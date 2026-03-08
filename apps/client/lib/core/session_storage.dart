import 'package:shared_preferences/shared_preferences.dart';

import 'session.dart';

const _keyToken = 'auth_token';
const _keyRole = 'auth_role';
const _keyArtistReminderSubject = 'artist_reminder_email_subject';
const _keyArtistReminderBody = 'artist_reminder_email_body';

/// Persists and restores auth session when "Remember me" is used.
Future<void> saveSession(AuthSession session) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_keyToken, session.token);
  await prefs.setString(_keyRole, session.role);
}

Future<void> clearSession() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_keyToken);
  await prefs.remove(_keyRole);
}

Future<AuthSession?> loadSession() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(_keyToken);
  final role = prefs.getString(_keyRole);
  if (token == null || token.isEmpty || role == null || role.isEmpty) {
    return null;
  }
  return AuthSession(token: token, role: role);
}

/// Artist reminder email template (used by Reports > Artist reminders).
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
