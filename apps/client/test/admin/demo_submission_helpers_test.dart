import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/features/admin/demo_submission_helpers.dart';

void main() {
  group('coerceDemoSubmissionId', () {
    test('parses int, num, and string', () {
      expect(coerceDemoSubmissionId(42), 42);
      expect(coerceDemoSubmissionId(42.0), 42);
      expect(coerceDemoSubmissionId(' 7 '), 7);
    });

    test('returns null for invalid input', () {
      expect(coerceDemoSubmissionId(null), isNull);
      expect(coerceDemoSubmissionId(''), isNull);
      expect(coerceDemoSubmissionId('x'), isNull);
      expect(coerceDemoSubmissionId(Object()), isNull);
    });
  });

  group('demoFieldsJsonPreview', () {
    test('pretty-prints map fields', () {
      final out = demoFieldsJsonPreview({
        'fields': {'a': 1, 'b': 'x'},
      });
      expect(out, contains('"a"'));
      expect(out, contains('"b"'));
    });

    test('returns {} when fields missing or not a map', () {
      expect(demoFieldsJsonPreview({}), '{}');
      expect(demoFieldsJsonPreview({'fields': 'bad'}), '{}');
    });
  });

  group('formatDemoSubmissionDate', () {
    test('formats valid ISO strings', () {
      expect(
        formatDemoSubmissionDate('2026-04-03T14:05:00Z'),
        '2026-04-03 14:05',
      );
    });

    test('returns null for empty or null', () {
      expect(formatDemoSubmissionDate(null), isNull);
      expect(formatDemoSubmissionDate(''), isNull);
      expect(formatDemoSubmissionDate('   '), isNull);
    });

    test('returns raw string on parse failure', () {
      expect(formatDemoSubmissionDate('not-a-date'), 'not-a-date');
    });
  });

  group('soundCloudUrlsFromDemoSubmission', () {
    test('collects from links, fields, and message', () {
      final urls = soundCloudUrlsFromDemoSubmission({
        'links': [
          'https://soundcloud.com/artist/track',
          'https://example.com/ignore',
        ],
        'fields': {
          'demo': 'https://on.soundcloud.com/short',
        },
        'message': 'Hear https://soundcloud.app.goo.gl/abc ok',
      });
      expect(urls, contains('https://soundcloud.com/artist/track'));
      expect(urls, contains('https://on.soundcloud.com/short'));
      expect(urls, contains('https://soundcloud.app.goo.gl/abc'));
      expect(urls, isNot(contains('https://example.com/ignore')));
    });
  });
}
