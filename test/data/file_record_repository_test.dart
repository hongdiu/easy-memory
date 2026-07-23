import 'package:easy_memory/data/database.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late FileRecordRepository repo;
  late MatchItemRepository matchRepo;
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
    repo = FileRecordRepository();
    matchRepo = MatchItemRepository();
    ruleRepo = RuleRepository();
  });

  tearDown(() async {
    final db = await DatabaseHelper.instance.database;
    await db.close();
  });

  Future<int> insertTestMatchItem() async {
    final ruleId = await ruleRepo.insert(Rule(
      name: 'test_rule',
      regexPattern: r'\d+',
      createdAt: '2024-01-01T00:00:00',
      updatedAt: '2024-01-01T00:00:00',
    ));
    return await matchRepo.insert(MatchItem(
      ruleId: ruleId,
      matchValue: 'TEST',
      createdAt: '2024-01-01T00:00:00',
    ));
  }

  FileRecord makeRecord(int matchItemId, {String fileName = 'test.txt'}) {
    return FileRecord(
      matchItemId: matchItemId,
      fileName: fileName,
      fullPath: '/tmp/$fileName',
      directory: '/tmp',
      scannedAt: '2024-01-01T00:00:00',
    );
  }

  test('insert and getByMatchItemId', () async {
    final matchItemId = await insertTestMatchItem();
    final id = await repo.insert(makeRecord(matchItemId));
    expect(id, greaterThan(0));

    final records = await repo.getByMatchItemId(matchItemId);
    expect(records.length, 1);
    expect(records.first.fileName, 'test.txt');
    expect(records.first.fullPath, '/tmp/test.txt');
  });

  test('getByMatchItemId returns empty for no records', () async {
    final records = await repo.getByMatchItemId(999);
    expect(records, isEmpty);
  });

  test('delete removes file record', () async {
    final matchItemId = await insertTestMatchItem();
    final id = await repo.insert(makeRecord(matchItemId));
    final deleted = await repo.delete(id);
    expect(deleted, 1);

    final records = await repo.getByMatchItemId(matchItemId);
    expect(records, isEmpty);
  });

  test('deleteByMatchItemId removes all records for a match item', () async {
    final matchItemId = await insertTestMatchItem();
    await repo.insert(makeRecord(matchItemId, fileName: 'a.txt'));
    await repo.insert(makeRecord(matchItemId, fileName: 'b.txt'));

    await repo.deleteByMatchItemId(matchItemId);
    final records = await repo.getByMatchItemId(matchItemId);
    expect(records, isEmpty);
  });

  test('fromMap/toMap roundtrip', () {
    final record = makeRecord(1);
    final map = record.toMap();
    final restored = FileRecord.fromMap(map);
    expect(restored.matchItemId, record.matchItemId);
    expect(restored.fileName, record.fileName);
    expect(restored.fullPath, record.fullPath);
    expect(restored.directory, record.directory);
  });
}
