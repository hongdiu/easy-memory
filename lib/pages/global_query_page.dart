import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/models/remote_endpoint.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/services/remote_delete_service.dart';
import 'package:easy_memory/services/local_delete_service.dart';
import 'package:easy_memory/services/data_change_notifier.dart';
import 'package:easy_memory/pages/file_record_detail_page.dart';

class GlobalQueryPage extends StatefulWidget {
  const GlobalQueryPage({super.key});

  @override
  State<GlobalQueryPage> createState() => _GlobalQueryPageState();
}

class _GlobalQueryPageState extends State<GlobalQueryPage> {
  final TextEditingController _searchController = TextEditingController();
  final MatchItemRepository _matchRepo = MatchItemRepository();
  final FileRecordRepository _fileRepo = FileRecordRepository();
  final RuleRepository _ruleRepo = RuleRepository();

  Timer? _debounce;

  List<_SearchResult> _results = [];
  bool _loading = false;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // 同步/导入等写库操作后，若有查询词则自动重查，保证结果最新。
    DataChangeNotifier.instance.addListener(_onDataChanged);
  }

  @override
  void dispose() {
    DataChangeNotifier.instance.removeListener(_onDataChanged);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// 数据变更后重查当前关键词（无词则忽略，避免无谓请求）。
  void _onDataChanged() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty && mounted) {
      _performSearch(query);
    }
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(_searchController.text.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final items = await _matchRepo.searchByValue(query);

      // Cache rule names to avoid N+1 per item
      final ruleIds = items.map((i) => i.ruleId).toSet();
      final Map<int, String> ruleNames = {};
      for (final id in ruleIds) {
        final rule = await _ruleRepo.getById(id);
        ruleNames[id] = rule?.name ?? '(已删除规则)';
      }

      // ponytail: batch file counts per match item
      final List<_SearchResult> results = [];
      for (final item in items) {
        final files = await _fileRepo.getByMatchItemId(item.id!);
        results.add(_SearchResult(
          matchItem: item,
          ruleName: ruleNames[item.ruleId] ?? '(已删除规则)',
          files: files,
        ));
      }

      if (!mounted) return;
      setState(() {
        _results = results;
        _hasSearched = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _hasSearched = true;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('搜索出错: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全局查询'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '输入匹配项搜索',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _results = [];
                      _hasSearched = false;
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_hasSearched) {
      return _buildInitialState();
    }

    if (_results.isEmpty) {
      return _buildEmptyState();
    }

    return _buildResultsList();
  }

  Widget _buildInitialState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            '输入匹配项值开始搜索',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '支持模糊搜索，输入部分值即可匹配',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 80, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            '未找到匹配项',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            '尝试使用不同的关键词搜索',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        return _SearchResultCard(
          result: _results[index],
          onFileDeleted: (deletedFile) async {
            // Remove the local DB record so it doesn't reappear on next search
            if (deletedFile.id != null) {
              await _fileRepo.delete(deletedFile.id!);
            }
            _results[index].files.remove(deletedFile);
            setState(() {});
          },
        );
      },
    );
  }
}

class _SearchResult {
  final MatchItem matchItem;
  final String ruleName;
  final List<FileRecord> files;

  const _SearchResult({
    required this.matchItem,
    required this.ruleName,
    required this.files,
  });
}

class _SearchResultCard extends StatefulWidget {
  final _SearchResult result;
  final void Function(FileRecord deletedFile) onFileDeleted;

  const _SearchResultCard({
    required this.result,
    required this.onFileDeleted,
  });

  @override
  State<_SearchResultCard> createState() => _SearchResultCardState();
}

class _SearchResultCardState extends State<_SearchResultCard> {
  final RemoteDeleteService _remoteDeleteService = RemoteDeleteService();
  final LocalDeleteService _localDeleteService = LocalDeleteService();
  bool _expanded = false;

