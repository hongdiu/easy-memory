import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:sm_crypto/sm_crypto.dart';

import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/file_record_repository.dart';

class ExportImportService {
  final RuleRepository _ruleRepo = RuleRepository();
  final MatchItemRepository _matchItemRepo = MatchItemRepository();
  final FileRecordRepository _fileRecordRepo = FileRecordRepository();

  /// Export all data to an encrypted .emdb file.
  /// Returns the saved file path on success.
  Future<String> exportData(String password) async {
    // 1. Fetch all data
    final rules = await _ruleRepo.getAll();

    final List<Map<String, dynamic>> rulesJson = [];
    final List<Map<String, dynamic>> matchItemsJson = [];
    final List<Map<String, dynamic>> fileRecordsJson = [];

    for (final rule in rules) {
      rulesJson.add(rule.toMap());
      if (rule.id == null) continue;
      final matchItems = await _matchItemRepo.getByRuleId(rule.id!);
      for (final item in matchItems) {
        matchItemsJson.add(item.toMap());
        if (item.id == null) continue;
        final files = await _fileRecordRepo.getByMatchItemId(item.id!);
        for (final file in files) {
          fileRecordsJson.add(file.toMap());
        }
      }
    }

    // 2. Build export payload (version 2 = natural-key merge support)
    final payload = {
      'version': 2,
      'exported_at': DateTime.now().toUtc().toIso8601String(),
      'rules': rulesJson,
      'match_items': matchItemsJson,
      'file_records': fileRecordsJson,
    };

    // 3. Encrypt with SM4
    final jsonString = jsonEncode(payload);
    final key = SM4.createHexKey(key: password);
    final encrypted = SM4.encrypt(data: jsonString, key: key);

    // 4. Save file via file_picker
    final path = await FilePicker.saveFile(
      dialogTitle: '导出数据',
      fileName: 'easy_memory_export.emdb',
      type: FileType.custom,
      allowedExtensions: ['emdb'],
    );

    if (path == null) {
      throw ExportCancelledException('用户取消了导出');
    }

    await File(path).writeAsString(encrypted, flush: true);
    return path;
  }

  /// Import data from an encrypted .emdb file (picked via file_picker).
  /// Returns a summary string of what was imported.
  Future<String> importData(String password) async {
    // 1. Pick file
    final result = await FilePicker.pickFiles(
      dialogTitle: '导入数据',
      type: FileType.custom,
      allowedExtensions: ['emdb'],
    );

    if (result == null || result.files.isEmpty) {
      throw ExportCancelledException('用户取消了导入');
    }

    final file = result.files.first;
    final filePath = file.path!;
    final encrypted = await File(filePath).readAsString();

    return importFromEncryptedString(encrypted, password);
  }

  /// Core import logic: decrypt, parse, and merge with natural-key matching.
  /// Extracted for testability — tests can call this directly.
  @visibleForTesting
  Future<String> importFromEncryptedString(
      String encrypted, String password) async {
    // 1. Decrypt with SM4
    final key = SM4.createHexKey(key: password);
    String jsonString;
    try {
      jsonString = SM4.decrypt(data: encrypted, key: key);
    } catch (e) {
      throw ExportImportException('解密失败：密码错误或文件损坏');
    }

    // 2. Parse JSON
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw ExportImportException('文件格式错误：不是有效的 JSON 数据');
    }

    // 3. Validate version
    final version = payload['version'] as int?;
    if (version == null || version < 1 || version > 2) {
      throw ExportImportException('不支持的版本号: $version');
    }

