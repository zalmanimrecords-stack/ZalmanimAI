// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// On web: if URL is path-based /l/68, redirect to /#/l/68 so the app loads (SPA).
void redirectPathToHash() {
  final path = html.window.location.pathname ?? '';
  if (path.startsWith('/l/')) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length >= 2 && int.tryParse(segments[1]) != null) {
      final origin = html.window.location.origin;
      html.window.location.replace('$origin/#/l/${segments[1]}');
    }
  }
}
