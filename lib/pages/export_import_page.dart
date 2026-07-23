import 'package:flutter/material.dart';

import 'package:easy_memory/services/export_import_service.dart';

class ExportImportPage extends StatefulWidget {
  const ExportImportPage({super.key});

  @override
  State<ExportImportPage> createState() => _ExportImportPageState();
}

class _ExportImportPageState extends State<ExportImportPage> {
  final ExportImportService _service = ExportImportService();
  bool _exporting = false;
  bool _importing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据导入/导出'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.backup, size: 64, color: Color(0xFF2563EB)),
              const SizedBox(height: 16),
              Text(
                '数据备份与恢复',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '导出数据将使用 SM4 加密保存为 .emdb 文件\n导入时不会覆盖已有数据',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: 220,
                child: FilledButton.icon(
                  onPressed: _exporting ? null : _onExport,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.file_upload_outlined),
                  label: Text(_exporting ? '导出中...' : '导出数据'),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 220,
                child: OutlinedButton.icon(
                  onPressed: _importing ? null : _onImport,
                  icon: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.file_download_outlined),
                  label: Text(_importing ? '导入中...' : '导入数据'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onExport() async {
    final password = await _showPasswordDialog(context, isExport: true);
    if (password == null) return;

    setState(() => _exporting = true);
    try {
      final path = await _service.exportData(password);
      if (!mounted) return;
      _showSnackBar('导出成功: $path', isError: false);
    } on ExportCancelledException {
      // user cancelled, no feedback needed
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('导出失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _onImport() async {
    final password = await _showPasswordDialog(context, isExport: false);
    if (password == null) return;

    setState(() => _importing = true);
    try {
      final summary = await _service.importData(password);
      if (!mounted) return;
      _showSnackBar(summary, isError: false);
    } on ExportCancelledException {
      // user cancelled, no feedback needed
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('导入失败: $e', isError: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<String?> _showPasswordDialog(BuildContext context,
      {required bool isExport}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isExport ? '导出数据' : '导入数据'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(isExport
                ? '请输入加密密码，用于保护导出的数据文件'
                : '请输入文件的加密密码'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final pwd = controller.text.trim();
              if (pwd.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入密码')),
                );
                return;
              }
              Navigator.pop(ctx, pwd);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: isError ? 4 : 3),
      ),
    );
  }
}