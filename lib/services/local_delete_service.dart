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
  /// If the physical file exists, it is deleted first. Only when the file
  /// is already missing (SafNotFoundException / File not found) is the DB
  /// record removed without a physical delete. Other errors (permission,
  /// IO) abort the operation and leave the DB record intact.
  ///
  /// Returns [LocalDeleteResult] — the caller is responsible for refreshing
  /// the UI on success.
  Future<LocalDeleteResult> delete(FileRecord record) async {
    try {
      // 1. Delete physical file — must succeed unless file is already gone
      final path = record.fullPath;
      if (path.startsWith('content://')) {
        // Android SAF
        if (!kIsWeb && Platform.isAndroid) {
          final saf = Saf();
          try {
            await saf.delete(path);
          } on SafNotFoundException {
            // File already gone → DB record still cleared below
          }
        } else {
          return const LocalDeleteResult(
            success: false,
            message: 'SAF URI 仅支持 Android 端',
          );
        }
      } else if (await File(path).exists()) {
        // Filesystem path (desktop: Windows / Linux / macOS)
        await File(path).delete();
      }

      // 2. Delete DB record — reached only if file was deleted or was missing
      await _fileRecordRepo.delete(record.id!);

      return const LocalDeleteResult(success: true, message: '删除成功');
    } catch (e) {
      return LocalDeleteResult(success: false, message: '删除失败: $e');
    }
  }
}