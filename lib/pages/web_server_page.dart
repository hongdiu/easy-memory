import 'dart:io';

import 'package:flutter/material.dart';
import '../services/web_server_service.dart';

class WebServerPage extends StatefulWidget {
  const WebServerPage({super.key});

  @override
  State<WebServerPage> createState() => _WebServerPageState();
}

class _WebServerPageState extends State<WebServerPage> {
  final WebServerService _service = WebServerService();
  final TextEditingController _portCtrl = TextEditingController(text: '8080');
  bool _running = false;
  String _statusMsg = '';
  String _localIp = '';

  @override
  void initState() {
    super.initState();
    _findLocalIp();
  }

  @override
  void dispose() {
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _findLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
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
        _statusMsg = '端口号须为 1024-65535';
        setState(() {});
        return;
      }
      try {
        await _service.start(port: port);
        setState(() {
          _running = true;
          _statusMsg = '服务已启动';
        });
      } catch (e) {
        setState(() {
          _statusMsg = '启动失败: $e';
        });
      }
    }
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

          // Port config
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
                          onPressed: () {
                            // Copy to clipboard via Flutter's clipboard
                          },
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
        ],
      ),
    );
  }
}