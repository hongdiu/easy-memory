import '../models/file_record.dart';
import 'database.dart';

class FileRecordRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insert(FileRecord record) async {
    final db = await _dbHelper.database;
    return await db.insert('file_records', record.toMap());
  }

  Future<List<FileRecord>> getByMatchItemId(int matchItemId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'file_records',
      where: 'match_item_id = ?',
      whereArgs: [matchItemId],
      orderBy: 'scanned_at DESC',
    );
    return maps.map((m) => FileRecord.fromMap(m)).toList();
  }

  /// Find a file record by its natural key (match_item_id + full_path).
  /// Used for cross-device import merge to avoid ID collisions.
  Future<FileRecord?> findByMatchItemIdAndPath(
      int matchItemId, String fullPath) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'file_records',
      where: 'match_item_id = ? AND full_path = ?',
      whereArgs: [matchItemId, fullPath],
    );
    if (maps.isEmpty) return null;
    return FileRecord.fromMap(maps.first);
  }

  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    return await db.delete('file_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByMatchItemId(int matchItemId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'file_records',
      where: 'match_item_id = ?',
      whereArgs: [matchItemId],
    );
  }

  /// Delete all file records with [fullPath]. Returns the number deleted.
  /// Used by the local/remote delete flow to keep the DB in sync.
  Future<int> deleteByFullPath(String fullPath) async {
    final db = await _dbHelper.database;
    return await db.delete(
      'file_records',
      where: 'full_path = ?',
      whereArgs: [fullPath],
    );
  }

  /// Total number of file records. Used by sync progress calculation.
  Future<int> count() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM file_records');
    return (result.first['c'] as int?) ?? 0;
  }

  /// Fetch a page of file records for batch sync.
  Future<List<FileRecord>> getPage(int offset, int limit) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'file_records',
      orderBy: 'id ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => FileRecord.fromMap(m)).toList();
  }

  /// Fetch all file records (used by cleanup).
  Future<List<FileRecord>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('file_records', orderBy: 'id ASC');
    return maps.map((m) => FileRecord.fromMap(m)).toList();
  }
}