  /// Whether [path] belongs to the current device (local) vs. a remote device.
  static bool _isLocalPath(String path) {
    if (kIsWeb) return false;
    if (Platform.isWindows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
    }
    if (Platform.isAndroid) {
      return path.startsWith('content://') || path.startsWith('/storage/');
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return path.startsWith('/');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.matchItem.matchValue,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.rule, size: 14, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              r.ruleName,
                              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${r.files.length} 文件',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && r.files.isNotEmpty) _buildFileList(r.files),
        ],
      ),
    );
  }

  Widget _buildFileList(List<FileRecord> files) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: files.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final file = files[index];
          return InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FileRecordDetailPage(
                    record: file,
                    matchValue: widget.result.matchItem.matchValue,
                    ruleName: widget.result.ruleName,
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, size: 18, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.fileName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${file.formattedSize}  ·  ${file.fullPath}',
                          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, size: 16, color: Colors.grey[400]),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: '复制路径',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: file.fullPath));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('路径已复制到剪贴板'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  if (_isLocalPath(file.fullPath))
                    _LocalDeleteButton(
                      file: file,
                      service: _localDeleteService,
                      onDeleted: (deleted) => widget.onFileDeleted(deleted),
                    )
                  else
                    _RemoteDeleteButton(
                      file: file,
                      service: _remoteDeleteService,
                      onDeleted: (deleted) => widget.onFileDeleted(deleted),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A small icon button that triggers the **local** delete flow.
/// Deletes the physical file on this device + its DB record, no remote
/// endpoint configuration needed.
class _LocalDeleteButton extends StatelessWidget {
  final FileRecord file;
  final LocalDeleteService service;
  final void Function(FileRecord deletedFile) onDeleted;

  const _LocalDeleteButton({
    required this.file,
    required this.service,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '删除文件',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTap(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.delete_outline, size: 16, color: Colors.red[300]),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定删除此文件？\n\n${file.fullPath}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await service.delete(file);
    if (!context.mounted) return;

    if (result.success) {
      onDeleted(file);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('删除成功'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
}

/// A small icon button that triggers the remote delete flow.
class _RemoteDeleteButton extends StatelessWidget {
  final FileRecord file;
  final RemoteDeleteService service;
  final void Function(FileRecord deletedFile) onDeleted;

  const _RemoteDeleteButton({
    required this.file,
    required this.service,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '远程删除',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _onTap(context),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.cloud_off_outlined, size: 16, color: Colors.red[300]),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    final endpoints = await service.loadEndpoints();
    if (!context.mounted) return;

    if (endpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在 Web 服务页面配置远程地址'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    if (endpoints.length == 1) {
      // Single endpoint — delete directly
      await _confirmAndDelete(context, endpoints.first);
      return;
    }

    // Multiple endpoints — let user choose
    if (!context.mounted) return;
    final selected = await showModalBottomSheet<RemoteEndpoint>(
      context: context,
      builder: (ctx) => _EndpointPickerSheet(endpoints: endpoints),
    );
    if (selected != null && context.mounted) {
      await _confirmAndDelete(context, selected);
    }
  }

  Future<void> _confirmAndDelete(BuildContext context, RemoteEndpoint endpoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('远程删除'),
        content: Text('确定在「${endpoint.label}」(${endpoint.host}) 上删除此文件？\n\n${file.fullPath}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('正在删除...'), duration: Duration(seconds: 1)),
    );

    final result = await service.deleteFile(endpoint: endpoint, filePath: file.fullPath);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? '删除成功${result.warning != null ? '（${result.warning}）' : ''}'
            : '删除失败: ${result.message}'),
        backgroundColor: result.success
            ? (result.warning != null ? Colors.orange : Colors.green)
            : Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );

    if (result.success) {
      // Delete local DB record so the list entry disappears
      onDeleted(file);
    }
  }
}

/// Bottom sheet to pick a remote endpoint from a list.
class _EndpointPickerSheet extends StatelessWidget {
  final List<RemoteEndpoint> endpoints;

  const _EndpointPickerSheet({required this.endpoints});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('选择远程设备', style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          ...endpoints.map((e) => ListTile(
                leading: const Icon(Icons.computer),
                title: Text(e.label),
                subtitle: Text(e.host),
                onTap: () => Navigator.of(context).pop(e),
              )),
        ],
      ),
    );
  }
}