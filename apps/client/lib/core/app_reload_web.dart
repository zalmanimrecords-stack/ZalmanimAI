// Web: force full reload from server (bypass cache).

import 'dart:html' as html;

/// Reloads the app from the server (full page reload, bypass cache).
void reloadApp() {
  html.window.location.reload();
}
