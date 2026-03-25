/// Label-specific config for the artist portal.
/// Change these per deployment to match your label branding.
class AppConfig {
  AppConfig._();

  /// API base URL (same backend as admin). e.g. https://api.yourlabel.com/ or http://localhost:8000/
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://lmapi.zalmanim.com/',
  );

  /// Label / portal name shown in the UI (e.g. "Zalmanim Records", "My Label").
  static const String labelName = String.fromEnvironment(
    'LABEL_NAME',
    defaultValue: 'Zalmanim Artists',
  );

  /// Primary brand color (hex without #). e.g. "1B7A5E" for green.
  static const String primaryColorHex = String.fromEnvironment(
    'PRIMARY_COLOR',
    defaultValue: 'B66A2C',
  );

  /// Optional logo URL for the app bar. Empty = no logo.
  static const String logoUrl = String.fromEnvironment(
    'LOGO_URL',
    defaultValue: '',
  );

  /// Public artists portal URL used for share links and public form attribution.
  static const String publicBaseUrl = String.fromEnvironment(
    'PUBLIC_BASE_URL',
    defaultValue: 'https://artists.zalmanim.com/',
  );
}
