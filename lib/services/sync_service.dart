import 'dart:convert';
import 'dart:io';

import '../data/file_record_repository.dart';
import '../data/match_item_repository.dart';
import '../data/rule_repository.dart';
import '../models/file_record.dart';
import '../models/match_item.dart';
import '../models/remote_endpoint.dart';
import '../models/rule.dart';

/// Progress of a sync operation.
class SyncProgress {
  final int percent;
  final String message;

  const SyncProgress({required this.percent, required this.message});
}

/// Result of a sync operation.
class SyncResult {
  final bool success;
  final String message;
  final int rulesCount;
  final int matchItemsCount;
  final int fileRecordsCount;

  const SyncResult({
    required this.success,
    required this.message,
    this.rulesCount = 0,
    this.matchItemsCount = 0,
    this.fileRecordsCount = 0,
  });
}

/// Client-side sync service: pulls data from a remote device's web server
/// and merges it into the local database using natural-key matching.
///
/// Sync direction is arbitrary — any device (Android / Windows / Linux / macOS)
/// can sync FROM any other device that runs the WebServerService.
class SyncService {
  final RuleRepository _ruleRepo = RuleRepository();
  final MatchItemRepository _matchItemRepo = MatchItemRepository();
  final FileRecordRepository _fileRecordRepo = FileRecordRepository();

