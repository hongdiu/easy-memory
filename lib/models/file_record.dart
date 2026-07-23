class FileRecord {
  final int? id;
  final int matchItemId;
  final String fileName;
  final String fullPath;
  final String directory;
  final String scannedAt;

  const FileRecord({
    this.id,
    required this.matchItemId,
    required this.fileName,
    required this.fullPath,
    required this.directory,
    required this.scannedAt,
  });

  factory FileRecord.fromMap(Map<String, dynamic> map) {
    return FileRecord(
      id: map['id'] as int?,
      matchItemId: map['match_item_id'] as int,
      fileName: map['file_name'] as String,
      fullPath: map['full_path'] as String,
      directory: map['directory'] as String,
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
      'scanned_at': scannedAt,
    };
  }

  FileRecord copyWith({
    int? id,
    int? matchItemId,
    String? fileName,
    String? fullPath,
    String? directory,
    String? scannedAt,
  }) {
    return FileRecord(
      id: id ?? this.id,
      matchItemId: matchItemId ?? this.matchItemId,
      fileName: fileName ?? this.fileName,
      fullPath: fullPath ?? this.fullPath,
      directory: directory ?? this.directory,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }
}
