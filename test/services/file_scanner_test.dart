import 'dart:io';

import 'package:easy_memory/services/file_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('file_scanner_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FileScanner', () {
    test('finds files matching regex pattern', () {
      // Create test files
      File('${tempDir.path}/001_hello.txt').createSync();
      File('${tempDir.path}/002_world.txt').createSync();
      File('${tempDir.path}/readme.md').createSync();

      final scanner = FileScanner();
      final results = scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      expect(results.length, 2);
      expect(results[0].fileName, '001_hello.txt');
      expect(results[1].fileName, '002_world.txt');
      expect(results[0].match.group(1), '001');
      expect(results[1].match.group(1), '002');
    });

    test('returns empty list when no files match', () {
      File('${tempDir.path}/readme.md').createSync();

      final scanner = FileScanner();
      final results = scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      expect(results, isEmpty);
    });

    test('returns empty list for empty directory', () {
      final scanner = FileScanner();
      final results = scanner.scanDirectory(tempDir.path, r'.*');

      expect(results, isEmpty);
    });

    test('skips system directories', () {
      // Create files inside system dirs that would match
      final gitDir = Directory('${tempDir.path}/.git');
      gitDir.createSync();
      File('${gitDir.path}/001_config.txt').createSync();

      final nodeDir = Directory('${tempDir.path}/node_modules');
      nodeDir.createSync();
      File('${nodeDir.path}/002_pkg.txt').createSync();

      // Create a matching file outside system dirs
      File('${tempDir.path}/003_valid.txt').createSync();

      final scanner = FileScanner();
      final results = scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      expect(results.length, 1);
      expect(results[0].fileName, '003_valid.txt');
    });

    test('recursively scans nested directories (max depth 10)', () {
      // Create nested structure
      final subDir = Directory('${tempDir.path}/sub1');
      subDir.createSync();
      File('${subDir.path}/001_nested.txt').createSync();

      final deepDir = Directory('${tempDir.path}/sub1/sub2');
      deepDir.createSync();
      File('${deepDir.path}/002_deep.txt').createSync();

      File('${tempDir.path}/003_root.txt').createSync();

      final scanner = FileScanner();
      final results = scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      // Should find all 3 files
      expect(results.length, 3);
      final names = results.map((r) => r.fileName).toSet();
      expect(names, containsAll(['001_nested.txt', '002_deep.txt', '003_root.txt']));
    });

    test('respects max depth of 10', () {
      // Create a chain 12 levels deep
      var current = tempDir.path;
      for (var i = 0; i < 12; i++) {
        current = '$current/level$i';
        Directory(current).createSync(recursive: true);
      }
      File('$current/deep.txt').createSync();

      final scanner = FileScanner();
      final results = scanner.scanDirectory(tempDir.path, r'.*\.txt');

      // Should NOT find the file at depth 12
      expect(results, isEmpty);
    });
  });
}