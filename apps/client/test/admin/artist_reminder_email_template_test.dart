import 'package:flutter_test/flutter_test.dart';
import 'package:labelops_client/features/admin/artist_reminder_email_template.dart';

void main() {
  group('applyArtistReminderTemplate', () {
    test('replaces tokens case-insensitively', () {
      final result = applyArtistReminderTemplate(
        'Hi {NAME}, from {artist_brand}',
        const {'name': 'Maya', 'artist_brand': 'Maya Waves'},
      );
      expect(result, 'Hi Maya, from Maya Waves');
    });
  });

  group('buildArtistReminderTemplateValues', () {
    test('prefers artist brand for name token', () {
      final values = buildArtistReminderTemplateValues({
        'name': 'Legal Name',
        'email': 'maya@example.com',
        'extra': {'artist_brand': 'Maya Waves'},
      });
      expect(values['name'], 'Maya Waves');
      expect(values['email'], 'maya@example.com');
    });
  });

  group('renderArtistReminderEmail', () {
    test('renders plain body as html with line breaks', () {
      final rendered = renderArtistReminderEmail(
        subjectTemplate: 'Hello {name}',
        bodyTemplate: 'Line one\nLine two',
        values: const {'name': 'Maya'},
      );
      expect(rendered.subject, 'Hello Maya');
      expect(rendered.bodyHtml, contains('<br>'));
      expect(rendered.bodyText, contains('Line one'));
    });
  });
}
