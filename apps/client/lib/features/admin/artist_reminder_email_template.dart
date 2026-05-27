import 'dart:convert';

import 'package:flutter/material.dart';

/// Default subject for artist reminder emails (Reports > Artist reminders).
const String defaultArtistReminderSubject =
    'Checking in - do you have new music for us?';

/// Default body for artist reminder emails.
const String defaultArtistReminderBody = r'''Hi {name},

Hope you're doing well. We're reaching out to see if you have any new music you'd like to send us. We'd love to hear from you.

Best regards''';

class ReminderTemplateField {
  const ReminderTemplateField(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  String get token => '{$key}';
}

const List<ReminderTemplateField> artistReminderTemplateFields = [
  ReminderTemplateField(
      'name', 'Artist name', 'Preferred display name for the artist'),
  ReminderTemplateField(
      'artist_brand', 'Artist brand', 'Artist brand field from the profile'),
  ReminderTemplateField(
      'full_name', 'Full name', 'Artist full name from the profile'),
  ReminderTemplateField('email', 'Email', 'Primary artist email address'),
  ReminderTemplateField('website', 'Website', 'Artist website URL'),
  ReminderTemplateField('facebook', 'Facebook', 'Facebook URL'),
  ReminderTemplateField('twitter_1', 'Twitter 1', 'First Twitter/X URL'),
  ReminderTemplateField('twitter_2', 'Twitter 2', 'Second Twitter/X URL'),
  ReminderTemplateField('instagram', 'Instagram', 'Instagram URL'),
  ReminderTemplateField('spotify', 'Spotify', 'Spotify URL'),
  ReminderTemplateField('soundcloud', 'SoundCloud', 'SoundCloud URL'),
  ReminderTemplateField('youtube', 'YouTube', 'YouTube URL'),
  ReminderTemplateField('tiktok', 'TikTok', 'TikTok URL'),
  ReminderTemplateField('apple_music', 'Apple Music', 'Apple Music URL'),
  ReminderTemplateField('other_1', 'Other 1', 'Additional artist link'),
  ReminderTemplateField('other_2', 'Other 2', 'Additional artist link'),
  ReminderTemplateField('other_3', 'Other 3', 'Additional artist link'),
  ReminderTemplateField(
      'address', 'Address', 'Address from the artist profile'),
  ReminderTemplateField(
      'comments', 'Comments', 'Internal comments stored on the artist'),
  ReminderTemplateField('notes', 'Notes', 'Artist notes'),
  ReminderTemplateField(
      'source_row', 'Source row', 'Original import source row'),
];

const Map<String, String> sampleArtistReminderTemplateValues = {
  'name': 'Test Artist',
  'artist_brand': 'Test Artist',
  'full_name': 'Test Artist',
  'email': 'test.artist@example.com',
  'website': 'https://example.com',
  'facebook': 'https://facebook.com/testartist',
  'twitter_1': 'https://x.com/testartist',
  'twitter_2': 'https://x.com/testartist_label',
  'instagram': 'https://instagram.com/testartist',
  'spotify': 'https://open.spotify.com/artist/testartist',
  'soundcloud': 'https://soundcloud.com/testartist',
  'youtube': 'https://youtube.com/@testartist',
  'tiktok': 'https://tiktok.com/@testartist',
  'apple_music': 'https://music.apple.com/artist/testartist',
  'other_1': 'https://beatport.com/artist/testartist',
  'other_2': 'https://bandcamp.com/testartist',
  'other_3': 'https://residentadvisor.net/dj/testartist',
  'address': 'Tel Aviv, Israel',
  'comments': 'Looking for new demos this quarter.',
  'notes': 'Prefers melodic techno and progressive house.',
  'source_row': 'release-management.csv:42',
};

class RenderedArtistReminderEmail {
  const RenderedArtistReminderEmail({
    required this.subject,
    required this.bodyHtml,
    required this.bodyText,
  });

