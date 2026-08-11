import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_memory/models/rule.dart';
import 'package:easy_memory/data/rule_repository.dart';
import 'package:easy_memory/theme/app_theme.dart';
import 'package:easy_memory/services/permission_service.dart';
import 'pages/rules_list_page.dart';
import 'pages/rule_edit_page.dart';
import 'pages/export_import_page.dart';
import 'pages/rule_detail_page.dart';
import 'pages/global_query_page.dart';
import 'pages/web_server_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Easy Memory',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(builder: (_) => const _HomePage());
          case '/rule/edit':
            // Support both arguments-based and id query param
            Rule? rule;
            if (settings.arguments is Rule) {
              rule = settings.arguments as Rule;
            } else if (settings.arguments is Map<String, dynamic>) {
              final args = settings.arguments as Map<String, dynamic>;
              final id = args['id'] as int?;
              if (id != null) {
                // Defer loading — we'll need the repo
                return MaterialPageRoute(
                  builder: (_) => _RuleEditLoader(ruleId: id),
                  settings: settings,
                );
              }
            }
            return MaterialPageRoute(
              builder: (_) => RuleEditPage(rule: rule),
              settings: settings,
            );
          case '/rule/detail':
            if (settings.arguments is Rule) {
              return MaterialPageRoute(
                builder: (_) => RuleDetailPage(rule: settings.arguments as Rule),
                settings: settings,
              );
            }
            return MaterialPageRoute(builder: (_) => const _HomePage());
          case '/export-import':
            return MaterialPageRoute(builder: (_) => const ExportImportPage());
          default:
            return MaterialPageRoute(builder: (_) => const _HomePage());
        }
      },
    );
  }
}

/// Root page with bottom navigation: 首页 (rules) and 查询 (global query).
class _HomePage extends StatefulWidget {
  const _HomePage();

  @override
  State<_HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<_HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    RulesListPage(),
    GlobalQueryPage(),
    WebServerPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermission();
  }

  Future<void> _checkAndRequestPermission() async {
    // Android 使用 SAF，无需 MANAGE_EXTERNAL_STORAGE 权限
    if (!kIsWeb && Platform.isAndroid) return;

    final hasPermission = await PermissionService.hasStoragePermission();
    if (!hasPermission && mounted) {
      final granted = await PermissionService.requestStorage();
      if (!granted && mounted) {
        // 首次请求失败，弹窗引导用户去设置
        final goSettings = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('需要存储权限'),
            content: const Text(
              'Easy Memory 需要「所有文件访问权限」才能扫描您选择的目录。\n\n'
              '请点击「去授权」，在设置中打开「允许访问所有文件」开关。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('稍后'),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.rule_outlined),
            selectedIcon: Icon(Icons.rule),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '查询',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: 'Web服务',
          ),
        ],
      ),
    );
  }
}

/// Loads a Rule by ID and shows RuleEditPage once loaded.
/// ponytail: one-shot loader, no caching, minimal glue
class _RuleEditLoader extends StatefulWidget {
  final int ruleId;
  const _RuleEditLoader({required this.ruleId});

  @override
  State<_RuleEditLoader> createState() => _RuleEditLoaderState();
}

class _RuleEditLoaderState extends State<_RuleEditLoader> {
  final RuleRepository _repo = RuleRepository();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Rule?>(
      future: _repo.getById(widget.ruleId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('规则编辑')),
            body: Center(child: Text('规则未找到 (ID: ${widget.ruleId})')),
          );
        }
        return RuleEditPage(rule: snapshot.data);
      },
    );
  }
}
