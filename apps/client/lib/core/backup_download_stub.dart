// Stub for non-web: download not supported (e.g. mobile could use share or save to app dir).

void downloadBackupFile(List<int> bytes, String filename) {
  throw UnsupportedError('Backup download is only supported on web. Use the API directly on other platforms.');
}
