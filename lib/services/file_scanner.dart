import 'dart:io';

import 'package:flutter/foundation.dart';

import 'saf_file_scanner.dart' show SafFileScanner;

/// 一次匹配到正则的文件扫描结果。
class FileScanResult {
  final String fileName;
  final String fullPath;
  final RegExpMatch match;

  const FileScanResult({
    required this.fileName,
    required this.fullPath,
    required this.match,
  });
}

/// 目录扫描器抽象接口。
///
/// - 桌面（Windows/Linux/macOS）：[IOFilesystemScanner]，直接读文件系统。
/// - Android：[SafFileScanner]，通过 Storage Access Framework (SAF) 访问用户
///   授权过的目录，无需 `MANAGE_EXTERNAL_STORAGE` 权限。
abstract class FileScanner {
  /// 递归扫描 [directory] 中匹配 [regexPattern] 的文件。
  ///
  /// [directory] 在桌面端是文件系统路径，在 Android 端是 SAF URI
  /// （`content://...`）。最大深度 10。返回匹配的 [FileScanResult]。
  Future<List<FileScanResult>> scanDirectory(
    String directory,
    String regexPattern,
  );
}

/// 按平台创建合适的 [FileScanner]。
///
/// Android 使用 SAF 实现（需要用户通过系统选择器授权目录），
/// 其余平台使用基于 [Directory] 的本地文件系统实现。
FileScanner createFileScanner() {
  if (!kIsWeb && Platform.isAndroid) {
    return SafFileScanner();
  }
  return IOFilesystemScanner();
}

/// 基于本地文件系统的扫描器（Windows / Linux / macOS）。
class IOFilesystemScanner extends FileScanner {
  /// ponytail: static set of system dirs to skip, add when configurable
  static const _systemDirs = {
    '.git',
    'node_modules',
    'build',
    '.dart_tool',
    '.idea',
    '.vscode',
    '__pycache__',
    '.svn',
    '.hg',
    '.gradle',
    '.cache',
    '.pub-cache',
    'vendor',
    '.next',
    'dist',
    '.turbo',
    '.mypy_cache',
    '.nox',
    '.tox',
    '.eggs',
    '.pytest_cache',
    '.coverage',
    '.nyc_output',
    '.serverless',
    '.terraform',
  };

  @override
  Future<List<FileScanResult>> scanDirectory(
    String directory,
    String regexPattern,
  ) async {
    final regex = RegExp(regexPattern);
    final results = <FileScanResult>[];
    final dir = Directory(directory);
    if (!dir.existsSync()) {
      debugPrint('[FileScanner] 目录不存在: $directory');
      return results;
    }
    _scanRecursive(dir, regex, results, 0);
    return results;
  }

  void _scanRecursive(
    Directory dir,
    RegExp regex,
    List<FileScanResult> results,
    int depth,
  ) {
    if (depth > 10) return;

    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync();
    } catch (e) {
      debugPrint('[FileScanner] 无法读取目录 ${dir.path}: $e');
      return;
    }
    for (final entity in entities) {
      if (entity is Directory) {
        if (_systemDirs.contains(entity.path.split(Platform.pathSeparator).last)) {
          continue;
        }
        _scanRecursive(entity, regex, results, depth + 1);
      } else if (entity is File) {
        final fileName = entity.path.split(Platform.pathSeparator).last;
        final match = regex.firstMatch(fileName);
        if (match != null) {
          results.add(FileScanResult(
            fileName: fileName,
            fullPath: entity.path,
            match: match,
          ));
        }
      }
    }
  }
}