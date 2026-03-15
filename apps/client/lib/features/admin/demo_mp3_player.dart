// Conditional export: web uses HTML Audio (no just_audio); other platforms use just_audio.
// This ensures the Flutter web build never compiles just_audio, avoiding dart2js issues.

// Web build: use web impl (no just_audio). VM/io: use just_audio impl.
export 'demo_mp3_player_web.dart' if (dart.library.io) 'demo_mp3_player_io.dart';
