import 'dart:convert';

import 'package:easy_memory/data/database.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/services/export_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sm_crypto/sm_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Helper to encrypt a json-encodable payload as the export would produce.
String buildEncryptedPayload(Map<String, dynamic> payload, String password) {
  final jsonString = jsonEncode(payload);
  final key = SM4.createHexKey(key: password);
  return SM4.encrypt(data: jsonString, key: key);
}

void main() {
  sqfliteFfiInit();

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
            file_size INTEGER,
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
  });

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
  });

  Rule makeRule(
      String name, String pattern, {int? id, String ts = '2024-01-01T00:00:00'}) {
    return Rule(
      id: id,
      name: name,
      regexPattern: pattern,
      createdAt: ts,
      updatedAt: ts,
    );
  }

  Map<String, dynamic> payloadWith(
      {List<Map<String, dynamic>> rules = const [],
      List<Map<String, dynamic>> matchItems = const [],
      List<Map<String, dynamic>> fileRecords = const [],
      int version = 2}) {
    return {
      'version': version,
      'exported_at': '2024-01-01T00:00:00.000Z',
      'rules': rules,
      'match_items': matchItems,
      'file_records': fileRecords,
    };
  }

  test('import with wrong password fails with ExportImportException', () async {
    final service = ExportImportService();
    final encrypted = buildEncryptedPayload(
        payloadWith(rules: [makeRule('R1', r'\d+').toMap()]), 'correct');
    try {
      await service.importFromEncryptedString(encrypted, 'wrong');
      fail('Expected ExportImportException');
    } catch (e) {
      expect(e, isA<ExportImportException>());
    }
  });

  test('wrong version is rejected', () async {
    final service = ExportImportService();
    final encrypted =
        buildEncryptedPayload(payloadWith(version: 99), 'pw');
    try {
      await service.importFromEncryptedString(encrypted, 'pw');
      fail('Expected ExportImportException');
    } catch (e) {
      expect(e, isA<ExportImportException>());
    }
  });

  test('new rules, match items and file records are imported', () async {
    final service = ExportImportService();

    // Simulate a real export payload: all records include their original IDs,
    // which the import logic remaps to local auto-increment IDs.
    final encrypted = buildEncryptedPayload(
      payloadWith(
        rules: [
          makeRule('PDF 检查', r'\.pdf$', id: 1).toMap(),
        ],
        matchItems: [
          {'id': 1, 'rule_id': 1, 'match_value': 'report_2024', 'created_at': '2024-01-01'},
        ],
        fileRecords: [
          {
            'id': 1,
            'match_item_id': 1,
            'file_name': 'a.pdf',
            'full_path': '/tmp/a.pdf',
            'directory': '/tmp',
            'scanned_at': '2024-01-01',
          },
        ],
      ),
      'pw',
    );

    await service.importFromEncryptedString(encrypted, 'pw');

    final rules = await RuleRepository().getAll();
    expect(rules.length, 1);

    final matchItems =
        await MatchItemRepository().getByRuleId(rules.first.id!);
    expect(matchItems.length, 1);

    final fileRecords =
        await FileRecordRepository().getByMatchItemId(matchItems.first.id!);
    expect(fileRecords.length, 1);
    expect(fileRecords.first.fullPath, '/tmp/a.pdf');
  });

  test('cross-device merge: same-name rule (ID collision) is NOT duplicated', () async {
    final ruleRepo = RuleRepository();
    // Device A already has rule 'PDF 检查' (local id, e.g. 1). Capture its local id.
    final localId = await ruleRepo.insert(makeRule('PDF 检查', r'\.pdf$'));
    expect(localId, 1);

    final service = ExportImportService();

    // Device B payload: rule id=1 named 'PDF 检查' — same regex_pattern as local, ID collides.
    final encrypted = buildEncryptedPayload(
      payloadWith(
        rules: [makeRule('PDF 检查', r'\.pdf$', id: 1).toMap()],
      ),
      'pw',
    );

    final summary = await service.importFromEncryptedString(encrypted, 'pw');
    expect(summary, contains('0 条规则'));

    // Still only one rule with the same regex_pattern.
    final rules = await ruleRepo.getAll();
    expect(rules.length, 1);
    final existing = await ruleRepo.findByPattern(r'\.pdf$');
    expect(existing, isNotNull);
    expect(existing!.id, localId);
    // Local rule's name is preserved (当前端为准)
    expect(existing.name, 'PDF 检查');
  });

  test('cross-device merge: different rule with SAME id survives (no data loss)', () async {
    final ruleRepo = RuleRepository();
    // Device A has 'PDF 检查' → id=1.
    final localId = await ruleRepo.insert(makeRule('PDF 检查', r'\.pdf$'));
    expect(localId, 1);

    final service = ExportImportService();

    // Device B also uses id=1 but for a completely different rule '图片检查'.
    final encrypted = buildEncryptedPayload(
      payloadWith(
        rules: [makeRule('图片检查', r'\.(jpg|png)$', id: 1).toMap()],
      ),
      'pw',
    );

    await service.importFromEncryptedString(encrypted, 'pw');

    // Both rules must coexist despite the shared id=1.
    final rules = await ruleRepo.getAll();
    expect(rules.length, 2);
  });

  test('cross-device merge: same pattern, DIFFERENT name — merge into local, keep local name', () async {
    final ruleRepo = RuleRepository();
    // Local: rule named 'PDF检查' with pattern \.pdf$
    final localId = await ruleRepo.insert(makeRule('PDF检查', r'\.pdf$'));
    expect(localId, 1);

    final service = ExportImportService();

    // Imported: same pattern \.pdf$ but named 'PDF Document Check' (different name).
    final encrypted = buildEncryptedPayload(
      payloadWith(
        rules: [makeRule('PDF Document Check', r'\.pdf$', id: 10).toMap()],
      ),
      'pw',
    );

    final summary = await service.importFromEncryptedString(encrypted, 'pw');
    expect(summary, contains('0 条规则'));

    // Still only one rule — merged by pattern.
    final rules = await ruleRepo.getAll();
    expect(rules.length, 1);
    // Local name is kept (当前端为准), not overwritten by imported name.
    expect(rules.first.name, 'PDF检查');
    expect(rules.first.id, localId);
  });

  test('cross-device merge: new pattern is inserted with imported name', () async {
    final ruleRepo = RuleRepository();
    // Local: rule with pattern \.pdf$
    await ruleRepo.insert(makeRule('PDF检查', r'\.pdf$'));

    final service = ExportImportService();

    // Imported: different pattern \.jpg$ — no local match, should insert new rule
    // with the imported name '图片检查'.
    final encrypted = buildEncryptedPayload(
      payloadWith(
        rules: [makeRule('图片检查', r'\.jpg$', id: 2).toMap()],
      ),
      'pw',
    );

    final summary = await service.importFromEncryptedString(encrypted, 'pw');
    expect(summary, contains('1 条规则'));

    final rules = await ruleRepo.getAll();
    expect(rules.length, 2);
    expect(rules.any((r) => r.name == 'PDF检查'), isTrue);
    // Imported rule uses its own name since no local rule matched.
    expect(rules.any((r) => r.name == '图片检查'), isTrue);
  });

  test('match items remap rule_id to the local rule id', () async {
    final ruleRepo = RuleRepository();
    final matchRepo = MatchItemRepository();
    // Device A: 'PDF 检查' gets local id 1.
    final localRuleId = await ruleRepo.insert(makeRule('PDF 检查', r'\.pdf$'));
    expect(localRuleId, 1);

    final service = ExportImportService();

    // Device B: same rule 'PDF 检查' (id=2 locally), with a new match item.
    final encrypted = buildEncryptedPayload(
      payloadWith(
        rules: [makeRule('PDF 检查', r'\.pdf$', id: 2).toMap()],
        matchItems: [
          {'rule_id': 2, 'match_value': 'invoice_2024', 'created_at': '2024-01-01'},
        ],
      ),
      'pw',
    );

    await service.importFromEncryptedString(encrypted, 'pw');

    final items = await matchRepo.getByRuleId(localRuleId);
    expect(items.length, 1);
    expect(items.first.ruleId, localRuleId);
    expect(items.first.matchValue, 'invoice_2024');
  });

  test('duplicate match item (same rule + value) is skipped', () async {
    final ruleRepo = RuleRepository();
    final matchRepo = MatchItemRepository();
    final ruleId = await ruleRepo.insert(makeRule('PDF 检查', r'\.pdf$'));
    await matchRepo.insert(MatchItem(
        ruleId: ruleId, matchValue: 'invoice_2024', createdAt: '2024-01-01'));

    final service = ExportImportService();
    final encrypted = buildEncryptedPayload(
      payloadWith(
        rules: [makeRule('PDF 检查', r'\.pdf$', id: 1).toMap()],
        matchItems: [
          {'rule_id': 1, 'match_value': 'invoice_2024', 'created_at': '2024-01-01'},
        ],
        fileRecords: [
          {
            'match_item_id': 1,
            'file_name': 'b.pdf',
            'full_path': '/tmp/b.pdf',
            'directory': '/tmp',
            'scanned_at': '2024-01-01',
          },
        ],
      ),
      'pw',
    );

    final summary = await service.importFromEncryptedString(encrypted, 'pw');
    expect(summary, contains('0 个匹配项'));

    final items = await matchRepo.getByRuleId(ruleId);
    expect(items.length, 1);
  });
}