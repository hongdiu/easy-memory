class MatchItem {
  final int? id;
  final int ruleId;
  final String matchValue;
  final String createdAt;

  const MatchItem({
    this.id,
    required this.ruleId,
    required this.matchValue,
    required this.createdAt,
  });

  factory MatchItem.fromMap(Map<String, dynamic> map) {
    return MatchItem(
      id: map['id'] as int?,
      ruleId: map['rule_id'] as int,
      matchValue: map['match_value'] as String,
      createdAt: map['created_at'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'rule_id': ruleId,
      'match_value': matchValue,
      'created_at': createdAt,
    };
  }

  MatchItem copyWith({
    int? id,
    int? ruleId,
    String? matchValue,
    String? createdAt,
  }) {
    return MatchItem(
      id: id ?? this.id,
      ruleId: ruleId ?? this.ruleId,
      matchValue: matchValue ?? this.matchValue,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
