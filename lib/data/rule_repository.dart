import '../models/rule.dart';
import 'database.dart';

class RuleRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> insert(Rule rule) async {
    final db = await _dbHelper.database;
    return await db.insert('rules', rule.toMap());
  }

  Future<Rule?> getById(int id) async {
    final db = await _dbHelper.database;
    final maps = await db.query('rules', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Rule.fromMap(maps.first);
  }

  Future<List<Rule>> getAll() async {
    final db = await _dbHelper.database;
    final maps = await db.query('rules', orderBy: 'created_at DESC');
    return maps.map((m) => Rule.fromMap(m)).toList();
  }

  Future<int> update(Rule rule) async {
    final db = await _dbHelper.database;
    return await db.update(
      'rules',
      rule.toMap(),
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _dbHelper.database;
    return await db.delete('rules', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteWithCascade(int id) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      // Delete file_records for all match_items of this rule
      await txn.rawDelete('''
        DELETE FROM file_records WHERE match_item_id IN (
          SELECT id FROM match_items WHERE rule_id = ?
        )
      ''', [id]);
      // Delete match_items for this rule
      await txn.delete('match_items', where: 'rule_id = ?', whereArgs: [id]);
      // Delete rule
      await txn.delete('rules', where: 'id = ?', whereArgs: [id]);
    });
  }
}
