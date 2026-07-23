class MatchGenerator {
  /// Generate a match value from [match] using [format].
  /// Supports $0 for the entire match, $1, $2, ... for capture groups.
  /// Result is always uppercased.
  /// If [format] is empty, defaults to '$0' (the entire match).
  String generateMatchValue(RegExpMatch match, String format) {
    final fmt = format.isEmpty ? '\$0' : format;
    final groups = <String>[];
    for (var i = 0; i <= match.groupCount; i++) {
      groups.add(match.group(i) ?? '');
    }
    final result = fmt.replaceAllMapped(
      RegExp(r'\$(\d+)'),
      (m) {
        final idx = int.parse(m.group(1)!);
        return idx < groups.length ? groups[idx] : m.group(0)!;
      },
    );
    return result.toUpperCase();
  }
}