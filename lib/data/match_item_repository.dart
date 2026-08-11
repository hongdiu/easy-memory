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

  /// Find a match item by its natural key (rule_id + match_value).
  /// Used for cross-device import merge to avoid ID collisions.
  Future<MatchItem?> findByRuleIdAndValue(int ruleId, String matchValue) async {
    final db = await _dbHelper.database;
    final maps = await db.query(
      'match_items',
      where: 'rule_id = ? AND match_value = ?',
      whereArgs: [ruleId, matchValue],
    );
    if (maps.isEmpty) return null;
    return MatchItem.fromMap(maps.first);
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
