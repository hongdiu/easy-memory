import 'package:flutter/material.dart';
import 'package:easy_memory/models/file_record.dart';

class FileRecordDetailPage extends StatelessWidget {
  final FileRecord record;
  final String? matchValue;
  final String? ruleName;

  const FileRecordDetailPage({
    super.key,
    required this.record,
    this.matchValue,
    this.ruleName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件详情'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('文件信息', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 16),
                  _buildRow(theme, Icons.insert_drive_file, '文件名', record.fileName),
                  const Divider(height: 20),
                  _buildRow(theme, Icons.storage, '大小', record.formattedSize),
                  const Divider(height: 20),
                  _buildRow(theme, Icons.folder_outlined, '目录', record.directory),
                  const Divider(height: 20),
                  _buildRow(theme, Icons.link, '完整路径', record.fullPath),
                  const Divider(height: 20),
                  _buildRow(theme, Icons.access_time, '扫描时间', record.scannedAt),
                  if (matchValue != null) ...[
                    const Divider(height: 20),
                    _buildRow(theme, Icons.tag, '匹配值', matchValue!),
                  ],
                  if (ruleName != null) ...[
                    const Divider(height: 20),
                    _buildRow(theme, Icons.rule, '所属规则', ruleName!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ThemeData theme, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        ),
        Expanded(
          child: SelectableText(value, style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }
}