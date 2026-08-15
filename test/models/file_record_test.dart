import 'package:flutter_test/flutter_test.dart';

import 'package:easy_memory/models/file_record.dart';

void main() {
  FileRecord record(String name) => FileRecord(
        matchItemId: 1,
        fileName: name,
        fullPath: '/some/dir/$name',
        directory: '/some/dir',
        scannedAt: '2025-01-01T00:00:00',
      );

  group('FileRecord.isVideo', () {
    test('returns true for supported video extensions', () {
      expect(record('clip.mp4').isVideo, true);
      expect(record('clip.MP4').isVideo, true);
      expect(record('movie.mkv').isVideo, true);
      expect(record('movie.mov').isVideo, true);
      expect(record('anim.webm').isVideo, true);
    });

    test('returns false for unsupported extensions', () {
      expect(record('clip.avi').isVideo, false);
      expect(record('doc.pdf').isVideo, false);
      expect(record('photo.jpg').isVideo, false);
      expect(record('text.txt').isVideo, false);
    });

    test('returns false when no extension', () {
      expect(record('README').isVideo, false);
    });

    test('returns false when filename ends with a dot', () {
      expect(record('file.').isVideo, false);
    });
  });
}