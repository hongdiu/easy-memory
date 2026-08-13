import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persisted device-level configuration (device name, etc.).
class DeviceConfig {
  String label;

  DeviceConfig({required this.label});

  /// 平台可读的默认设备名（优于原始主机名——Android 上
  /// `Platform.localHostname` 固定返回 "localhost"，不适合展示）。
  static String defaultLabel() {
    if (kIsWeb) return 'Web 端';
    if (Platform.isAndroid) return 'Android设备';
    if (Platform.isWindows) return 'Windows电脑';
    if (Platform.isLinux) return 'Linux主机';
    if (Platform.isMacOS) return 'Mac电脑';
    return Platform.localHostname;
  }

  /// Load device config from disk; returns defaults if no file exists.
  static Future<DeviceConfig> load() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/device_config.json');
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString())
            as Map<String, dynamic>;
        // 兼容旧数据：历史保存过 localhost 的文件不再回退到原始主机名。
        final stored = (json['label'] as String?) ?? '';
        final label = (stored.isEmpty || stored == 'localhost')
            ? defaultLabel()
            : stored;
        return DeviceConfig(label: label);
      } catch (_) {
        // fall through to default
      }
    }
    return DeviceConfig(label: defaultLabel());
  }

  /// Persist to disk.
  Future<void> save() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/device_config.json');
    await file.writeAsString(jsonEncode({'label': label}));
  }
}