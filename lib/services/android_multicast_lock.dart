import 'dart:io';

import 'package:flutter/services.dart';

/// Acquire/release the Android WiFi multicast lock.
///
/// Required for the UDP discovery listener to receive broadcast packets
/// while the app is in the foreground on Android. No-op on other platforms.
class AndroidMulticastLock {
  static const MethodChannel _channel = MethodChannel(
    'com.easymemory.easy_memory/multicast_lock',
  );
  static bool _acquired = false;

  /// Acquire the multicast lock. Safe to call multiple times.
  static Future<void> acquire() async {
    if (!Platform.isAndroid || _acquired) return;
    try {
      await _channel.invokeMethod<void>('acquire');
      _acquired = true;
    } catch (_) {
      // Non-fatal: discovery still works when the lock is not available.
    }
  }

  /// Release the multicast lock. Safe to call multiple times.
  static Future<void> release() async {
    if (!Platform.isAndroid || !_acquired) return;
    try {
      await _channel.invokeMethod<void>('release');
    } catch (_) {
      // Non-fatal.
    } finally {
      _acquired = false;
    }
  }
}