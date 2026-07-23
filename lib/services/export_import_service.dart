import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:sm_crypto/sm_crypto.dart';

import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/data/database.dart';

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

    // 2. Build export payload
    final payload = {
      'version': 1,
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

  /// Import data from an encrypted .emdb file.
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

    // 2. Decrypt with SM4
    final key = SM4.createHexKey(key: password);
    String jsonString;
    try {
      jsonString = SM4.decrypt(data: encrypted, key: key);
    } catch (e) {
      throw ExportImportException('解密失败：密码错误或文件损坏');
    }

    // 3. Parse JSON
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw ExportImportException('文件格式错误：不是有效的 JSON 数据');
    }

    // 4. Validate version
    final version = payload['version'] as int?;
    if (version == null || version != 1) {
      throw ExportImportException('不支持的版本号: $version');
    }

    // 5. Import - merge into DB, skip duplicates by ID
    final importedRules = (payload['rules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final importedMatchItems = (payload['match_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final importedFileRecords = (payload['file_records'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    int ruleCount = 0, matchCount = 0, fileCount = 0;

    for (final data in importedRules) {
      final rule = Rule.fromMap(data);
      if (rule.id != null) {
        final existing = await _ruleRepo.getById(rule.id!);
        if (existing != null) continue; // skip duplicate
      }
      await _ruleRepo.insert(rule);
      ruleCount++;
    }

    for (final data in importedMatchItems) {
      final item = MatchItem.fromMap(data);
      if (item.id != null) {
        final existing = await _matchItemRepo.getById(item.id!);
        if (existing != null) continue; // skip duplicate
      }
      await _matchItemRepo.insert(item);
      matchCount++;
    }

    for (final data in importedFileRecords) {
      final record = FileRecord.fromMap(data);
      // ponytail: no getById on FileRecordRepository, check via direct DB access
      if (record.id != null) {
        final db = await DatabaseHelper.instance.database;
        final existing = await db.query(
          'file_records',
          where: 'id = ?',
          whereArgs: [record.id],
        );
        if (existing.isNotEmpty) continue;
      }
      await _fileRecordRepo.insert(record);
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