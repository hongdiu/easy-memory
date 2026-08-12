import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:saf/saf.dart';

import '../data/file_record_repository.dart';
import '../models/file_record.dart';

/// Result of a local delete attempt.
class LocalDeleteResult {
  final bool success;
  final String message;

  const LocalDeleteResult({required this.success, required this.message});
}

/// Service for deleting files on the **current** device + removing the
/// corresponding DB record. No remote endpoint configuration needed.
///
/// Platform dispatch:
/// - Android SAF URI (`content://...`) → `Saf().delete()`
/// - Filesystem path (desktop) → `File(path).delete()`
class LocalDeleteService {
  final FileRecordRepository _fileRecordRepo = FileRecordRepository();

  /// Delete [record]'s physical file **and** its DB row.
  ///
  /// Returns [LocalDeleteResult] — the caller is responsible for refreshing
  /// the UI on success.
  Future<LocalDeleteResult> delete(FileRecord record) async {
    try {
      // 1. Delete physical file
      final path = record.fullPath;
      if (path.startsWith('content://')) {
        // Android SAF
        if (!kIsWeb && Platform.isAndroid) {
          final saf = Saf();
          await saf.delete(path);
        } else {
          return const LocalDeleteResult(
            success: false,
            message: 'SAF URI 仅支持 Android 端',
          );
        }
      } else {
        // Filesystem path (desktop: Windows / Linux / macOS)
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
        // If file doesn't exist, still proceed to delete DB record
      }

      // 2. Delete DB record
      await _fileRecordRepo.delete(record.id!);

      return const LocalDeleteResult(success: true, message: '删除成功');
    } catch (e) {
      return LocalDeleteResult(success: false, message: '删除失败: $e');
    }
  }
}