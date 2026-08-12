import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/remote_endpoint.dart';
import '../services/web_server_service.dart';
import '../services/sync_service.dart';
import '../services/cleanup_service.dart';

class WebServerPage extends StatefulWidget {
  const WebServerPage({super.key});

  @override
  State<WebServerPage> createState() => _WebServerPageState();
}

class _WebServerPageState extends State<WebServerPage> {
  final WebServerService _service = WebServerService();
  final TextEditingController _portCtrl = TextEditingController(text: '8080');
  final TextEditingController _apiKeyCtrl = TextEditingController();
  bool _running = false;
  String _statusMsg = '';
  String _localIp = '';

  final List<RemoteEndpoint> _remoteEndpoints = [];
  bool _endpointsExpanded = false;
  bool _loadingEndpoints = true;

  @override
  void initState() {
    super.initState();
    _findLocalIp();
    _loadEndpoints();
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _findLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 5));
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            _localIp = addr.address;
            return;
          }
        }
      }
    } catch (_) {
      // non-fatal, just don't show IP
    }
  }

  Future<void> _loadEndpoints() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/remote_endpoints.json');
      if (await file.exists()) {
        final json = await file.readAsString();
        final loaded = remoteEndpointsFromJson(json);
        setState(() {
          _remoteEndpoints
            ..clear()
            ..addAll(loaded);
        });
      }
    } catch (_) {
      // non-fatal
    } finally {
      setState(() => _loadingEndpoints = false);
    }
  }

  Future<void> _saveEndpoints() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/remote_endpoints.json');
      await file.writeAsString(remoteEndpointsToJson(_remoteEndpoints));
    } catch (_) {
      // non-fatal
    }
  }

  Future<void> _toggleServer() async {
    if (_running) {
      await _service.stop();
      setState(() {
        _running = false;
        _statusMsg = '服务已停止';
      });
    } else {
      final port = int.tryParse(_portCtrl.text);
      if (port == null || port < 1024 || port > 65535) {
        setState(() => _statusMsg = '端口号须为 1024-65535');
        return;
      }
      try {
        await _service.start(port: port, apiKey: _apiKeyCtrl.text.trim());
        setState(() {
          _running = true;
          _statusMsg = '服务已启动';
        });
      } catch (e) {
        setState(() => _statusMsg = '启动失败: $e');
      }
    }
  }

  void _addEndpoint() {
    final controller = _EndpointFormController();
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _EndpointDialog(controller: controller),
    ).then((_) {
      if (controller.saved && mounted) {
        final endpoint = controller.toEndpoint();
        setState(() => _remoteEndpoints.add(endpoint));
        _saveEndpoints();
      }
    });
  }

  void _editEndpoint(RemoteEndpoint endpoint) {
    final controller = _EndpointFormController.fromEndpoint(endpoint);
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => _EndpointDialog(controller: controller),
    ).then((_) {
      if (controller.saved && mounted) {
        final updated = controller.toEndpoint();
        setState(() {
          final index = _remoteEndpoints.indexWhere((e) => e.id == updated.id);
          if (index != -1) _remoteEndpoints[index] = updated;
        });
        _saveEndpoints();
      }
    });
  }

  void _removeEndpoint(RemoteEndpoint endpoint) {
    setState(() => _remoteEndpoints.removeWhere((e) => e.id == endpoint.id));
    _saveEndpoints();
  }

  /// Start a sync from [endpoint] and show the progress dialog.
  Future<void> _startSync(RemoteEndpoint endpoint) async {
    final service = SyncService();
    final progress = ValueNotifier<SyncProgress>(
      const SyncProgress(percent: 0, message: '准备同步...'),
    );

    // Show the progress dialog (non-blocking, updates via ValueNotifier)
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _SyncProgressDialog(
        endpoint: endpoint,
        progress: progress,
      ),
    );

    // Run sync in the background
    final result = await service.sync(
      endpoint,
      onProgress: (p) => progress.value = p,
    );

    // Close the dialog and report the result
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(result.success ? '同步完成' : '同步失败'),
        content: Text(result.message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// Start a cleanup of ghost DB records and show the progress dialog.
  Future<void> _startCleanup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('数据清理'),
        content: const Text(
          '将检查本机路径对应的文件是否存在，删除文件已不存在的幽灵记录。\n\n'
          '仅处理本机平台的路径（远程同步来的记录会跳过）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('开始清理'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final service = CleanupService();
    final progress = ValueNotifier<CleanupProgress>(
      const CleanupProgress(percent: 0, message: '准备清理...'),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _CleanupProgressDialog(progress: progress),
    );

    final result = await service.cleanup(
      onProgress: (p) => progress.value = p,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('清理完成'),
        content: Text(
          '共 ${result.totalRecords} 条记录\n'
          '本地路径 ${result.localRecords} 条\n'
          '清理幽灵记录 ${result.cleanedRecords} 条',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = _running ? 'http://$_localIp:${_service.port}' : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Web 服务')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    _running ? Icons.check_circle : Icons.cancel,
                    size: 56,
                    color: _running ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _running ? '运行中' : '已停止',
                    style: theme.textTheme.titleLarge,
                  ),
                  if (_statusMsg.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_statusMsg,
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Port + API key config
          if (!_running) ...[
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: '端口号',
                hintText: '8080',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyCtrl,
              decoration: const InputDecoration(
                labelText: '访问密钥 (可选)',
                hintText: '留空则不要求密钥',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Start/Stop button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _toggleServer,
              icon: Icon(_running ? Icons.stop : Icons.play_arrow),
              label: Text(_running ? '停止服务' : '启动服务'),
            ),
          ),

          // Access URL
          if (url != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('访问地址', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            url,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
                          tooltip: '复制地址',
                          onPressed: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在同一局域网的电脑浏览器中打开此地址即可查询',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Remote endpoints panel
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('远程地址配置'),
                  subtitle: const Text('记录各端 (Android/电脑) 的地址与密钥'),
                  trailing: IconButton(
                    icon: Icon(_endpointsExpanded ? Icons.expand_less : Icons.expand_more),
                    onPressed: () => setState(() => _endpointsExpanded = !_endpointsExpanded),
                  ),
                ),
                if (_endpointsExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_loadingEndpoints)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_remoteEndpoints.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              '尚未配置远程地址',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          )
                        else
                          ..._remoteEndpoints.map((e) => _EndpointTile(
                                endpoint: e,
                                onSync: () => _startSync(e),
                                onEdit: () => _editEndpoint(e),
                                onDelete: () => _removeEndpoint(e),
                              )),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _addEndpoint,
                          icon: const Icon(Icons.add),
                          label: const Text('添加远程地址'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Data cleanup panel
          Card(
            child: ListTile(
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('数据清理'),
              subtitle: const Text('删除文件已不存在的幽灵记录 (仅限本机路径)'),
              trailing: OutlinedButton.icon(
                onPressed: _startCleanup,
                icon: const Icon(Icons.cleaning_services, size: 18),
                label: const Text('清理'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EndpointTile extends StatelessWidget {
  final RemoteEndpoint endpoint;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSync;

  const _EndpointTile({
    required this.endpoint,
    required this.onEdit,
    required this.onDelete,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.computer),
        title: Text(endpoint.label),
        subtitle: Text(
          '${endpoint.host}:${endpoint.port}'
          '${endpoint.apiKey.isEmpty ? '' : '  ·  密' }',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.sync, size: 20),
              color: Colors.blue,
              tooltip: '同步数据',
              onPressed: onSync,
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Form controller for the Add/Edit endpoint dialog.
class _EndpointFormController {
  final _labelCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '8080');
  final _apiKeyCtrl = TextEditingController();
  final String _id;
  bool saved = false;

  _EndpointFormController({String? id}) : _id = id ?? DateTime.now().millisecondsSinceEpoch.toString();

  factory _EndpointFormController.fromEndpoint(RemoteEndpoint e) {
    final c = _EndpointFormController(id: e.id)
      .._labelCtrl.text = e.label
      .._hostCtrl.text = e.host
      .._portCtrl.text = e.port.toString()
      .._apiKeyCtrl.text = e.apiKey;
    return c;
  }

  RemoteEndpoint toEndpoint() {
    return RemoteEndpoint(
      id: _id,
      label: _labelCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 8080,
      apiKey: _apiKeyCtrl.text.trim(),
    );
  }

  void dispose() {
    _labelCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _apiKeyCtrl.dispose();
  }
}

class _EndpointDialog extends StatefulWidget {
  final _EndpointFormController controller;

  const _EndpointDialog({required this.controller});

  @override
  State<_EndpointDialog> createState() => _EndpointDialogState();
}

class _EndpointDialogState extends State<_EndpointDialog> {
  late final _EndpointFormController c = widget.controller;

  @override
  void dispose() {
    if (!c.saved) c.dispose();
    super.dispose();
  }

  void _save() {
    if (c._labelCtrl.text.trim().isEmpty || c._hostCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称和地址不能为空')),
      );
      return;
    }
    c.saved = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('远程地址'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c._labelCtrl,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '如：客厅电脑 / 安卓机',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c._hostCtrl,
              decoration: const InputDecoration(
                labelText: 'IP / 主机名',
                hintText: '如：192.168.1.100',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c._portCtrl,
              decoration: const InputDecoration(
                labelText: '端口',
                hintText: '8080',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c._apiKeyCtrl,
              decoration: const InputDecoration(
                labelText: '访问密钥 (可选)',
                hintText: '与对方服务启动时设置的密钥一致',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            c.dispose();
            Navigator.of(context).pop();
          },
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}

/// Sync progress dialog shown during data synchronization.
class _SyncProgressDialog extends StatelessWidget {
  final RemoteEndpoint endpoint;
  final ValueNotifier<SyncProgress> progress;

  const _SyncProgressDialog({
    required this.endpoint,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('同步数据 — ${endpoint.label}'),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<SyncProgress>(
          valueListenable: progress,
          builder: (context, p, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: p.percent / 100.0),
                const SizedBox(height: 16),
                Text(
                  '${p.percent}%',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  p.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Cleanup progress dialog shown during data cleanup.
class _CleanupProgressDialog extends StatelessWidget {
  final ValueNotifier<CleanupProgress> progress;

  const _CleanupProgressDialog({required this.progress});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('数据清理'),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<CleanupProgress>(
          valueListenable: progress,
          builder: (context, p, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: p.percent / 100.0),
                const SizedBox(height: 16),
                Text(
                  '${p.percent}%',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  p.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}