    // 4. Parse imported data
    final importedRules =
        (payload['rules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final importedMatchItems =
        (payload['match_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final importedFileRecords =
        (payload['file_records'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // 5. Merge with natural-key matching + FK remapping
    //
    // Strategy:
    //   - Rules:     match by regex_pattern only. If a local rule already has
    //                the same regex, merge into it and keep the LOCAL rule's
    //                name (当前端为准). Otherwise insert with the imported name.
    //   - MatchItems: match by (remapped_rule_id + match_value)
    //   - FileRecords: match by (remapped_match_item_id + full_path)
    //
    // old_id → new_id maps are maintained so FK references are remapped.

    int ruleCount = 0, matchCount = 0, fileCount = 0;

    // old rule.id → new/existing rule.id
    final Map<int, int> ruleIdMap = {};

    for (final data in importedRules) {
      final rule = Rule.fromMap(data);
      final oldId = rule.id;

      // Match by regex_pattern only: if the current app already has a rule
      // with the same regex (even if the name differs), merge into it.
      final existing = await _ruleRepo.findByPattern(rule.regexPattern);
      if (existing != null) {
        // Duplicate: use existing ID, skip insert.
        // Keep the local rule's name/fields (当前端为准) — do not overwrite.
        if (oldId != null) {
          ruleIdMap[oldId] = existing.id!;
        }
        continue;
      }

      // New rule: insert without ID (let DB auto-assign)
      // NOTE: copyWith(id: null) doesn't work — ?? retains the original id.
      final newRule = Rule(
        name: rule.name,
        regexPattern: rule.regexPattern,
        formatString: rule.formatString,
        scanDirectory: rule.scanDirectory,
        createdAt: rule.createdAt,
        updatedAt: rule.updatedAt,
      );
      final newId = await _ruleRepo.insert(newRule);
      if (oldId != null) {
        ruleIdMap[oldId] = newId;
      }
      ruleCount++;
    }

    // old match_item.id → new/existing match_item.id
    final Map<int, int> matchItemIdMap = {};

    for (final data in importedMatchItems) {
      var item = MatchItem.fromMap(data);
      final oldId = item.id;

      // Remap rule_id to the local ID
      final remappedRuleId = ruleIdMap[item.ruleId];
      if (remappedRuleId == null) {
        // Rule was not imported (shouldn't happen, but skip if orphaned)
        continue;
      }
      item = item.copyWith(ruleId: remappedRuleId);

      // Try to match by natural key (remapped_rule_id + match_value)
      final existing = await _matchItemRepo.findByRuleIdAndValue(
          remappedRuleId, item.matchValue);
      if (existing != null) {
        if (oldId != null) {
          matchItemIdMap[oldId] = existing.id!;
        }
        continue;
      }

      // New match item: insert without ID
      final newItem = MatchItem(
        ruleId: item.ruleId,
        matchValue: item.matchValue,
        createdAt: item.createdAt,
      );
      final newId = await _matchItemRepo.insert(newItem);
      if (oldId != null) {
        matchItemIdMap[oldId] = newId;
      }
      matchCount++;
    }

    for (final data in importedFileRecords) {
      var record = FileRecord.fromMap(data);

      // Remap match_item_id to the local ID
      final remappedItemId = matchItemIdMap[record.matchItemId];
      if (remappedItemId == null) {
        continue;
      }
      record = record.copyWith(matchItemId: remappedItemId);

      // Try to match by natural key (remapped_match_item_id + full_path)
      final existing = await _fileRecordRepo.findByMatchItemIdAndPath(
          remappedItemId, record.fullPath);
      if (existing != null) {
        continue;
      }

      // New file record: insert without ID
      await _fileRecordRepo.insert(FileRecord(
        matchItemId: record.matchItemId,
        fileName: record.fileName,
        fullPath: record.fullPath,
        directory: record.directory,
        scannedAt: record.scannedAt,
      ));
      fileCount++;
    }

    return '导入完成: $ruleCount 条规则, $matchCount 个匹配项, $fileCount 条文件记录';
  }
}

class ExportCancelledException implements Exception {
  final String message;
  const ExportCancelledException(this.message);
  @override
  String toString() => message;
}

class ExportImportException implements Exception {
  final String message;
  const ExportImportException(this.message);
  @override
  String toString() => message;
}