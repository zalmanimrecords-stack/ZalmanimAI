// Web: trigger browser download of a file (e.g. demo MP3).
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Triggers a file download in the browser. Safe to call only on web.
void triggerBrowserDownload(List<int> bytes, String filename) {
  final blob = html.Blob([bytes], 'audio/mpeg');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
