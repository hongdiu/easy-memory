import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Android 运行时权限请求服务
///
/// 注意：扫描任意目录需要 MANAGE_EXTERNAL_STORAGE（Android 11+）
/// 或 READ_EXTERNAL_STORAGE（Android 10 以下）。
/// 媒体权限（READ_MEDIA_IMAGES/VIDEO/AUDIO）仅针对媒体文件，不能用于扫描任意目录。
class PermissionService {
  /// 请求存储访问权限，返回是否已获得足够权限
  static Future<bool> requestStorage() async {
    if (!Platform.isAndroid) return true;

    // Android 11+：需要 MANAGE_EXTERNAL_STORAGE（"所有文件访问权限"）
    // 这个权限只能通过系统设置页面授予，无法弹出普通对话框
    if (await _isAndroid11OrAbove()) {
      return await _requestManageExternalStorage();
    }

    // Android 10 及以下：用传统存储权限
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// 检查当前是否已有足够权限（用于扫描任意目录）
  static Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Android 11+：必须要有 MANAGE_EXTERNAL_STORAGE
    if (await _isAndroid11OrAbove()) {
      return await Permission.manageExternalStorage.isGranted;
    }

    // Android 10 及以下：READ_EXTERNAL_STORAGE
    return await Permission.storage.isGranted;
  }

  static Future<bool> _isAndroid11OrAbove() async {
    final sdk = await _getAndroidSdkInt();
    return sdk >= 11;
  }

  static Future<int> _getAndroidSdkInt() async {
    // Platform.operatingSystemVersion 返回 Android 版本号，如 "13"、"14"、"11"
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
    return false;
  }

  /// 打开系统设置（"所有文件访问权限"页面），供用户手动授权。
  /// 返回 true 表示授权成功。
  static Future<bool> openSettingsAndCheck() async {
    await openAppSettings();
    // 从设置返回后重新检查
    return hasStoragePermission();
  }
}