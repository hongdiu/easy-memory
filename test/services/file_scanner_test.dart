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

  group('IOFilesystemScanner', () {
    test('finds files matching regex pattern', () async {
      // Create test files with content so fileSize > 0
      File('${tempDir.path}/001_hello.txt').writeAsStringSync('hello');
      File('${tempDir.path}/002_world.txt').writeAsStringSync('world');
      File('${tempDir.path}/readme.md').writeAsStringSync('readme');

      final scanner = IOFilesystemScanner();
      final results = await scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      expect(results.length, 2);
      final fnames = results.map((r) => r.fileName).toSet();
      expect(fnames, containsAll(['001_hello.txt', '002_world.txt']));
      for (final r in results) {
        if (r.fileName == '001_hello.txt') {
          expect(r.match.group(1), '001');
        } else {
          expect(r.match.group(1), '002');
        }
        // fileSize should be present for real files
        expect(r.fileSize, greaterThan(0));
      }
    });

    test('returns empty list when no files match', () async {
      File('${tempDir.path}/readme.md').createSync();

      final scanner = IOFilesystemScanner();
      final results = await scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      expect(results, isEmpty);
    });

    test('returns empty list for empty directory', () async {
      final scanner = IOFilesystemScanner();
      final results = await scanner.scanDirectory(tempDir.path, r'.*');

      expect(results, isEmpty);
    });

    test('skips system directories', () async {
      // Create files inside system dirs that would match
      final gitDir = Directory('${tempDir.path}/.git');
      gitDir.createSync();
      File('${gitDir.path}/001_config.txt').createSync();

      final nodeDir = Directory('${tempDir.path}/node_modules');
      nodeDir.createSync();
      File('${nodeDir.path}/002_pkg.txt').createSync();

      // Create a matching file outside system dirs
      File('${tempDir.path}/003_valid.txt').createSync();

      final scanner = IOFilesystemScanner();
      final results = await scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      expect(results.length, 1);
      expect(results[0].fileName, '003_valid.txt');
    });

    test('recursively scans nested directories (max depth 10)', () async {
      // Create nested structure
      final subDir = Directory('${tempDir.path}/sub1');
      subDir.createSync();
      File('${subDir.path}/001_nested.txt').createSync();

      final deepDir = Directory('${tempDir.path}/sub1/sub2');
      deepDir.createSync();
      File('${deepDir.path}/002_deep.txt').createSync();

      File('${tempDir.path}/003_root.txt').createSync();

      final scanner = IOFilesystemScanner();
      final results = await scanner.scanDirectory(tempDir.path, r'(\d{3})_.*\.txt');

      // Should find all 3 files
      expect(results.length, 3);
      final names = results.map((r) => r.fileName).toSet();
      expect(names, containsAll(['001_nested.txt', '002_deep.txt', '003_root.txt']));
    });

    test('respects max depth of 10', () async {
      // Create a chain 12 levels deep
      var current = tempDir.path;
      for (var i = 0; i < 12; i++) {
        current = '$current/level$i';
        Directory(current).createSync(recursive: true);
      }
      File('$current/deep.txt').createSync();

      final scanner = IOFilesystemScanner();
      final results = await scanner.scanDirectory(tempDir.path, r'.*\.txt');

      // Should NOT find the file at depth 12
      expect(results, isEmpty);
    });
  });
}