import 'dart:convert';
import 'dart:io';

import 'package:saf/saf.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../data/rule_repository.dart';
import '../data/match_item_repository.dart';
import '../data/file_record_repository.dart';

class WebServerService {
  final RuleRepository _ruleRepo = RuleRepository();
  final MatchItemRepository _matchItemRepo = MatchItemRepository();
  final FileRecordRepository _fileRecordRepo = FileRecordRepository();
  String _apiKey;

  HttpServer? _server;
  int _port = 8080;

  bool get isRunning => _server != null;
  int get port => _port;

  // ignore: prefer_initializing_formals - `_apiKey` 非 final，start() 内可被覆盖
  WebServerService({String apiKey = ''}) : _apiKey = apiKey;

  /// Auth middleware: checks X-Api-Key on /api/* routes.
  shelf.Middleware get _authMiddleware {
    return (innerHandler) {
      return (request) async {
        if (_apiKey.isNotEmpty && request.url.path.startsWith('api/')) {
          final key = request.headers['x-api-key'];
          if (key == null || key != _apiKey) {
            return shelf.Response.unauthorized(
              jsonEncode({'success': false, 'error': '未授权'}),
            );
          }
        }
        return innerHandler(request);
      };
    };
  }

  /// Start the HTTP server on [port] with an optional [apiKey].
  /// Returns the actual port bound.
  Future<int> start({int port = 8080, String apiKey = ''}) async {
    if (_server != null) throw StateError('Server already running');

    // Use the provided apiKey, fall back to the constructor value.
    final effectiveApiKey = apiKey.isNotEmpty ? apiKey : _apiKey;
    _apiKey = effectiveApiKey;

    final router = Router();

    router.get('/', _serveIndex);
    router.get('/api/health', _handleHealth);
    router.get('/api/query', _handleQuery);
    router.get('/api/rules', _handleRules);
    router.get('/api/sync/data', _handleSyncData);
    router.get('/api/sync/records', _handleSyncRecords);
    router.post('/api/delete', _handleDelete);

    final handler = shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_authMiddleware)
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
    _port = _server!.port;
    return _port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// GET / — serve the embedded Web query page
  Future<shelf.Response> _serveIndex(shelf.Request request) async {
    return shelf.Response.ok(
      _webHtml,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }

  /// GET /api/query?match=[value] -- search match items and return enriched JSON
  Future<shelf.Response> _handleQuery(shelf.Request request) async {
    final matchValue = request.url.queryParameters['match'] ?? '';
    if (matchValue.isEmpty) {
      return shelf.Response.ok(
        jsonEncode([]),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    final items = await _matchItemRepo.searchByValue(matchValue);
    if (items.isEmpty) {
      return shelf.Response.ok(
        jsonEncode([]),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    final results = <Map<String, dynamic>>[];
    for (final item in items) {
      final rule = await _ruleRepo.getById(item.ruleId);
      final files = await _fileRecordRepo.getByMatchItemId(item.id!);
      results.add({
        'match_value': item.matchValue,
        'rule_name': rule?.name ?? '(未知规则)',
        'files': files
            .map((f) => {
                  'file_name': f.fileName,
                  'full_path': f.fullPath,
                })
            .toList(),
      });
    }

    return shelf.Response.ok(
      jsonEncode(results),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// GET /api/rules — return all rules as JSON
  Future<shelf.Response> _handleRules(shelf.Request request) async {
    final rules = await _ruleRepo.getAll();
    final result = rules.map((r) => {
      'id': r.id,
      'name': r.name,
      'regex_pattern': r.regexPattern,
      'scan_directory': r.scanDirectory,
    }).toList();

    return shelf.Response.ok(
      jsonEncode(result),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// GET /api/sync/data — return all rules + match_items for sync.
  /// Match items carry their rule_id FK, used by the client for natural-key
  /// merge (rule_id + match_value). This endpoint is NOT paginated — rules
  /// and match items are small enough to send in one shot.
  Future<shelf.Response> _handleSyncData(shelf.Request request) async {
    final rules = await _ruleRepo.getAll();
    final rulesJson = rules.map((r) => r.toMap()).toList();

    final List<Map<String, dynamic>> matchItemsJson = [];
    for (final rule in rules) {
      if (rule.id == null) continue;
      final items = await _matchItemRepo.getByRuleId(rule.id!);
      matchItemsJson.addAll(items.map((i) => i.toMap()));
    }

    final body = jsonEncode({
      'rules': rulesJson,
      'match_items': matchItemsJson,
    });

    return shelf.Response.ok(
      body,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// GET /api/sync/records?offset=0&limit=100 — paginated file records.
  /// Returns the total count + the current page.
  Future<shelf.Response> _handleSyncRecords(shelf.Request request) async {
    final offset =
        int.tryParse(request.url.queryParameters['offset'] ?? '') ?? 0;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 100;
    final clampedLimit = limit.clamp(1, 500);

    final total = await _fileRecordRepo.count();
    final records = await _fileRecordRepo.getPage(offset, clampedLimit);
    final recordsJson = records.map((r) => r.toMap()).toList();

    final body = jsonEncode({
      'total': total,
      'offset': offset,
      'limit': clampedLimit,
      'records': recordsJson,
    });

    return shelf.Response.ok(
      body,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// GET /api/health — return server status + platform info
  Future<shelf.Response> _handleHealth(shelf.Request request) async {
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
            ? 'windows'
            : Platform.isLinux
                ? 'linux'
                : Platform.isMacOS
                    ? 'macos'
                    : 'unknown';
    return shelf.Response.ok(
      jsonEncode({
        'status': 'ok',
        'platform': platform,
        'timestamp': DateTime.now().toIso8601String(),
      }),
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  /// POST /api/delete — delete a file by path (filesystem path or SAF URI)
  ///
  /// The DB record is **always** removed, even if the physical file is
  /// already missing or its deletion fails — the goal is to keep the DB
  /// free of ghost records. A warning is returned when the physical file
  /// was already missing.
  Future<shelf.Response> _handleDelete(shelf.Request request) async {
    try {
      final body = jsonDecode(await request.readAsString())
          as Map<String, dynamic>;
      final path = body['path'] as String?;
      if (path == null || path.isEmpty) {
        return shelf.Response(400,
            body: jsonEncode({'success': false, 'error': '缺少 path 参数'}));
      }

      // 1. Delete physical file (best-effort — missing file is not an error)
      var fileMissing = false;
      if (path.startsWith('content://')) {
        // Android SAF URI — only supported on Android
        if (!Platform.isAndroid) {
          return shelf.Response(400,
              body: jsonEncode({'success': false, 'error': 'SAF URI 仅支持 Android 端'}));
        }
        final saf = Saf();
        try {
          await saf.delete(path);
        } catch (_) {
          // File already gone or deletion failed — DB record still cleared
          fileMissing = true;
        }
      } else if (await File(path).exists()) {
        // Filesystem path
        await File(path).delete();
      } else {
        // File already missing → skip physical delete, still clear DB below
        fileMissing = true;
      }

      // 2. Delete DB record — always
      final deletedRows = await _fileRecordRepo.deleteByFullPath(path);
      final response = {'success': true};
      if (deletedRows == 0) {
        response['warning'] =
            '物理文件已删除，但未找到匹配的 DB 记录 (full_path 不一致)';
      } else if (fileMissing) {
        response['warning'] = '文件已不存在，已清理对应 DB 记录';
      }

      return shelf.Response.ok(
        jsonEncode(response),
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    } catch (e) {
      return shelf.Response(500,
          body: jsonEncode({'success': false, 'error': e.toString()}));
    }
  }
}

// ponytail: embedded HTML, zero external deps, no CDN, works offline
const _webHtml = r'''<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Easy Memory - 查询</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #f5f7fa; color: #1e293b; min-height: 100vh;
  }
  .container { max-width: 720px; margin: 0 auto; padding: 48px 16px; }
  h1 { font-size: 24px; font-weight: 600; margin-bottom: 8px; }
  .subtitle { color: #64748b; margin-bottom: 24px; font-size: 14px; }
  .search-box {
    display: flex; gap: 8px; margin-bottom: 24px;
  }
  .search-box input {
    flex: 1; padding: 10px 14px; border: 1px solid #cbd5e1; border-radius: 8px;
    font-size: 15px; outline: none; transition: border-color .2s;
  }
  .search-box input:focus { border-color: #2563eb; }
  .search-box button {
    padding: 10px 24px; background: #2563eb; color: #fff; border: none;
    border-radius: 8px; font-size: 15px; cursor: pointer; font-weight: 500;
  }
  .search-box button:hover { background: #1d4ed8; }
  .search-box button:disabled { background: #93c5fd; cursor: not-allowed; }
  .status { font-size: 13px; color: #64748b; margin-bottom: 16px; }
  .result-card {
    background: #fff; border-radius: 10px; padding: 16px; margin-bottom: 12px;
    box-shadow: 0 1px 3px rgba(0,0,0,.08);
  }
  .result-card h3 { font-size: 16px; margin-bottom: 4px; }
  .result-card .rule-tag {
    display: inline-block; font-size: 12px; background: #eff6ff; color: #2563eb;
    padding: 2px 8px; border-radius: 4px; margin-bottom: 10px;
  }
  .file-list { list-style: none; }
  .file-list li {
    display: flex; justify-content: space-between; align-items: center;
    padding: 6px 0; border-top: 1px solid #f1f5f9; font-size: 13px;
  }
  .file-list li:first-child { border-top: none; }
  .file-path { color: #475569; word-break: break-all; flex: 1; }
  .copy-btn {
    font-size: 12px; padding: 3px 10px; background: #f1f5f9; border: 1px solid #e2e8f0;
    border-radius: 4px; cursor: pointer; margin-left: 8px; white-space: nowrap;
  }
  .copy-btn:hover { background: #e2e8f0; }
  .empty { text-align: center; color: #94a3b8; padding: 48px 0; }
  .empty .icon { font-size: 48px; margin-bottom: 12px; }
  .error { color: #dc2626; text-align: center; padding: 24px; }
  @media (max-width: 480px) {
    .container { padding: 24px 12px; }
    .search-box { flex-direction: column; }
    .file-list li { flex-direction: column; align-items: flex-start; gap: 4px; }
    .copy-btn { margin-left: 0; }
  }
</style>
</head>
<body>
<div class="container">
  <h1>Easy Memory</h1>
  <p class="subtitle">输入匹配项值，查询关联文件</p>
  <div class="search-box">
    <input type="text" id="searchInput" placeholder="输入匹配项，如 ABC_123" autofocus>
    <button id="searchBtn" onclick="doSearch()">查询</button>
  </div>
  <div id="status" class="status"></div>
  <div id="results"></div>
</div>
<script>
  const input = document.getElementById('searchInput');
  const btn = document.getElementById('searchBtn');
  const status = document.getElementById('status');
  const results = document.getElementById('results');

  input.addEventListener('keydown', e => { if (e.key === 'Enter') doSearch(); });

  async function doSearch() {
    const q = input.value.trim();
    if (!q) { status.textContent = '请输入搜索内容'; return; }
    btn.disabled = true;
    status.textContent = '查询中...';
    results.innerHTML = '';
    try {
      const res = await fetch('/api/query?match=' + encodeURIComponent(q));
      if (!res.ok) throw new Error('HTTP ' + res.status);
      const data = await res.json();
      if (data.length === 0) {
        results.innerHTML = '<div class="empty"><div class="icon">&#128269;</div>未找到匹配结果</div>';
        status.textContent = '';
      } else {
        status.textContent = '找到 ' + data.length + ' 个匹配项';
        results.innerHTML = data.map(item => {
          const files = (item.files || []).map(f => {
            const path = f.full_path || '';
            return '<li><span class="file-path">' + escapeHtml(path) + '</span><button class="copy-btn" onclick="copyPath(\'' + escapeHtml(path) + '\')">复制</button></li>';
          }).join('');
          return '<div class="result-card"><h3>' + escapeHtml(item.match_value) + '</h3><span class="rule-tag">' + escapeHtml(item.rule_name) + '</span><ul class="file-list">' + files + '</ul></div>';
        }).join('');
      }
    } catch (e) {
      results.innerHTML = '<div class="error">查询失败: ' + e.message + '<br>请确认服务已启动</div>';
      status.textContent = '';
    }
    btn.disabled = false;
  }

  function copyPath(text) {
    navigator.clipboard.writeText(text).then(() => {
      const btn = event.target;
      const orig = btn.textContent;
      btn.textContent = '已复制';
      setTimeout(() => btn.textContent = orig, 1500);
    }).catch(() => {});
  }

  function escapeHtml(s) {
    if (!s) return '';
    return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }
</script>
</body>
</html>''';