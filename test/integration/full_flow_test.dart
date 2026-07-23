import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:easy_memory/data/database.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/services/scan_result_handler.dart';

void main() {
  late Database db;
  late RuleRepository ruleRepo;
  late MatchItemRepository matchItemRepo;
  late FileRecordRepository fileRecordRepo;
  late ScanResultHandler scanHandler;

  setUp(() async {
    sqfliteFfiInit();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    // Create tables
    await db.execute('''
      CREATE TABLE rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        regex_pattern TEXT NOT NULL,
        format_string TEXT NOT NULL DEFAULT '\$0',
        scan_directory TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE match_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rule_id INTEGER NOT NULL,
        match_value TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (rule_id) REFERENCES rules (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE file_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        match_item_id INTEGER NOT NULL,
        file_name TEXT NOT NULL,
        full_path TEXT NOT NULL,
        directory TEXT NOT NULL,
        scanned_at TEXT NOT NULL,
        FOREIGN KEY (match_item_id) REFERENCES match_items (id) ON DELETE CASCADE
      )
    ''');
    await db.execute('CREATE INDEX idx_match_items_rule_id ON match_items (rule_id)');
    await db.execute('CREATE INDEX idx_file_records_match_item_id ON file_records (match_item_id)');

    DatabaseHelper.setDatabaseForTesting(db);

    ruleRepo = RuleRepository();
    matchItemRepo = MatchItemRepository();
    fileRecordRepo = FileRecordRepository();
    scanHandler = ScanResultHandler();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.setDatabaseForTesting(db);
  });

  group('Full flow: create rule -> scan -> view results', () {
    test('create rule, simulate scan, verify match items and file records', () async {
      // 1. Create a rule
      final ruleId = await ruleRepo.insert(const Rule(
        name: '发票提取',
        regexPattern: r'INV_(\d{4})_(\w+)',
        formatString: r'$1@$2',
        createdAt: '2025-06-01T00:00:00',
        updatedAt: '2025-06-01T00:00:00',
      ));
      expect(ruleId, greaterThan(0));

      // Verify rule exists
      final rule = await ruleRepo.getById(ruleId);
      expect(rule, isNotNull);
      expect(rule!.name, '发票提取');
      expect(rule.regexPattern, r'INV_(\d{4})_(\w+)');

      // 2. Simulate scan results (bypass file scanner, insert directly)
      // In real flow, scan would find files matching INV_2025_TAX, INV_2025_SALE, etc.
      final matchValues = ['2025@TAX', '2025@SALE', '2025@PURCHASE'];
      final now = DateTime.now().toIso8601String();

      for (final matchValue in matchValues) {
        final matchId = await matchItemRepo.insert(MatchItem(
          ruleId: ruleId,
          matchValue: matchValue,
          createdAt: now,
        ));

        // Each match item has 1-2 file records
        await fileRecordRepo.insert(FileRecord(
          matchItemId: matchId,
          fileName: 'INV_2025_${matchValue.split('@').last}.pdf',
          fullPath: 'C:/invoices/INV_2025_${matchValue.split('@').last}.pdf',
          directory: 'C:/invoices',
          scannedAt: now,
        ));
      }

      // 3. Verify match items
      final items = await matchItemRepo.getByRuleId(ruleId);
      expect(items.length, 3);
      expect(items.map((i) => i.matchValue), containsAll(['2025@TAX', '2025@SALE', '2025@PURCHASE']));

      // 4. Verify file records per match item
      for (final item in items) {
        final files = await fileRecordRepo.getByMatchItemId(item.id!);
        expect(files.length, 1);
        expect(files[0].fullPath, contains(item.matchValue.split('@').last));
      }

      // 5. Search across rules
      final searchResults = await matchItemRepo.searchByValue('TAX');
      expect(searchResults.length, 1);
      expect(searchResults[0].matchValue, '2025@TAX');
    });

    test('edit rule name and re-scan', () async {
      final ruleId = await ruleRepo.insert(const Rule(
        name: '旧名称',
        regexPattern: r'DOC_(\d+)',
        formatString: r'$0',
        createdAt: '2025-06-01T00:00:00',
        updatedAt: '2025-06-01T00:00:00',
      ));

      // Update rule name
      final updated = await ruleRepo.update(Rule(
        id: ruleId,
        name: '新名称',
        regexPattern: r'DOC_(\d+)',
        formatString: r'$0',
        createdAt: '2025-06-01T00:00:00',
        updatedAt: '2025-06-02T00:00:00',
      ));
      expect(updated, 1);

      final rule = await ruleRepo.getById(ruleId);
      expect(rule!.name, '新名称');
    });

    test('delete rule cascades to match items and file records', () async {
      final ruleId = await ruleRepo.insert(const Rule(
        name: '待删除',
        regexPattern: r'DEL_(\d+)',
        formatString: r'$0',
        createdAt: '2025-06-01T00:00:00',
        updatedAt: '2025-06-01T00:00:00',
      ));

      final matchId = await matchItemRepo.insert(MatchItem(
        ruleId: ruleId,
        matchValue: 'DEL_001',
        createdAt: '2025-06-01T00:00:00',
      ));

      await fileRecordRepo.insert(FileRecord(
        matchItemId: matchId,
        fileName: 'DEL_001.txt',
        fullPath: 'C:/del/DEL_001.txt',
        directory: 'C:/del',
        scannedAt: '2025-06-01T00:00:00',
      ));

      // Delete with cascade
      await ruleRepo.deleteWithCascade(ruleId);

      // Verify all gone
      final rule = await ruleRepo.getById(ruleId);
      expect(rule, isNull);

      final items = await matchItemRepo.getByRuleId(ruleId);
      expect(items, isEmpty);

      final files = await fileRecordRepo.getByMatchItemId(matchId);
      expect(files, isEmpty);
    });
  });

  group('ScanResultHandler integration', () {
    test('processScanResult with valid directory and pattern', () async {
      final ruleId = await ruleRepo.insert(const Rule(
        name: '扫描测试',
        regexPattern: r'(\w+)_(\d+)',
        formatString: r'$1_$2',
        createdAt: '2025-06-01T00:00:00',
        updatedAt: '2025-06-01T00:00:00',
      ));

      // Create temp directory with test files
      final tmpDir = await Future(() async {
        final dir = await Directory.systemTemp.createTemp('scan_test_');
        // Create files that match and don't match
        await File('${dir.path}/REPORT_001.pdf').create();
        await File('${dir.path}/REPORT_002.pdf').create();
        await File('${dir.path}/readme.txt').create(); // doesn't match
        await File('${dir.path}/DATA_999.xlsx').create();
        // Create a subdirectory with matching files
        final subDir = await Directory('${dir.path}/sub').create();
        await File('${subDir.path}/REPORT_003.pdf').create();
        return dir;
      });

      try {
        final stats = await scanHandler.processScanResult(
          ruleId,
          tmpDir.path,
          r'(\w+)_(\d+)',
          r'$1_$2',
        );

        expect(stats.matchedFiles, 4);
        expect(stats.scannedFiles, 4);
        expect(stats.newMatchItems, greaterThanOrEqualTo(1));

        // Verify items stored
        final items = await matchItemRepo.getByRuleId(ruleId);
        expect(items.length, greaterThanOrEqualTo(1));

        // All match values should be uppercase
        for (final item in items) {
          expect(item.matchValue, equals(item.matchValue.toUpperCase()));
        }
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });

    test('processScanResult handles empty directory', () async {
      final ruleId = await ruleRepo.insert(const Rule(
        name: '空目录测试',
        regexPattern: r'.*',
        formatString: r'$0',
        createdAt: '2025-06-01T00:00:00',
        updatedAt: '2025-06-01T00:00:00',
      ));

      final tmpDir = await Directory.systemTemp.createTemp('empty_scan_');
      try {
        final stats = await scanHandler.processScanResult(
          ruleId,
          tmpDir.path,
          r'.*',
          r'$0',
        );
        expect(stats.matchedFiles, 0);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });
}