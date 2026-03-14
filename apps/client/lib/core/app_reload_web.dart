// Web: force full reload from server (bypass cache).

import 'package:web/web.dart' as web;

/// Reloads the app from the server (full page reload, bypass cache).
void reloadApp() {
  web.window.location.reload();
}
