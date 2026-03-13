import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

const _keyToken = 'auth_token';
const _keyRole = 'auth_role';
const _keyEmail = 'auth_email';
const _keyFullName = 'auth_full_name';
const _keyRememberMe = 'auth_remember_me';
const _keyArtistReminderSubject = 'artist_reminder_email_subject';
const _keyArtistReminderBody = 'artist_reminder_email_body';

Future<void> saveSession(AuthSession session, {required bool rememberMe}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyRememberMe, rememberMe);
  if (!rememberMe) {
    await clearSession(clearRememberPreference: false);
    return;
  }
  await prefs.setString(_keyToken, session.token);
  await prefs.setString(_keyRole, session.role);
  if (session.email != null && session.email!.isNotEmpty) {
    await prefs.setString(_keyEmail, session.email!);
  } else {
    await prefs.remove(_keyEmail);
  }
  if (session.fullName != null && session.fullName!.isNotEmpty) {
    await prefs.setString(_keyFullName, session.fullName!);
  } else {
    await prefs.remove(_keyFullName);
  }
}

Future<void> clearSession({bool clearRememberPreference = true}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_keyToken);
  await prefs.remove(_keyRole);
  await prefs.remove(_keyEmail);
  await prefs.remove(_keyFullName);
  if (clearRememberPreference) {
    await prefs.remove(_keyRememberMe);
  }
}

Future<AuthSession?> loadSession() async {
  final prefs = await SharedPreferences.getInstance();
  final rememberMe = prefs.getBool(_keyRememberMe) ?? false;
  if (!rememberMe) {
    await clearSession(clearRememberPreference: false);
    return null;
  }
  final token = prefs.getString(_keyToken);
  final role = prefs.getString(_keyRole);
  if (token == null || token.isEmpty || role == null || role.isEmpty) {
    return null;
  }
  return AuthSession(
    token: token,
    role: role,
    email: prefs.getString(_keyEmail),
    fullName: prefs.getString(_keyFullName),
  );
}

Future<String?> getArtistReminderEmailSubject() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_keyArtistReminderSubject);
}

Future<String?> getArtistReminderEmailBody() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_keyArtistReminderBody);
}

Future<void> setArtistReminderEmailTemplate({String? subject, String? body}) async {
  final prefs = await SharedPreferences.getInstance();
  if (subject != null) await prefs.setString(_keyArtistReminderSubject, subject);
  if (body != null) await prefs.setString(_keyArtistReminderBody, body);
}

/// Clears all app cache (session, cookie consent, reminder templates, etc.).
/// After this, call [reloadApp] on web to reload the page from the server.
Future<void> clearAllAppCache() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

