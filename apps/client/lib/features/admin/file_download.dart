// Conditional export: web triggers download; other platforms throw.

export 'file_download_web.dart' if (dart.library.io) 'file_download_stub.dart';
