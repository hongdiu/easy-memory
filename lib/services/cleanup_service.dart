import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:saf/saf.dart';

import '../data/file_record_repository.dart';

/// Progress of a cleanup operation.
class CleanupProgress {
  final int percent;
  final String message;

  const CleanupProgress({required this.percent, required this.message});
}

/// Result of a cleanup operation.
class CleanupResult {
  final int totalRecords;
  final int localRecords;
  final int cleanedRecords;

  const CleanupResult({
    required this.totalRecords,
    required this.localRecords,
    required this.cleanedRecords,
  });
}

/// Service for cleaning up ghost DB records — records whose physical file
/// no longer exists on the **current** device.
///
/// Strategy (方案一):
/// 1. Filter by platform prefix to identify local paths only
/// 2. Check physical file existence for each local record
/// 3. Delete DB record if the file is gone
/// 4. Skip remote paths entirely (no false positives)
class CleanupService {
  final FileRecordRepository _fileRecordRepo = FileRecordRepository();

  /// Whether [path] looks like a local path on the current platform.
  /// Remote paths (synced from other devices) are skipped.
  bool _isLocalPath(String path) {
    if (kIsWeb) return false;
    if (Platform.isWindows) {
      return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
    }
    if (Platform.isAndroid) {
      return path.startsWith('content://') || path.startsWith('/storage/');
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return path.startsWith('/');
    }
    return false;
  }

  /// Check whether a physical file exists at [path].
  Future<bool> _fileExists(String path) async {
    if (path.startsWith('content://')) {
      // SAF URI — use saf.exists() (no side effects)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final saf = Saf();
          return await saf.exists(path);
        } catch (_) {
          // Permission error etc. — treat as exists (conservative)
          return true;
        }
      }
      // SAF URI on non-Android — should not happen, skip
      return true;
    }
    // Filesystem path
    return await File(path).exists();
  }

  /// Run cleanup: scan all file records, check local files, delete ghosts.
  ///
  /// [onProgress] is called after each record for UI updates.
  Future<CleanupResult> cleanup({
    void Function(CleanupProgress)? onProgress,
  }) async {
    final records = await _fileRecordRepo.getAll();
    final total = records.length;
    if (total == 0) {
      return const CleanupResult(
        totalRecords: 0,
        localRecords: 0,
        cleanedRecords: 0,
      );
    }

    onProgress?.call(const CleanupProgress(percent: 0, message: '扫描中...'));

    // Separate local vs remote
    final localRecords = records.where((r) => _isLocalPath(r.fullPath)).toList();
    final localCount = localRecords.length;
    final remoteCount = total - localCount;

    onProgress?.call(CleanupProgress(
      percent: 0,
      message: '共 $total 条记录，本地 $localCount 条，跳过 $remoteCount 条远程路径',
    ));

    // Check existence for each local record
    int cleaned = 0;
    for (int i = 0; i < localRecords.length; i++) {
      final record = localRecords[i];
      final exists = await _fileExists(record.fullPath);
      if (!exists) {
        await _fileRecordRepo.delete(record.id!);
        cleaned++;
      }

      // Report progress (0 → 100%)
      final percent = ((i + 1) * 100 / localRecords.length).round();
      onProgress?.call(CleanupProgress(
        percent: percent,
        message: '检查中 ($cleaned 条幽灵记录已清理)...',
      ));
    }

    return CleanupResult(
      totalRecords: total,
      localRecords: localCount,
      cleanedRecords: cleaned,
    );
  }
}