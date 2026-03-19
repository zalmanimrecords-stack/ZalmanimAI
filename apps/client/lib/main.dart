import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/consent_storage.dart';
import 'core/session.dart';
import 'core/session_storage.dart';
import 'features/admin/admin_dashboard_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/legal/cookie_consent_page.dart';
import 'widgets/app_version_badge.dart';
import 'widgets/ambient_underwater_shell.dart';

/// Message shown when an artist token is used in the LM app (artists use the artist portal only).
const String kLmArtistForbiddenMessage =
    'Artists cannot access the LM system. Use the artist portal.';

void main() {
  runApp(const LabelOpsApp());
}

String get _apiBaseUrl {
  const env = String.fromEnvironment('API_BASE_URL', defaultValue: '');
  final base = env.isNotEmpty ? env : apiBaseUrl;
  if (base.endsWith('/')) return '${base}api';
  if (!base.endsWith('api')) return '$base/api';
  return base;
}

class LabelOpsApp extends StatefulWidget {
  const LabelOpsApp({super.key});

  @override
  State<LabelOpsApp> createState() => _LabelOpsAppState();
}

class _LabelOpsAppState extends State<LabelOpsApp> {
  late final ApiClient _apiClient;
  AuthSession? _session;
  bool _initializing = true;
  bool _cookieConsentGiven = false;
  String? _authError;
  bool _showResetPassword = false;
  String? _resetToken;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: _apiBaseUrl);
    final resetToken = Uri.base.queryParameters['reset_token'];
    if (resetToken != null && resetToken.isNotEmpty) {
      _showResetPassword = true;
      _resetToken = resetToken;
    }
    _initializeSession();
  }

  Future<void> _initializeSession() async {
    final session = await _resolveInitialSession();
    final consent = await getCookieConsent();
    if (!mounted) return;
    setState(() {
      _session = session;
      _cookieConsentGiven = consent;
      _initializing = false;
    });
  }

  Future<AuthSession?> _resolveInitialSession() async {
    final params = Uri.base.queryParameters;
    final token = params['token'];
    final role = params['role'];
    final socialError = params['social_error'];
    final provider = params['provider'];
    final email = params['email'];
    final fullName = params['full_name'];
    if (socialError != null && socialError.isNotEmpty) {
      final providerLabel = (provider == null || provider.isEmpty)
          ? 'Social'
          : '${provider[0].toUpperCase()}${provider.substring(1)}';
      _authError = '$providerLabel sign-in failed: $socialError';
    }
    if (token != null && token.isNotEmpty && role != null && role.isNotEmpty) {
      final session = AuthSession(
        token: token,
        role: role,
        email: email,
        fullName: fullName,
      );
      await saveSession(session, rememberMe: false);
      return session;
    }
    return loadSession();
  }

  Future<void> _handleLoginSuccess(
    AuthSession session, {
    required bool rememberMe,
  }) async {
    await saveSession(session, rememberMe: rememberMe);
    if (!mounted) return;
    setState(() {
      _session = session;
      _authError = null;
      _showResetPassword = false;
      _resetToken = null;
    });
  }

  Future<void> _handleLogout() async {
    await clearSession();
    if (!mounted) return;
    setState(() {
      _session = null;
      _authError = null;
      _showResetPassword = false;
      _resetToken = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1B7A5E),
      brightness: Brightness.light,
    ).copyWith(
      primary: const Color(0xFF156B5C),
      secondary: const Color(0xFFDA8A6C),
      tertiary: const Color(0xFFE47BAA),
      surface: const Color(0xFFFCFEFD),
      surfaceContainerHighest: const Color(0xFFE7F3F0),
    );

    return MaterialApp(
      title: 'LabelOps',
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4FBFB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7FCFC),
          foregroundColor: Color(0xFF133A38),
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        dividerColor: const Color(0x22156B5C),
        cardTheme: CardThemeData(
          color: const Color(0xFDFDFEFE),
          elevation: 2,
          shadowColor: const Color(0x18156B5C),
          surfaceTintColor: const Color(0x33156B5C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0x14156B5C)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.84),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0x22156B5C)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0x22156B5C)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xAA156B5C), width: 1.4),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colorScheme.primary,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      builder: (context, child) => AmbientUnderwaterShell(
        child: child ?? const SizedBox.shrink(),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_showResetPassword && _resetToken != null) {
      return ResetPasswordPage(
        apiClient: _apiClient,
        resetToken: _resetToken!,
        onSuccess: () => setState(() {
          _showResetPassword = false;
          _resetToken = null;
        }),
      );
    }
    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_cookieConsentGiven) {
      return CookieConsentPage(
        appName: 'LabelOps',
        onAccept: () => setState(() => _cookieConsentGiven = true),
      );
    }
    final session = _session;
    if (session != null) {
      if (session.role == 'admin' || session.role == 'manager') {
        return AdminDashboardPage(
          apiClient: _apiClient,
          session: session,
          onLogout: _handleLogout,
        );
      }
      // Artists must use the artist portal; do not allow them into the LM app.
      return _ArtistForbiddenPage(onLogout: _handleLogout);
    }
    return LoginPage(
      apiClient: _apiClient,
      initialError: _authError,
      onLoginSuccess: _handleLoginSuccess,
    );
  }
}

/// Shown when the user has an artist token in the LM app. Artists must use the artist portal only.
class _ArtistForbiddenPage extends StatelessWidget {
  const _ArtistForbiddenPage({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LabelOps'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: AppVersionBadge(
                tooltipPrefix: 'LM app version',
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 64, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                'Access not allowed',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              SelectableText(
                kLmArtistForbiddenMessage,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: kLmArtistForbiddenMessage),
                    ),
                    tooltip: 'Copy message',
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout),
                    label: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
