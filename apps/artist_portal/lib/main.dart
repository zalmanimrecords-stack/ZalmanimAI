import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/session_storage.dart';
import 'core/session.dart';
import 'features/auth/login_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/dashboard/artist_dashboard_page.dart';
import 'features/public/landing_page.dart';

void main() {
  runApp(const ArtistPortalApp());
}

String get _apiBaseUrl {
  final base = AppConfig.apiBaseUrl;
  if (base.endsWith('/')) return '${base}api';
  if (!base.endsWith('api')) return '$base/api';
  return base;
}

Color _primaryColor() {
  final hex = AppConfig.primaryColorHex.replaceFirst('#', '').trim();
  if (hex.length >= 6) {
    return Color(int.parse('FF${hex.padRight(6, '0').substring(0, 6)}', radix: 16));
  }
  return const Color(0xFF1B7A5E);
}

class ArtistPortalApp extends StatefulWidget {
  const ArtistPortalApp({super.key});

  @override
  State<ArtistPortalApp> createState() => _ArtistPortalAppState();
}

class _ArtistPortalAppState extends State<ArtistPortalApp> {
  late final ApiClient _apiClient;
  late Future<AuthSession?> _sessionFuture;
  bool _showResetPassword = false;
  String? _resetToken;
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: _apiBaseUrl);
    _sessionFuture = loadSession();
    final resetToken = Uri.base.queryParameters['reset_token'];
    if (resetToken != null && resetToken.isNotEmpty) {
      _showResetPassword = true;
      _resetToken = resetToken;
    }
    if (Uri.base.queryParameters['view'] == 'signin') {
      _showLogin = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = _primaryColor();
    return MaterialApp(
      title: AppConfig.labelName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: AppBarTheme(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: FutureBuilder<AuthSession?>(
        future: _sessionFuture,
        builder: (context, snapshot) {
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
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: primary),
                    const SizedBox(height: 16),
                    Text(
                      AppConfig.labelName,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          final session = snapshot.data;
          if (session != null && session.role == 'artist') {
            return ArtistDashboardPage(
              apiClient: _apiClient,
              token: session.token,
              onLogout: () async {
                await clearSession();
                setState(() => _sessionFuture = loadSession());
              },
            );
          }
          if (session != null && session.role != 'artist') {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, size: 48, color: Colors.grey[600]),
                      const SizedBox(height: 16),
                      Text(
                        'This portal is for artists only.',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please use the management app to sign in as admin or manager.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: () async {
                          await clearSession();
                          setState(() => _sessionFuture = loadSession());
                        },
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (_showLogin) {
            return LoginPage(
              apiClient: _apiClient,
              onSessionSaved: () => setState(() => _sessionFuture = loadSession()),
              onBack: () => setState(() => _showLogin = false),
            );
          }
          return LandingPage(
            apiClient: _apiClient,
            onSignIn: () => setState(() => _showLogin = true),
          );
        },
      ),
    );
  }
}
