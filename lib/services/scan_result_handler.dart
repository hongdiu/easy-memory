import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/services/file_scanner.dart';
import 'package:easy_memory/services/match_generator.dart';

class ScanResult {
  final int scannedFiles;
  final int matchedFiles;
  final int newMatchItems;

  const ScanResult({
    required this.scannedFiles,
    required this.matchedFiles,
    required this.newMatchItems,
  });
}

class ScanResultHandler {
  final FileScanner _scanner;
  final MatchGenerator _generator;
  final MatchItemRepository _matchItemRepo;
  final FileRecordRepository _fileRecordRepo;

  ScanResultHandler({
    FileScanner? scanner,
    MatchGenerator? generator,
    MatchItemRepository? matchItemRepo,
    FileRecordRepository? fileRecordRepo,
  })  : _scanner = scanner ?? FileScanner(),
        _generator = generator ?? MatchGenerator(),
        _matchItemRepo = matchItemRepo ?? MatchItemRepository(),
        _fileRecordRepo = fileRecordRepo ?? FileRecordRepository();

  /// Scan [directory] with [regexPattern], generate match values using
  /// [formatString], persist results, and return stats.
  Future<ScanResult> processScanResult(
    int ruleId,
    String directory,
    String regexPattern,
    String formatString,
  ) async {
    final results = _scanner.scanDirectory(directory, regexPattern);
    if (results.isEmpty) {
      return const ScanResult(
        scannedFiles: 0,
        matchedFiles: 0,
        newMatchItems: 0,
      );
    }

    // Pre-load existing match items for this rule to avoid repeated queries
    final existingItems = await _matchItemRepo.getByRuleId(ruleId);
    final existingByValue = <String, MatchItem>{};
    for (final item in existingItems) {
      existingByValue[item.matchValue] = item;
    }

    // Pre-load existing file records for dedup
    final existingFilePaths = <String, Set<String>>{};
    for (final item in existingItems) {
      final records = await _fileRecordRepo.getByMatchItemId(item.id!);
      existingFilePaths[item.matchValue] =
          records.map((r) => r.fullPath).toSet();
    }

    int newMatchItems = 0;

    for (final scanResult in results) {
      final matchValue = _generator.generateMatchValue(
        scanResult.match,
        formatString,
      );

      // Find or create MatchItem
      var matchItem = existingByValue[matchValue];
      if (matchItem == null) {
        final id = await _matchItemRepo.insert(MatchItem(
          ruleId: ruleId,
          matchValue: matchValue,
          createdAt: DateTime.now().toIso8601String(),
        ));
        matchItem = MatchItem(
          id: id,
          ruleId: ruleId,
          matchValue: matchValue,
          createdAt: DateTime.now().toIso8601String(),
        );
        existingByValue[matchValue] = matchItem;
        existingFilePaths[matchValue] = <String>{};
        newMatchItems++;
      }

      // Dedup: skip if already recorded
      final paths = existingFilePaths[matchValue]!;
      if (paths.contains(scanResult.fullPath)) continue;
      paths.add(scanResult.fullPath);

      await _fileRecordRepo.insert(FileRecord(
        matchItemId: matchItem.id!,
        fileName: scanResult.fileName,
        fullPath: scanResult.fullPath,
        directory: directory,
        scannedAt: DateTime.now().toIso8601String(),
      ));
    }

    return ScanResult(
      scannedFiles: results.length,
      matchedFiles: results.length,
      newMatchItems: newMatchItems,
    );
  }
}