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
}
