import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/models/match_item.dart';
import 'package:easy_memory/models/file_record.dart';
import 'package:easy_memory/data/match_item_repository.dart';
import 'package:easy_memory/data/file_record_repository.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/services/file_scanner.dart';
import 'package:easy_memory/services/saf_file_scanner.dart';
import 'package:easy_memory/services/scan_result_handler.dart';
import 'package:easy_memory/services/permission_service.dart';
import 'package:easy_memory/services/local_delete_service.dart';
import 'package:easy_memory/services/remote_delete_service.dart';
import 'package:easy_memory/models/remote_endpoint.dart';
import 'package:easy_memory/pages/file_record_detail_page.dart';
import 'package:easy_memory/pages/video_player_page.dart';

class RuleDetailPage extends StatefulWidget {
  final Rule rule;

  const RuleDetailPage({super.key, required this.rule});

  @override
  State<RuleDetailPage> createState() => _RuleDetailPageState();
}

class _RuleDetailPageState extends State<RuleDetailPage> {
  final MatchItemRepository _matchItemRepo = MatchItemRepository();
  final FileRecordRepository _fileRecordRepo = FileRecordRepository();
  final RuleRepository _ruleRepo = RuleRepository();
  late final FileScanner _scanner;
  late final ScanResultHandler _scanHandler;

  /// 当前规则的可变副本：更换目录后（写回 DB）同步更新它，
  /// 页面显示的目录立即反映最新值（_rule 是 immutable 的）。
  late Rule _rule;

  List<MatchItem> _matchItems = [];
  Map<int, List<FileRecord>> _fileRecords = {};
  bool _loading = true;
  bool _scanning = false;

  final LocalDeleteService _localDeleteService = LocalDeleteService();
  final RemoteDeleteService _remoteDeleteService = RemoteDeleteService();

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
  void initState() {
    super.initState();
    _rule = widget.rule;
    _scanner = createFileScanner();
    _scanHandler = ScanResultHandler(scanner: _scanner);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final items = await _matchItemRepo.getByRuleId(_rule.id!);
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _matchItems = [];
          _fileRecords = {};
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载数据失败: $e')),
        );
      }
    }
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<void> _rescan() async {
    if (_rule.scanDirectory == null || _rule.scanDirectory!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先设置扫描目录')),
      );
      return;
    }

    // Android 使用 SAF，无需 MANAGE_EXTERNAL_STORAGE 权限
    if (!_isAndroid) {
      final granted = await PermissionService.requestStorage();
      if (!granted) {
        if (mounted) {
          final goSettings = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('需要存储权限'),
              content: const Text(
                '扫描文件需要「所有文件访问权限」。\n\n'
                '请点击「去授权」，在设置中打开「允许访问所有文件」开关。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('去授权'),
                ),
              ],
            ),
          );
          if (goSettings == true && mounted) {
            await PermissionService.openSettingsAndCheck();
          }
        }
        return;
      }
    }

    setState(() => _scanning = true);
    try {
      await _scanHandler.processScanResult(
        _rule.id!,
        _rule.scanDirectory!,
        _rule.regexPattern,
        _rule.formatString,
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
    final bool isAndroid = _isAndroid;

    // Android: 使用 SAF 选择器（无需权限）
    // 桌面: 使用 FilePicker，先请求权限
    String? directory;
    if (isAndroid) {
      final safScanner = _scanner as SafFileScanner;
      directory = await safScanner.pickDirectory();
    } else {
      final granted = await PermissionService.requestStorage();
      if (!granted) {
        if (mounted) {
          final goSettings = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('需要存储权限'),
              content: const Text(
                '更换目录并扫描文件需要「所有文件访问权限」。\n\n'
                '请点击「去授权」，在设置中打开「允许访问所有文件」开关。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('去授权'),
                ),
              ],
            ),
          );
          if (goSettings == true && mounted) {
            await PermissionService.openSettingsAndCheck();
          }
        }
        return;
      }
      directory = await FilePicker.getDirectoryPath();
    }

    if (directory == null || !mounted) return;

    // 更新当前规则的扫描目录（写回 DB + 同步页面显示）。
    // 放在扫描之前，无论扫描成败目录都已更新，符合用户意图。
    final updatedRule = _rule.copyWith(
      scanDirectory: directory,
      updatedAt: DateTime.now().toIso8601String(),
    );
    try {
      await _ruleRepo.update(updatedRule);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新规则目录失败: $e')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _rule = updatedRule;
      _scanning = true;
    });

    try {
      await _scanHandler.processScanResult(
        _rule.id!,
        directory,
        _rule.regexPattern,
        _rule.formatString,
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

  /// 文件项点击：视频 → 播放；否则 → 详情页。
  Future<void> _onFileTap(BuildContext context, FileRecord record, MatchItem item) async {
    final handled = await launchVideoPlayer(
      context,
      record,
      isLocalPath: _isLocalPath,
    );
    if (handled) return;
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FileRecordDetailPage(
          record: record,
          matchValue: item.matchValue,
          ruleName: _rule.name,
        ),
      ),
    );
  }

  Future<void> _confirmLocalDelete(BuildContext context, FileRecord record) async {
    final confirmed = await showDialog<bool>(
        title: const Text('删除文件'),
        content: Text('确定删除此文件？\n\n${record.fullPath}'),
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

    final result = await _localDeleteService.delete(record);
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
    if (result.success) {
      await _loadData();
    }
  }

  /// Remote delete succeeded — clean up the local DB record and refresh.
  Future<void> _onRemoteDeleted(FileRecord record) async {
    if (record.id != null) {
      await _fileRecordRepo.delete(record.id!);
    }
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_rule.name),
        backgroundColor: Theme.of(context).colorScheme.primary,
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
            _infoRow(Icons.code, '正则', _rule.regexPattern),
            const SizedBox(height: 6),
            _infoRow(Icons.folder_outlined, '目录', _rule.scanDirectory ?? '未设置'),
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
            leading: const Icon(Icons.insert_drive_file_outlined, size: 18),
            title: Text(record.fileName, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              '${record.formattedSize}  ·  ${record.fullPath}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _onFileTap(context, record, item),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isLocalPath(record.fullPath))
                  Tooltip(
                    message: '删除文件',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _confirmLocalDelete(context, record),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline, size: 16, color: Colors.red[300]),
                      ),
                    ),
                  )
                else
                  _RemoteDeleteButton(
                    file: record,
                    service: _remoteDeleteService,
                    onDeleted: (deleted) => _onRemoteDeleted(deleted),
                  ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: '复制路径',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: record.fullPath));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('路径已复制'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// A small icon button that triggers the remote delete flow (cross-device).
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
          content: Text('请先在高级页面配置远程地址'),
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