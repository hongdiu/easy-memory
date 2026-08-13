import 'dart:io';

import 'package:flutter/services.dart';
import 'package:easy_memory/services/discovery_logger.dart';

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
    if (!Platform.isAndroid || _acquired) {
      if (!Platform.isAndroid) {
        DiscoveryLogger.log('[MulticastLock] acquire skipped (non-Android)');
      }
      return;
    }
    try {
      await _channel.invokeMethod<void>('acquire');
      _acquired = true;
      DiscoveryLogger.log('[MulticastLock] acquired (Android)');
    } catch (e) {
      DiscoveryLogger.log('[MulticastLock] acquire FAILED: $e — broadcast replies '
          'may be dropped by WiFi power saving');
    }
  }

  /// Release the multicast lock. Safe to call multiple times.
  static Future<void> release() async {
    if (!Platform.isAndroid || !_acquired) return;
    try {
      await _channel.invokeMethod<void>('release');
      DiscoveryLogger.log('[MulticastLock] released');
    } catch (e) {
      DiscoveryLogger.log('[MulticastLock] release FAILED: $e');
    } finally {
      _acquired = false;
    }
  }
}