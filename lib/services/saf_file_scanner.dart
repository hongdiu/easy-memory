import 'package:flutter/foundation.dart';
import 'package:saf/saf.dart';

import 'file_scanner.dart';

/// 基于 Storage Access Framework (SAF) 的 Android 目录扫描器。
///
/// 用户通过系统目录选择器授权后，应用即可跨重启访问该目录，
/// 无需声明 `MANAGE_EXTERNAL_STORAGE`（"所有文件访问权限"）。
class SafFileScanner extends FileScanner {
  final Saf _saf = Saf();

  /// 打开系统目录选择器，返回所选目录的 SAF URI（`content://...`）。
  ///
  /// 用户取消时返回 null。授权会持久化，后续启动无需再次选择。
  Future<String?> pickDirectory() async {
    final dir = await _saf.pickDirectory();
    return dir?.uri;
  }

  /// 检查 [uri] 是否仍持有有效授权。
  Future<bool> isGranted(String uri) async {
    try {
      final grants = await _saf.persistedPermissions();
      return grants.any((g) => g.uri == uri);
    } catch (e) {
      debugPrint('[SafFileScanner] 检查授权失败: $e');
      return false;
    }
  }

  /// 恢复用户最近授予的目录 URI（供启动时自动恢复授权）。
  Future<String?> lastGrantedUri() async {
    try {
      final grants = await _saf.persistedPermissions();
      if (grants.isEmpty) return null;
      return grants.first.uri;
    } catch (e) {
      debugPrint('[SafFileScanner] 读取授权失败: $e');
      return null;
    }
  }

  @override
  Future<List<FileScanResult>> scanDirectory(
    String directory,
    String regexPattern,
  ) async {
    final regex = RegExp(regexPattern);
    final results = <FileScanResult>[];

    try {
      await for (final walkEntry in _saf.walk(directory)) {
        final file = walkEntry.file;
        if (file.isDir) continue;
        final match = regex.firstMatch(file.name);
        if (match != null) {
          results.add(FileScanResult(
            fileName: file.name,
            fullPath: file.uri,
            match: match,
            fileSize: file.length,
          ));
        }
      }
    } catch (e) {
      debugPrint('[SafFileScanner] 扫描失败 $directory: $e');
    }

    return results;
  }
}