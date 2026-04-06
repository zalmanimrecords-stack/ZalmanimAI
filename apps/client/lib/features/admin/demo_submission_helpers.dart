import 'dart:convert';

/// JSON may decode `id` as int or num; list rows may use dynamic maps.
int? coerceDemoSubmissionId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

String demoFieldsJsonPreview(Map<String, dynamic> submission) {
  final raw = submission['fields'];
  if (raw is! Map) {
    return '{}';
  }
  try {
    final normalized = Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
    return const JsonEncoder.withIndent('  ').convert(normalized);
  } catch (_) {
    return raw.toString();
  }
}

/// Formats a demo submission date (ISO string or null) for display. Returns null if missing/invalid.
String? formatDemoSubmissionDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  try {
    final dt = DateTime.parse(s);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return s;
  }
}

/// Collects SoundCloud URLs from demo submission links, fields, and message text.
List<String> soundCloudUrlsFromDemoSubmission(Map<String, dynamic> submission) {
  final urls = <String>{};
  bool isSoundCloudUrl(String s) {
    final lower = s.toLowerCase().trim();
    return (lower.contains('soundcloud.com') ||
            lower.contains('on.soundcloud.com') ||
            lower.contains('soundcloud.app.goo.gl')) &&
        (lower.startsWith('http://') || lower.startsWith('https://'));
  }

  void addIfSoundCloud(String s) {
    final t = s.trim();
    if (t.isEmpty) return;
    if (isSoundCloudUrl(t)) urls.add(t);
  }

  for (final link in (submission['links'] as List<dynamic>? ?? const [])) {
    addIfSoundCloud(link.toString());
  }
  final fields = submission['fields'];
  if (fields is Map<String, dynamic>) {
    for (final entry in fields.entries) {
      final val = entry.value;
      if (val is! String) continue;
      addIfSoundCloud(val);
    }
  }
  final message = (submission['message'] ?? '').toString();
  if (message.isNotEmpty) {
    final uriPattern = RegExp(
      r'https?://[^\s<>"{}|\\^`\[\]]+',
      caseSensitive: false,
    );
    for (final match in uriPattern.allMatches(message)) {
      addIfSoundCloud(match.group(0)!);
    }
  }
  return urls.toList();
}
