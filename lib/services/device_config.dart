import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Persisted device-level configuration (device name, etc.).
class DeviceConfig {
  String label;

  DeviceConfig({required this.label});

  /// Load device config from disk; returns defaults if no file exists.
  static Future<DeviceConfig> load() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/device_config.json');
    if (await file.exists()) {
      try {
        final json = jsonDecode(await file.readAsString())
            as Map<String, dynamic>;
        return DeviceConfig(
          label: json['label'] as String? ?? Platform.localHostname,
        );
      } catch (_) {
        // fall through to default
      }
    }
    return DeviceConfig(label: Platform.localHostname);
  }

  /// Persist to disk.
  Future<void> save() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/device_config.json');
    await file.writeAsString(jsonEncode({'label': label}));
  }
}