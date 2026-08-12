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
  /// The DB record is **always** removed, even if the physical file is
  /// already missing or its deletion fails — the goal is to keep the DB
  /// free of ghost records.
  ///
  /// Returns [LocalDeleteResult] — the caller is responsible for refreshing
  /// the UI on success.
  Future<LocalDeleteResult> delete(FileRecord record) async {
    try {
      // 1. Delete physical file (best-effort — missing file is not an error)
      final path = record.fullPath;
      if (path.startsWith('content://')) {
        // Android SAF
        if (!kIsWeb && Platform.isAndroid) {
          final saf = Saf();
          try {
            await saf.delete(path);
          } catch (_) {
            // File already gone or deletion failed — DB record still cleared
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

      // 2. Delete DB record — always
      await _fileRecordRepo.delete(record.id!);

      return const LocalDeleteResult(success: true, message: '删除成功');
    } catch (e) {
      return LocalDeleteResult(success: false, message: '删除失败: $e');
    }
  }
}