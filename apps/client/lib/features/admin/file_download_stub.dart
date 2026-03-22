// Stub for non-web: download not supported (admin app is web-only in practice).

void triggerBrowserDownload(
  List<int> bytes,
  String filename, {
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('Download is only supported on web.');
}