  final String subject;
  final String bodyHtml;
  final String bodyText;
}

Map<String, String> buildArtistReminderTemplateValues(
    Map<String, dynamic>? artist) {
  final item = artist ?? const <String, dynamic>{};
  final extra = item['extra'] is Map<String, dynamic>
      ? item['extra'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final name =
      (extra['artist_brand'] ?? item['name'] ?? item['email'] ?? 'there')
          .toString()
          .trim();

  String readValue(String key) {
    if (key == 'name') return name;
    final direct = item[key];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }
    final extraValue = extra[key];
    if (extraValue != null && extraValue.toString().trim().isNotEmpty) {
      return extraValue.toString().trim();
    }
    return '';
  }

  return {
    for (final field in artistReminderTemplateFields)
      field.key: readValue(field.key),
  };
}

String applyArtistReminderTemplate(
    String template, Map<String, String> values) {
  var output = template;
  for (final entry in values.entries) {
    output = output.replaceAll(
      RegExp('\\{${RegExp.escape(entry.key)}\\}', caseSensitive: false),
      entry.value,
    );
  }
  return output;
}

bool _looksLikeHtml(String value) =>
    RegExp(r'<[a-zA-Z][\s\S]*>').hasMatch(value);

String _renderReminderHtml(String value, Map<String, String> values) {
  final rendered = applyArtistReminderTemplate(value, values);
  if (_looksLikeHtml(rendered)) return rendered;
  return const HtmlEscape(HtmlEscapeMode.element)
      .convert(rendered)
      .replaceAll('\n', '<br>');
}

String htmlToPlainReminderText(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

RenderedArtistReminderEmail renderArtistReminderEmail({
  required String subjectTemplate,
  required String bodyTemplate,
  required Map<String, String> values,
}) {
  final subject = applyArtistReminderTemplate(subjectTemplate, values).trim();
  final bodyHtml = _renderReminderHtml(bodyTemplate, values).trim();
  final bodyText = htmlToPlainReminderText(bodyHtml);
  return RenderedArtistReminderEmail(
    subject: subject,
    bodyHtml: bodyHtml,
    bodyText: bodyText,
  );
}

void insertArtistReminderTemplateToken(
    TextEditingController controller, String value) {
  final selection = controller.selection;
  if (!selection.isValid) {
    controller.text += value;
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    return;
  }
  final start = selection.start < 0 ? controller.text.length : selection.start;
  final end = selection.end < 0 ? controller.text.length : selection.end;
  final newText = controller.text.replaceRange(start, end, value);
  controller.value = controller.value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: start + value.length),
    composing: TextRange.empty,
  );
}

/// Subject/body editor with field chips and live preview for reminder emails.
class ArtistReminderTemplateEditor extends StatefulWidget {
  const ArtistReminderTemplateEditor({
    super.key,
    required this.subjectController,
    required this.bodyController,
    required this.previewValues,
    required this.helperText,
    this.footerText,
  });

  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final Map<String, String> previewValues;
  final String helperText;
  final String? footerText;

  @override
  State<ArtistReminderTemplateEditor> createState() =>
      _ArtistReminderTemplateEditorState();
}

class _ArtistReminderTemplateEditorState
    extends State<ArtistReminderTemplateEditor> {
  void _onControllerTextChanged() {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.subjectController.addListener(_onControllerTextChanged);
    widget.bodyController.addListener(_onControllerTextChanged);
  }

  @override
  void dispose() {
    widget.subjectController.removeListener(_onControllerTextChanged);
    widget.bodyController.removeListener(_onControllerTextChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewSubject = applyArtistReminderTemplate(
      widget.subjectController.text,
      widget.previewValues,
    ).trim();
    final previewBodyHtml = _renderReminderHtml(
      widget.bodyController.text,
      widget.previewValues,
    );
    final previewBodyPlain = htmlToPlainReminderText(previewBodyHtml);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(widget.helperText, style: theme.textTheme.bodySmall),
        if (widget.footerText != null) ...[
          const SizedBox(height: 8),
          Text(
            widget.footerText!,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: widget.subjectController,
          decoration: const InputDecoration(
            labelText: 'Subject',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Insert into subject',
            style: theme.textTheme.labelSmall,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final field in artistReminderTemplateFields)
              ActionChip(
                label: Text(field.label, style: const TextStyle(fontSize: 11)),
                tooltip: field.description,
                onPressed: () {
                  insertArtistReminderTemplateToken(
                    widget.subjectController,
                    field.token,
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.bodyController,
          decoration: const InputDecoration(
            labelText: 'Body',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          minLines: 10,
          maxLines: 16,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Insert into body',
            style: theme.textTheme.labelSmall,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final field in artistReminderTemplateFields)
              ActionChip(
                label: Text(field.label, style: const TextStyle(fontSize: 11)),
                tooltip: field.description,
                onPressed: () {
                  insertArtistReminderTemplateToken(
                    widget.bodyController,
                    field.token,
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Preview (sample artist)', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                previewSubject.isEmpty ? '(empty subject)' : previewSubject,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              SelectableText(
                previewBodyPlain.isEmpty ? '(empty body)' : previewBodyPlain,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
