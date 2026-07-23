import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android 运行时权限请求服务
class PermissionService {
  /// 请求存储访问权限，返回是否已获得足够权限
  static Future<bool> requestStorage() async {
    if (!Platform.isAndroid) return true;

    // Android 13+ (API 33+) 用细分媒体权限
    if (await _isAndroid13OrAbove()) {
      final statuses = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();
      final granted = statuses.values.every((s) => s.isGranted || s.isLimited);
      if (granted) return true;
      // 媒体权限不够时，尝试 MANAGE_EXTERNAL_STORAGE
      return await _requestManageExternalStorage();
    }

    // Android 13 以下用传统存储权限
    final status = await Permission.storage.request();
    if (status.isGranted) return true;

    // Android 11+ (API 30+) 可以请求 MANAGE_EXTERNAL_STORAGE
    if (await _isAndroid11OrAbove()) {
      return await _requestManageExternalStorage();
    }

    return false;
  }

  /// 检查当前是否已有权限
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    if (await _isAndroid13OrAbove()) {
      final photos = await Permission.photos.isGranted || await Permission.photos.isLimited;
      final videos = await Permission.videos.isGranted || await Permission.videos.isLimited;
      final audio = await Permission.audio.isGranted || await Permission.audio.isLimited;
      if (photos || videos || audio) return true;
      return await Permission.manageExternalStorage.isGranted;
    }

    if (await Permission.storage.isGranted) return true;
    return await Permission.manageExternalStorage.isGranted;
  }

  static Future<bool> _isAndroid13OrAbove() async {
    try {
      final sdk = await _getAndroidSdkInt();
      return sdk >= 33;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isAndroid11OrAbove() async {
    try {
      final sdk = await _getAndroidSdkInt();
      return sdk >= 30;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _getAndroidSdkInt() async {
    // permission_handler 内部已处理，这里用 manageExternalStorage 的状态间接判断
    // 简单起见：直接尝试请求，由系统决定是否弹窗
    final build = Platform.version;
    debugPrint('[Permission] Platform.version: $build');
    // 通过 Platform.operatingSystemVersion 解析
    final versionStr = Platform.operatingSystemVersion;
    final match = RegExp(r'(\d+)').firstMatch(versionStr);
    if (match != null) {
      final sdk = int.tryParse(match.group(1)!);
      if (sdk != null) return sdk;
    }
    return 0;
  }

  static Future<bool> _requestManageExternalStorage() async {
    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;
    // 仍未授权，引导用户去系统设置
    if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    return false;
  }
}
