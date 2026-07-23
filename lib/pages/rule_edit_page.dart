import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/data/rule_repository.dart';

class RuleEditPage extends StatefulWidget {
  final Rule? rule;

  const RuleEditPage({super.key, this.rule});

  @override
  State<RuleEditPage> createState() => _RuleEditPageState();
}

class _RuleEditPageState extends State<RuleEditPage> {
  final _formKey = GlobalKey<FormState>();
  final RuleRepository _repository = RuleRepository();

  late final TextEditingController _nameController;
  late final TextEditingController _regexController;
  late final TextEditingController _formatController;
  late final TextEditingController _dirController;
  final TextEditingController _testFileNameController = TextEditingController();

  RegExp? _compiledRegex;
  bool _regexValid = true;
  String _regexError = '';
  String? _previewResult;
  List<String> _captureGroups = [];

  bool _isEditing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.rule != null;
    _nameController = TextEditingController(text: widget.rule?.name ?? '');
    _regexController = TextEditingController(text: widget.rule?.regexPattern ?? '');
    _formatController = TextEditingController(text: widget.rule?.formatString ?? '\$0');
    _dirController = TextEditingController(text: widget.rule?.scanDirectory ?? '');

    if (widget.rule?.regexPattern != null && widget.rule!.regexPattern.isNotEmpty) {
      _compileRegex(widget.rule!.regexPattern);
    }

    _regexController.addListener(_onRegexChanged);
    _testFileNameController.addListener(_updatePreview);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _regexController.dispose();
    _formatController.dispose();
    _dirController.dispose();
    _testFileNameController.dispose();
    super.dispose();
  }

  void _onRegexChanged() {
    _compileRegex(_regexController.text);
    _updatePreview();
  }

  void _compileRegex(String pattern) {
    if (pattern.isEmpty) {
      setState(() {
        _compiledRegex = null;
        _regexValid = true;
        _regexError = '';
      });
      return;
    }
    try {
      _compiledRegex = RegExp(pattern);
      setState(() {
        _regexValid = true;
        _regexError = '';
      });
    } on FormatException catch (e) {
      setState(() {
        _compiledRegex = null;
        _regexValid = false;
        _regexError = e.message;
      });
    }
  }

  void _updatePreview() {
    final testName = _testFileNameController.text;
    final regex = _compiledRegex;
    if (testName.isEmpty || regex == null || !_regexValid) {
      setState(() {
        _previewResult = null;
        _captureGroups = [];
      });
      return;
    }

    final match = regex.firstMatch(testName);
    if (match == null) {
      setState(() {
        _previewResult = null;
        _captureGroups = [];
      });
      return;
    }

    final groups = <String>[];
    for (int i = 0; i <= match.groupCount; i++) {
      groups.add(match.group(i) ?? '');
    }

    // Apply format string: replace $0, $1, $2, ... with capture groups
    String formatted = _formatController.text;
    formatted = formatted.replaceAllMapped(
      RegExp(r'\$(\d+)'),
      (m) {
        final idx = int.parse(m.group(1)!);
        return idx < groups.length ? groups[idx] : m.group(0)!;
      },
    );

    setState(() {
      _captureGroups = groups;
      _previewResult = formatted;
    });
  }

  Future<void> _pickDirectory() async {
    final path = await FilePicker.getDirectoryPath();
    if (path != null) {
      _dirController.text = path;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_regexValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正则表达式无效，请修正后再保存')),
      );
      return;
    }

    setState(() => _saving = true);

    final now = DateTime.now().toIso8601String();
    final rule = Rule(
      id: widget.rule?.id,
      name: _nameController.text.trim(),
      regexPattern: _regexController.text.trim(),
      formatString: _formatController.text.trim().isEmpty ? '\$0' : _formatController.text.trim(),
      scanDirectory: _dirController.text.trim().isEmpty ? null : _dirController.text.trim(),
      createdAt: widget.rule?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      if (_isEditing && rule.id != null) {
        await _repository.update(rule);
      } else {
        await _repository.insert(rule);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑规则' : '新建规则'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionHeader('基本信息'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '规则名称',
                hintText: '例如: 邮箱提取',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入规则名称' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _regexController,
              decoration: InputDecoration(
                labelText: '正则表达式',
                hintText: '例如: (\\w+)@(\\w+\\.\\w+)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.code),
                suffixIcon: _regexController.text.isNotEmpty
                    ? Icon(
                        _regexValid ? Icons.check_circle : Icons.error,
                        color: _regexValid ? Colors.green : Colors.red,
                      )
                    : null,
                errorText: _regexValid ? null : _regexError,
              ),
              maxLines: 2,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '请输入正则表达式';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _formatController,
              decoration: const InputDecoration(
                labelText: '自定义格式',
                hintText: '用 \$1, \$2 引用捕获组, 如 \$1@\$2',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.format_align_left),
                helperText: '默认 \$0 表示完整匹配',
              ),
              maxLines: 2,
              onChanged: (_) => _updatePreview(),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dirController,
              decoration: InputDecoration(
                labelText: '扫描目录',
                hintText: '选择要扫描的目录',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.folder_outlined),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: '选择目录',
                  onPressed: _pickDirectory,
                ),
              ),
              readOnly: false,
            ),
            const SizedBox(height: 24),
            _buildPreviewSection(),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey[700]));
  }

  Widget _buildPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('格式预览'),
        const SizedBox(height: 8),
        TextFormField(
          controller: _testFileNameController,
          decoration: const InputDecoration(
            labelText: '测试文件名',
            hintText: '输入文件名测试正则匹配',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.preview),
          ),
        ),
        if (_captureGroups.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('捕获组', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  ...List.generate(_captureGroups.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '\$$i → ${_captureGroups[i]}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    );
                  }),
                  if (_previewResult != null) ...[
                    const Divider(),
                    Text('格式化结果', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _previewResult!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (_regexValid && _compiledRegex != null && _testFileNameController.text.isNotEmpty && _captureGroups.isEmpty) ...[
          const SizedBox(height: 8),
          Text('不匹配', style: TextStyle(color: Colors.orange[700], fontSize: 13)),
        ],
      ],
    );
  }
}