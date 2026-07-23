import 'package:flutter/material.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'rule_edit_page.dart';
import 'export_import_page.dart';
import 'rule_detail_page.dart';

class RulesListPage extends StatefulWidget {
  const RulesListPage({super.key});

  @override
  State<RulesListPage> createState() => _RulesListPageState();
}

class _RulesListPageState extends State<RulesListPage> {
  final RuleRepository _repository = RuleRepository();
  List<Rule> _rules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _loading = true);
    try {
      final rules = await _repository.getAll();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rules = [];
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('加载失败: $e')),
      );
    }
  }

  Future<void> _deleteRule(Rule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('确定删除规则「${rule.name}」吗？\n关联的匹配项和文件记录也将被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && rule.id != null) {
      // ponytail: deleteWithCascade handles match_items + file_records
      await _repository.deleteWithCascade(rule.id!);
      await _loadRules();
    }
  }

  String _regexSummary(String pattern) {
    if (pattern.length <= 30) return pattern;
    return '${pattern.substring(0, 27)}...';
  }

  String _dirSummary(String? dir) {
    if (dir == null || dir.isEmpty) return '未设置';
    if (dir.length <= 40) return dir;
    return '...${dir.substring(dir.length - 37)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则管理'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.backup_outlined),
            tooltip: '导入/导出数据',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExportImportPage()),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rules.isEmpty
              ? _buildEmptyState()
              : _buildRuleList(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEdit(),
        tooltip: '新建规则',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.rule_folder_outlined, size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('暂无规则', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text('点击右下角 + 按钮创建第一条规则', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
        ],
      ),
    );
  }

  Widget _buildRuleList() {
    // ponytail: simple ListView, no pull-to-refresh, reload on return
    return RefreshIndicator(
      onRefresh: _loadRules,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _rules.length,
        itemBuilder: (context, index) {
          final rule = _rules[index];
          return _buildRuleCard(rule);
        },
      ),
    );
  }

  Widget _buildRuleCard(Rule rule) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RuleDetailPage(rule: rule)),
            );
          },
        onLongPress: () => _deleteRule(rule),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(rule.name, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _navigateToEdit(rule: rule),
                    tooltip: '编辑',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _infoRow(Icons.code, '正则', _regexSummary(rule.regexPattern)),
              const SizedBox(height: 4),
              _infoRow(Icons.folder_outlined, '目录', _dirSummary(rule.scanDirectory)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Future<void> _navigateToEdit({Rule? rule}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RuleEditPage(rule: rule)),
    );
    if (result == true) await _loadRules();
  }
}