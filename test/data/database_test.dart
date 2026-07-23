import 'package:easy_memory/data/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('database initializes with all tables', () async {
    final db = await DatabaseHelper.instance.database;
    // Query sqlite_master to verify tables exist
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    final tableNames = tables.map((t) => t['name'] as String).toSet();

    expect(tableNames, containsAll(['rules', 'match_items', 'file_records']));
  });

  test('database has correct indexes', () async {
    final db = await DatabaseHelper.instance.database;
    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
    );
    final indexNames = indexes.map((i) => i['name'] as String).toSet();

    expect(indexNames, containsAll([
      'idx_match_items_rule_id',
      'idx_file_records_match_item_id',
    ]));
  });
}
