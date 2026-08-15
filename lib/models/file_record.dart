class FileRecord {
  final int? id;
  final int matchItemId;
  final String fileName;
  final String fullPath;
  final String directory;
  final int? fileSize;
  final String scannedAt;

  const FileRecord({
    this.id,
    required this.matchItemId,
    required this.fileName,
    required this.fullPath,
    required this.directory,
    this.fileSize,
    required this.scannedAt,
  });

  /// Human-readable file size, e.g. "1.5 MB". Returns "未知" when null.
  String get formattedSize {
    final bytes = fileSize;
    if (bytes == null) return '未知';
    if (bytes < 1024) return '1 KB';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB';
  }

  /// Video extensions supported by ExoPlayer (Android) natively.
  /// `.avi` is intentionally excluded (incomplete container support).
  static const List<String> _videoExtensions = ['mp4', 'mkv', 'mov', 'webm'];

  /// Whether this file is a video that the app can preview.
  bool get isVideo {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return false;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return _videoExtensions.contains(ext);
  }

  factory FileRecord.fromMap(Map<String, dynamic> map) {
    return FileRecord(
      id: map['id'] as int?,
      matchItemId: map['match_item_id'] as int,
      fileName: map['file_name'] as String,
      fullPath: map['full_path'] as String,
      directory: map['directory'] as String,
      fileSize: map['file_size'] as int?,
      scannedAt: map['scanned_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'match_item_id': matchItemId,
      'file_name': fileName,
      'full_path': fullPath,
      'directory': directory,
      'file_size': fileSize,
      'scanned_at': scannedAt,
    };
  }

  FileRecord copyWith({
    int? id,
    int? matchItemId,
    String? fileName,
    String? fullPath,
    String? directory,
    int? fileSize,
    String? scannedAt,
  }) {
    return FileRecord(
      id: id ?? this.id,
      matchItemId: matchItemId ?? this.matchItemId,
      fileName: fileName ?? this.fileName,
      fullPath: fullPath ?? this.fullPath,
      directory: directory ?? this.directory,
      fileSize: fileSize ?? this.fileSize,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }
}
