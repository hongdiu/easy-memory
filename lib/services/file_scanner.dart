import 'dart:io';
import 'package:flutter/foundation.dart';

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

class FileScanner {
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

  /// Recursively scan [directory] for files matching [regexPattern].
  /// Max depth is 10. Returns matched [FileScanResult]s.
  List<FileScanResult> scanDirectory(String directory, String regexPattern) {
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