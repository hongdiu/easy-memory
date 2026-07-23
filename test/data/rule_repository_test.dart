import 'package:easy_memory/data/database.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late RuleRepository repo;

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
    repo = RuleRepository();
  });

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
  });

  Rule makeRule({String name = 'test_rule', String createdAt = '2024-01-01T00:00:00'}) {
    return Rule(
      name: name,
      regexPattern: r'\d+',
      formatString: '\$0',
      scanDirectory: '/tmp',
      createdAt: createdAt,
      updatedAt: '2024-01-01T00:00:00',
    );
  }

  test('insert and getById', () async {
    final rule = makeRule();
    final id = await repo.insert(rule);
    expect(id, greaterThan(0));

    final fetched = await repo.getById(id);
    expect(fetched, isNotNull);
    expect(fetched!.name, 'test_rule');
    expect(fetched.regexPattern, r'\d+');
    expect(fetched.formatString, '\$0');
  });

  test('getById returns null for nonexistent id', () async {
    final fetched = await repo.getById(999);
    expect(fetched, isNull);
  });

  test('getAll returns rules ordered by created_at DESC', () async {
    await repo.insert(makeRule(name: 'first', createdAt: '2024-01-01T00:00:00'));
    await repo.insert(makeRule(name: 'second', createdAt: '2024-01-02T00:00:00'));
    final all = await repo.getAll();
    expect(all.length, 2);
    // second has later created_at, so it appears first in DESC order
    expect(all[0].name, 'second');
    expect(all[1].name, 'first');
  });

  test('update modifies rule', () async {
    final id = await repo.insert(makeRule());
    final original = await repo.getById(id);
    final updated = original!.copyWith(name: 'updated_name');
    final rows = await repo.update(updated);
    expect(rows, 1);

    final fetched = await repo.getById(id);
    expect(fetched!.name, 'updated_name');
  });

  test('delete removes rule', () async {
    final id = await repo.insert(makeRule());
    final rows = await repo.delete(id);
    expect(rows, 1);

    final fetched = await repo.getById(id);
    expect(fetched, isNull);
  });

  test('deleteWithCascade removes rule, match_items, and file_records', () async {
    final ruleId = await repo.insert(makeRule());
    // Insert match_item manually
    final db = await DatabaseHelper.instance.database;
    final matchItemId = await db.insert('match_items', {
      'rule_id': ruleId,
      'match_value': 'TEST',
      'created_at': '2024-01-01T00:00:00',
    });
    // Insert file_record manually
    await db.insert('file_records', {
      'match_item_id': matchItemId,
      'file_name': 'test.txt',
      'full_path': '/tmp/test.txt',
      'directory': '/tmp',
      'scanned_at': '2024-01-01T00:00:00',
    });

    await repo.deleteWithCascade(ruleId);

    expect(await repo.getById(ruleId), isNull);
    final matchItems = await db.query('match_items', where: 'rule_id = ?', whereArgs: [ruleId]);
    expect(matchItems, isEmpty);
    final fileRecords = await db.query('file_records', where: 'match_item_id = ?', whereArgs: [matchItemId]);
    expect(fileRecords, isEmpty);
  });

  test('fromMap/toMap roundtrip', () {
    final rule = makeRule(name: 'roundtrip');
    final map = rule.toMap();
    final restored = Rule.fromMap(map);
    expect(restored.name, rule.name);
    expect(restored.regexPattern, rule.regexPattern);
    expect(restored.formatString, rule.formatString);
    expect(restored.scanDirectory, rule.scanDirectory);
  });
}
