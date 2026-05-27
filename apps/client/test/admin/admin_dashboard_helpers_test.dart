import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/features/admin/admin_dashboard_helpers.dart';

void main() {
  group('formatLastGitUpdate', () {
    test('formats ISO timestamps in local time', () {
      final formatted = formatLastGitUpdate('2026-04-03T14:05:00Z');
      expect(formatted, isNotNull);
      expect(formatted, contains('2026'));
    });

    test('returns null for empty values', () {
      expect(formatLastGitUpdate(null), isNull);
      expect(formatLastGitUpdate(''), isNull);
    });

    test('returns raw string when parse fails', () {
      expect(formatLastGitUpdate('not-a-date'), 'not-a-date');
    });
  });
}
