import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

DatabaseFactory get _databaseFactory {
  if (kIsWeb) return databaseFactory;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return databaseFactory;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      sqfliteFfiInit();
      return databaseFactoryFfi;
  }
}

class DatabaseHelper {
  // ponytail: singleton, one instance
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  /// Inject a database for testing purposes.
  static void setDatabaseForTesting(Database db) {
    _database = db;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('easy_memory.db');
    return _database!;
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$filePath';
    return await _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _onCreate,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
  }
}
