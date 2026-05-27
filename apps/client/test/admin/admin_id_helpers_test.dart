import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/features/admin/admin_id_helpers.dart';

void main() {
  group('coerceIntId', () {
    test('parses int, num, and string', () {
      expect(coerceIntId(42), 42);
      expect(coerceIntId(42.0), 42);
      expect(coerceIntId(' 7 '), 7);
    });

    test('returns null for invalid input', () {
      expect(coerceIntId(null), isNull);
      expect(coerceIntId(''), isNull);
      expect(coerceIntId('x'), isNull);
      expect(coerceIntId(Object()), isNull);
    });
  });
}
