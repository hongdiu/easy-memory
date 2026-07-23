import 'dart:io';

import 'package:easy_memory/data/database.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/services/scan_result_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late RuleRepository ruleRepo;
  late MatchItemRepository matchItemRepo;
  late FileRecordRepository fileRecordRepo;
  late ScanResultHandler handler;
  late Directory tempDir;

  setUp(() async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
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
            CREATE INDEX idx_match_items_rule_id ON match_items (rule_id)
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
          await db.execute('''
            CREATE INDEX idx_file_records_match_item_id ON file_records (match_item_id)
          ''');
        },
      ),
    );
    DatabaseHelper.setDatabaseForTesting(db);

    ruleRepo = RuleRepository();
    matchItemRepo = MatchItemRepository();
    fileRecordRepo = FileRecordRepository();
    handler = ScanResultHandler(
      matchItemRepo: matchItemRepo,
      fileRecordRepo: fileRecordRepo,
    );

    tempDir = Directory.systemTemp.createTempSync('scan_result_test_');
  });

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ScanResultHandler', () {
    test('processes scan and writes match items and file records', () async {
      // Create a rule
      final ruleId = await ruleRepo.insert(Rule(
        name: 'Test Rule',
        regexPattern: r'(\d{3})_.*\.txt',
        formatString: r'$1',
        scanDirectory: tempDir.path,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      // Create test files
      File('${tempDir.path}/001_hello.txt').createSync();
      File('${tempDir.path}/002_world.txt').createSync();
      File('${tempDir.path}/readme.md').createSync();

      final result = await handler.processScanResult(
        ruleId,
        tempDir.path,
        r'(\d{3})_.*\.txt',
        r'$1',
      );

      expect(result.matchedFiles, 2);
      expect(result.newMatchItems, 2);

      // Verify match items
      final matchItems = await matchItemRepo.getByRuleId(ruleId);
      expect(matchItems.length, 2);
      final values = matchItems.map((m) => m.matchValue).toSet();
      expect(values, containsAll(['001', '002']));

      // Verify file records
      for (final item in matchItems) {
        final records = await fileRecordRepo.getByMatchItemId(item.id!);
        expect(records.length, 1);
        expect(records[0].directory, tempDir.path);
        if (item.matchValue == '001') {
          expect(records[0].fileName, '001_hello.txt');
        } else {
          expect(records[0].fileName, '002_world.txt');
        }
      }
    });

    test('deduplicates file records by full path', () async {
      final ruleId = await ruleRepo.insert(Rule(
        name: 'Test Rule',
        regexPattern: r'(\d{3})_.*\.txt',
        formatString: r'$1',
        scanDirectory: tempDir.path,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      File('${tempDir.path}/001_hello.txt').createSync();

      // Scan twice
      await handler.processScanResult(
        ruleId,
        tempDir.path,
        r'(\d{3})_.*\.txt',
        r'$1',
      );
      final result = await handler.processScanResult(
        ruleId,
        tempDir.path,
        r'(\d{3})_.*\.txt',
        r'$1',
      );

      // Should not create duplicate match items or file records
      expect(result.newMatchItems, 0);

      final matchItems = await matchItemRepo.getByRuleId(ruleId);
      expect(matchItems.length, 1);
      expect(matchItems[0].matchValue, '001');

      final records = await fileRecordRepo.getByMatchItemId(matchItems[0].id!);
      expect(records.length, 1);
    });

    test('returns zero stats when no files match', () async {
      final ruleId = await ruleRepo.insert(Rule(
        name: 'Test Rule',
        regexPattern: r'(\d{3})_.*\.txt',
        formatString: r'$1',
        scanDirectory: tempDir.path,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      File('${tempDir.path}/readme.md').createSync();

      final result = await handler.processScanResult(
        ruleId,
        tempDir.path,
        r'(\d{3})_.*\.txt',
        r'$1',
      );

      expect(result.matchedFiles, 0);
      expect(result.newMatchItems, 0);
    });

    test('same match value from different files creates one match item', () async {
      final ruleId = await ruleRepo.insert(Rule(
        name: 'Test Rule',
        regexPattern: r'(\d{3})_.*\.txt',
        formatString: r'$1',
        scanDirectory: tempDir.path,
        createdAt: DateTime.now().toIso8601String(),
        updatedAt: DateTime.now().toIso8601String(),
      ));

      // Two files with same capture group value
      File('${tempDir.path}/001_hello.txt').createSync();
      File('${tempDir.path}/001_world.txt').createSync();

      final result = await handler.processScanResult(
        ruleId,
        tempDir.path,
        r'(\d{3})_.*\.txt',
        r'$1',
      );

      // Only one new match item (value '001'), but 2 matched files
      expect(result.matchedFiles, 2);
      expect(result.newMatchItems, 1);

      final matchItems = await matchItemRepo.getByRuleId(ruleId);
      expect(matchItems.length, 1);
      expect(matchItems[0].matchValue, '001');

      // Two file records for the same match item
      final records = await fileRecordRepo.getByMatchItemId(matchItems[0].id!);
      expect(records.length, 2);
    });
  });
}