  /// Fetch JSON from [url] using the [endpoint]'s apiKey.
  Future<Map<String, dynamic>> _fetchJson(
      RemoteEndpoint endpoint, String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      if (endpoint.apiKey.isNotEmpty) {
        request.headers.set('x-api-key', endpoint.apiKey);
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        final snippet = body.length > 200 ? body.substring(0, 200) : body;
        throw HttpException('HTTP ${response.statusCode}: $snippet');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// Sync all data from [endpoint] into the local database.
  ///
  /// [onProgress] is called after each step for UI updates.
  Future<SyncResult> sync(
    RemoteEndpoint endpoint, {
    void Function(SyncProgress)? onProgress,
  }) async {
    try {
      onProgress?.call(const SyncProgress(
        percent: 0,
        message: '开始同步...',
      ));

      // ——————————————————————————————————————————————
      // Step 1: Fetch rules + match_items (0% → 10%)
      // ——————————————————————————————————————————————
      final baseUrl = endpoint.url;
      final data = await _fetchJson(endpoint, '$baseUrl/api/sync/data');

      final importedRules =
          (data['rules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final importedMatchItems =
          (data['match_items'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      onProgress?.call(SyncProgress(
        percent: 10,
        message: '下载规则 (${importedRules.length} 条)...',
      ));

      // ——————————————————————————————————————————————
      // Step 2: Merge rules (10% → 15%)
      //   Match by regex_pattern. If exists → skip (local wins).
      //   Otherwise → insert with new ID.
      // ——————————————————————————————————————————————
      final Map<int, int> ruleIdMap = {};
      int rulesMerged = 0;

      for (final data in importedRules) {
        final rule = Rule.fromMap(data);
        final oldId = rule.id;

        final existing = await _ruleRepo.findByPattern(rule.regexPattern);
        if (existing != null) {
          if (oldId != null) ruleIdMap[oldId] = existing.id!;
          continue;
        }

        final newRule = Rule(
          name: rule.name,
          regexPattern: rule.regexPattern,
          formatString: rule.formatString,
          scanDirectory: rule.scanDirectory,
          createdAt: rule.createdAt,
          updatedAt: rule.updatedAt,
        );
        final newId = await _ruleRepo.insert(newRule);
        if (oldId != null) ruleIdMap[oldId] = newId;
        rulesMerged++;
      }

      onProgress?.call(SyncProgress(
        percent: 15,
        message: '合并匹配项 (${importedMatchItems.length} 条)...',
      ));

      // ——————————————————————————————————————————————
      // Step 3: Merge match_items (15% → 20%)
      //   Match by (remapped_rule_id + match_value).
      //   If exists → skip. Otherwise → insert.
      // ——————————————————————————————————————————————
      final Map<int, int> matchItemIdMap = {};
      int matchItemsMerged = 0;

      for (final data in importedMatchItems) {
        var item = MatchItem.fromMap(data);
        final oldId = item.id;

        final remappedRuleId = ruleIdMap[item.ruleId];
        if (remappedRuleId == null) continue;

        item = item.copyWith(ruleId: remappedRuleId);

        final existing = await _matchItemRepo.findByRuleIdAndValue(
            remappedRuleId, item.matchValue);
        if (existing != null) {
          if (oldId != null) matchItemIdMap[oldId] = existing.id!;
          continue;
        }

        final newItem = MatchItem(
          ruleId: item.ruleId,
          matchValue: item.matchValue,
          createdAt: item.createdAt,
        );
        final newId = await _matchItemRepo.insert(newItem);
        if (oldId != null) matchItemIdMap[oldId] = newId;
        matchItemsMerged++;
      }

      // ——————————————————————————————————————————————
      // Step 4: Get total file record count (20% → 25%)
      // ——————————————————————————————————————————————
      final countResp = await _fetchJson(
          endpoint, '$baseUrl/api/sync/records?offset=0&limit=1');
      final totalRecords = countResp['total'] as int? ?? 0;

      onProgress?.call(SyncProgress(
        percent: 25,
        message: '同步文件记录 (共 $totalRecords 条)...',
      ));

      // ——————————————————————————————————————————————
      // Step 5: Fetch + merge file records in batches (25% → 90%)
      //   Match by (remapped_match_item_id + full_path).
      //   If exists → skip. Otherwise → insert.
      //
      //   Progress formula:
      //     batch_progress = 25 + (batch_index / total_batches) * 65
      // ——————————————————————————————————————————————
      const batchSize = 100;
      int fileRecordsMerged = 0;
      int offset = 0;

      while (offset < totalRecords) {
        final batchResp = await _fetchJson(endpoint,
            '$baseUrl/api/sync/records?offset=$offset&limit=$batchSize');
        final batchRecords =
            (batchResp['records'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        for (final data in batchRecords) {
          var record = FileRecord.fromMap(data);

          final remappedItemId = matchItemIdMap[record.matchItemId];
          if (remappedItemId == null) continue;

          record = record.copyWith(matchItemId: remappedItemId);

          final existing = await _fileRecordRepo.findByMatchItemIdAndPath(
              remappedItemId, record.fullPath);
          if (existing != null) continue;

          await _fileRecordRepo.insert(FileRecord(
            matchItemId: record.matchItemId,
            fileName: record.fileName,
            fullPath: record.fullPath,
            directory: record.directory,
            fileSize: record.fileSize,
            scannedAt: record.scannedAt,
          ));
          fileRecordsMerged++;
        }

        offset += batchSize;

        // Clamp progress to 25-90%
        final totalBatches =
            (totalRecords + batchSize - 1) ~/ batchSize;
        final currentBatch = offset ~/ batchSize;
        final batchPercent = totalBatches > 0
            ? (currentBatch * 65 / totalBatches).round()
            : 65;
        final percent = (25 + batchPercent).clamp(25, 90);

        onProgress?.call(SyncProgress(
          percent: percent,
          message: '同步文件记录 ($offset / $totalRecords)...',
        ));
      }

      // ——————————————————————————————————————————————
      // Done
      // ——————————————————————————————————————————————
      final summary =
          '同步完成: $rulesMerged 条规则, $matchItemsMerged 个匹配项, $fileRecordsMerged 条文件记录';

      onProgress?.call(SyncProgress(percent: 100, message: summary));

      return SyncResult(
        success: true,
        message: summary,
        rulesCount: rulesMerged,
        matchItemsCount: matchItemsMerged,
        fileRecordsCount: fileRecordsMerged,
      );
    } catch (e) {
      final errorMsg = '同步失败: $e';

      onProgress?.call(SyncProgress(
        percent: 0,
        message: errorMsg,
      ));

      return SyncResult(success: false, message: errorMsg);
    }
  }
}