import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// File-based logger for discovery/network operations.
///
/// Writes to `{appSupportDir}/discovery_log.txt` with timestamps, so you
/// can inspect scan results without connecting a debugger. Also calls
/// [debugPrint] so logs still appear in `flutter logs` when connected.
class DiscoveryLogger {
  static File? _file;

  /// Lazily initialise the log file on first write.
  static Future<File?> _ensureFile() async {
    if (_file != null) return _file;
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/discovery_log.txt');
      return _file;
    } catch (_) {
      // Non-fatal: logs will only appear in debugPrint.
      return null;
    }
  }

  /// Append a log line with a timestamp.
  static Future<void> log(String message) async {
    final line = '${_timestamp()} $message';
    debugPrint(line);
    final f = await _ensureFile();
    if (f == null) return;
    try {
      await f.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {
      // Non-fatal: if we can't write, just skip.
    }
  }

  /// Read all log lines.
  static Future<String> readAll() async {
    final f = await _ensureFile();
    if (f == null || !await f.exists()) return '(日志文件不存在)';
    try {
      return await f.readAsString();
    } catch (_) {
      return '(读取日志失败)';
    }
  }

  /// Clear the log file.
  static Future<void> clear() async {
    final f = await _ensureFile();
    if (f == null) return;
    try {
      await f.writeAsString('');
    } catch (_) {
      // Non-fatal.
    }
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
        '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';
  }

  static String _pad(int n) => n < 10 ? '0$n' : '$n';
}