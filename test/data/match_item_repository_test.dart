import 'package:easy_memory/data/database.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late MatchItemRepository repo;
  late RuleRepository ruleRepo;

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
    repo = MatchItemRepository();
    ruleRepo = RuleRepository();
  });

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
  });

  Future<int> insertTestRule() async {
    return await ruleRepo.insert(Rule(
      name: 'test_rule',
      regexPattern: r'\d+',
      formatString: '\$0',
      createdAt: '2024-01-01T00:00:00',
      updatedAt: '2024-01-01T00:00:00',
    ));
  }

  MatchItem makeItem(int ruleId, {String value = 'TEST'}) {
    return MatchItem(
      ruleId: ruleId,
      matchValue: value,
      createdAt: '2024-01-01T00:00:00',
    );
  }

  test('insert and getById', () async {
    final ruleId = await insertTestRule();
    final id = await repo.insert(makeItem(ruleId));
    expect(id, greaterThan(0));

    final fetched = await repo.getById(id);
    expect(fetched, isNotNull);
    expect(fetched!.matchValue, 'TEST');
    expect(fetched.ruleId, ruleId);
  });

  test('getById returns null for nonexistent id', () async {
    final fetched = await repo.getById(999);
    expect(fetched, isNull);
  });

  test('getByRuleId returns items for specific rule', () async {
    final ruleId = await insertTestRule();
    await repo.insert(makeItem(ruleId, value: 'A'));
    await repo.insert(makeItem(ruleId, value: 'B'));

    final items = await repo.getByRuleId(ruleId);
    expect(items.length, 2);
  });

  test('searchByValue finds matching values across rules', () async {
    final ruleId = await insertTestRule();
    await repo.insert(makeItem(ruleId, value: 'HELLO'));
    await repo.insert(makeItem(ruleId, value: 'WORLD'));
    await repo.insert(makeItem(ruleId, value: 'HELLO_WORLD'));

    final results = await repo.searchByValue('HELLO');
    expect(results.length, 2);
    expect(results.every((m) => m.matchValue.contains('HELLO')), isTrue);
  });

  test('searchByValue is case sensitive (values stored uppercase)', () async {
    final ruleId = await insertTestRule();
    await repo.insert(makeItem(ruleId, value: 'UPPER'));

    final results = await repo.searchByValue('UPPER');
    expect(results.length, 1);
  });

  test('delete removes match_item', () async {
    final ruleId = await insertTestRule();
    final id = await repo.insert(makeItem(ruleId));
    await repo.delete(id);

    final fetched = await repo.getById(id);
    expect(fetched, isNull);
  });

  test('deleteByRuleId removes all items for a rule', () async {
    final ruleId = await insertTestRule();
    await repo.insert(makeItem(ruleId, value: 'A'));
    await repo.insert(makeItem(ruleId, value: 'B'));

    await repo.deleteByRuleId(ruleId);
    final items = await repo.getByRuleId(ruleId);
    expect(items, isEmpty);
  });

  test('fromMap/toMap roundtrip', () {
    final item = makeItem(1);
    final map = item.toMap();
    final restored = MatchItem.fromMap(map);
    expect(restored.ruleId, item.ruleId);
    expect(restored.matchValue, item.matchValue);
  });
}
