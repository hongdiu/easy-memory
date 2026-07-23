import 'package:easy_memory/services/match_generator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MatchGenerator generator;

  setUp(() {
    generator = MatchGenerator();
  });

  group('MatchGenerator', () {
    test('dollar-zero returns entire match uppercased', () {
      final regex = RegExp(r'(\d{3})\s+(\w+)');
      final match = regex.firstMatch('001 happy')!;
      final result = generator.generateMatchValue(match, r'$0');
      expect(result, '001 HAPPY');
    });

    test('dollar-one captures first group', () {
      final regex = RegExp(r'(\d{3})\s+(\w+)');
      final match = regex.firstMatch('001 happy')!;
      final result = generator.generateMatchValue(match, r'$1');
      expect(result, '001');
    });

    test('dollar-two captures second group', () {
      final regex = RegExp(r'(\d{3})\s+(\w+)');
      final match = regex.firstMatch('001 happy')!;
      final result = generator.generateMatchValue(match, r'$2');
      expect(result, 'HAPPY');
    });

    test('combines multiple groups with separator', () {
      final regex = RegExp(r'(\d{3})\s+(\w+)');
      final match = regex.firstMatch('001 happy')!;
      final result = generator.generateMatchValue(match, r'$1@$2');
      expect(result, '001@HAPPY');
    });

    test('combines groups without separator', () {
      final regex = RegExp(r'(\d{3})\s+(\w+)');
      final match = regex.firstMatch('001 happy')!;
      final result = generator.generateMatchValue(match, r'$1$2');
      expect(result, '001HAPPY');
    });

    test('reversed group order', () {
      final regex = RegExp(r'(\d{3})\s+(\w+)');
      final match = regex.firstMatch('001 happy')!;
      final result = generator.generateMatchValue(match, r'$2-$1');
      expect(result, 'HAPPY-001');
    });

    test('empty format defaults to dollar-zero', () {
      final regex = RegExp(r'(\d{3})\s+(\w+)');
      final match = regex.firstMatch('001 happy')!;
      final result = generator.generateMatchValue(match, '');
      expect(result, '001 HAPPY');
    });

    test('uppercases all letters', () {
      final regex = RegExp(r'(\w+)');
      final match = regex.firstMatch('Hello World')!;
      final result = generator.generateMatchValue(match, r'$1');
      expect(result, 'HELLO');
    });

    test('handles non-capturing groups in format', () {
      final regex = RegExp(r'(\w+)-(\d+)');
      final match = regex.firstMatch('abc-123')!;
      final result = generator.generateMatchValue(match, r'$2_$1');
      expect(result, '123_ABC');
    });

    test('handles special characters in format string', () {
      final regex = RegExp(r'(\d+)\s+(\w+)');
      final match = regex.firstMatch('42 test')!;
      final result = generator.generateMatchValue(match, r'[$1] -> $2');
      expect(result, '[42] -> TEST');
    });

    test('handles literal backslash-n in format string', () {
      final regex = RegExp(r'(\d+)\s+(\w+)');
      final match = regex.firstMatch('42 test')!;
      final result = generator.generateMatchValue(match, r'$1\n$2');
      expect(result, '42\\NTEST');
    });

    test('handles match with no groups', () {
      final regex = RegExp(r'\d{3}');
      final match = regex.firstMatch('456')!;
      final result = generator.generateMatchValue(match, r'$0');
      expect(result, '456');
    });

    test('handles empty match group', () {
      final regex = RegExp(r'(\d*)(\w+)');
      final match = regex.firstMatch('abc')!;
      final result = generator.generateMatchValue(match, r'$1-$2');
      expect(result, '-ABC');
    });
  });
}