import 'package:shared_preferences/shared_preferences.dart';

const _keyCookieConsent = 'gdpr_cookie_consent';
const _keyCookieConsentTimestamp = 'gdpr_cookie_consent_timestamp';
const _keyTermsAcceptedTimestamp = 'gdpr_terms_accepted_timestamp';

Future<bool> getCookieConsent() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_keyCookieConsent) ?? false;
}

Future<DateTime?> getCookieConsentTimestamp() async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt(_keyCookieConsentTimestamp);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> setCookieConsentAccepted() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyCookieConsent, true);
  await prefs.setInt(_keyCookieConsentTimestamp, DateTime.now().millisecondsSinceEpoch);
}

Future<void> setEssentialOnlyConsent() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyCookieConsent, true);
  await prefs.setInt(_keyCookieConsentTimestamp, DateTime.now().millisecondsSinceEpoch);
}

Future<DateTime?> getTermsAcceptedTimestamp() async {
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt(_keyTermsAcceptedTimestamp);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> setTermsAcceptedTimestamp() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_keyTermsAcceptedTimestamp, DateTime.now().millisecondsSinceEpoch);
}
