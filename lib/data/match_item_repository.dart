import '../models/match_item.dart';
import 'database.dart';

class MatchItemRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insert(MatchItem item) async {
    final db = await _dbHelper.database;
    return await db.insert('match_items', item.toMap());
  }

  Future<List<MatchItem>> getByRuleId(int ruleId) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'match_items',
      where: 'rule_id = ?',
      whereArgs: [ruleId],
      orderBy: 'created_at DESC',
    );
    return maps.map((m) => MatchItem.fromMap(m)).toList();
  }

  Future<MatchItem?> getById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('match_items', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return MatchItem.fromMap(maps.first);
  }

  Future<List<MatchItem>> searchByValue(String value) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'match_items',
      where: 'match_value LIKE ?',
      whereArgs: ['%$value%'],
    );
    return maps.map((m) => MatchItem.fromMap(m)).toList();
  }

  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    return await db.delete('match_items', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteByRuleId(int ruleId) async {
    final db = await _dbHelper.database;
    await db.delete('match_items', where: 'rule_id = ?', whereArgs: [ruleId]);
  }
}
