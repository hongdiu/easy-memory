import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/services/scan_result_handler.dart';
import 'package:easy_memory/services/permission_service.dart';

class RuleDetailPage extends StatefulWidget {
  final Rule rule;

  const RuleDetailPage({super.key, required this.rule});

  @override
  State<RuleDetailPage> createState() => _RuleDetailPageState();
}

class _RuleDetailPageState extends State<RuleDetailPage> {
  final MatchItemRepository _matchItemRepo = MatchItemRepository();
  final FileRecordRepository _fileRecordRepo = FileRecordRepository();
  final ScanResultHandler _scanHandler = ScanResultHandler();

  List<MatchItem> _matchItems = [];
  Map<int, List<FileRecord>> _fileRecords = {};
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final items = await _matchItemRepo.getByRuleId(widget.rule.id!);
    // ponytail: sort alphabetically for consistent display
    items.sort((a, b) => a.matchValue.compareTo(b.matchValue));

    final records = <int, List<FileRecord>>{};
    for (final item in items) {
      records[item.id!] = await _fileRecordRepo.getByMatchItemId(item.id!);
    }

    if (mounted) {
      setState(() {
        _matchItems = items;
        _fileRecords = records;
        _loading = false;
      });
    }
  }

  Future<void> _rescan() async {
    if (widget.rule.scanDirectory == null || widget.rule.scanDirectory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置扫描目录')),
      );
      return;
    }

    // 扫描前请求存储权限
    final granted = await PermissionService.requestStorage();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要存储权限才能扫描文件，请在系统设置中授权')),
        );
      }
      return;
    }

    setState(() => _scanning = true);
    try {
      await _scanHandler.processScanResult(
        widget.rule.id!,
        widget.rule.scanDirectory!,
        widget.rule.regexPattern,
        widget.rule.formatString,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('扫描完成'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _changeDirectory() async {
    // 选择目录前请求存储权限
    final granted = await PermissionService.requestStorage();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('需要存储权限才能扫描文件，请在系统设置中授权')),
        );
      }
      return;
    }

    final path = await FilePicker.getDirectoryPath();
    if (path == null || !mounted) return;

    setState(() => _scanning = true);
    try {
      await _scanHandler.processScanResult(
        widget.rule.id!,
        path,
        widget.rule.regexPattern,
        widget.rule.formatString,
      );
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('扫描完成'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('扫描失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule.name),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildRuleInfoCard(),
                _buildActionButtons(),
                const Divider(height: 1),
                Expanded(child: _buildMatchList()),
              ],
            ),
    );
  }

  Widget _buildRuleInfoCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(Icons.code, '正则', widget.rule.regexPattern),
            const SizedBox(height: 6),
            _infoRow(Icons.folder_outlined, '目录', widget.rule.scanDirectory ?? '未设置'),
            const SizedBox(height: 6),
            _infoRow(Icons.layers, '匹配项', '${_matchItems.length} 个'),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _scanning ? null : _rescan,
              icon: _scanning
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: Text(_scanning ? '扫描中...' : '重新扫描'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _scanning ? null : _changeDirectory,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text('更换目录'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchList() {
    if (_matchItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('暂无匹配项', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
            const SizedBox(height: 4),
            Text('点击「重新扫描」开始匹配', style: TextStyle(color: Colors.grey[500], fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _matchItems.length,
      itemBuilder: (context, index) {
        final item = _matchItems[index];
        final records = _fileRecords[item.id] ?? [];
        return _buildMatchTile(item, records);
      },
    );
  }

  Widget _buildMatchTile(MatchItem item, List<FileRecord> records) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.matchValue,
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w500),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${records.length} 文件',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        children: records.map((record) {
          return ListTile(
            dense: true,
            title: Text(record.fileName, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              record.fullPath,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: '复制路径',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: record.fullPath));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('路径已复制'), duration: Duration(seconds: 1)),
                );
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}