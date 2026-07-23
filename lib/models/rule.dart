class Rule {
  final int? id;
  final String name;
  final String regexPattern;
  final String formatString;
  final String? scanDirectory;
  final String createdAt;
  final String updatedAt;

  const Rule({
    this.id,
    required this.name,
    required this.regexPattern,
    this.formatString = '\$0',
    this.scanDirectory,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Rule.fromMap(Map<String, dynamic> map) {
    return Rule(
      id: map['id'] as int?,
      name: map['name'] as String,
      regexPattern: map['regex_pattern'] as String,
      formatString: map['format_string'] as String? ?? '\$0',
      scanDirectory: map['scan_directory'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'regex_pattern': regexPattern,
      'format_string': formatString,
      'scan_directory': scanDirectory,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  Rule copyWith({
    int? id,
    String? name,
    String? regexPattern,
    String? formatString,
    String? scanDirectory,
    String? createdAt,
    String? updatedAt,
  }) {
    return Rule(
      id: id ?? this.id,
      name: name ?? this.name,
      regexPattern: regexPattern ?? this.regexPattern,
      formatString: formatString ?? this.formatString,
      scanDirectory: scanDirectory ?? this.scanDirectory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
