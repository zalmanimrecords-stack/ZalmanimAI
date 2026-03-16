import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/redirect_to_hash_stub.dart'
    if (dart.library.html) 'core/redirect_to_hash_web.dart' as redirect;
import 'core/app_config.dart';
import 'core/consent_storage.dart';
import 'core/zalmanim_icons.dart';
import 'core/session_storage.dart';
import 'core/session.dart';
import 'features/auth/login_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/dashboard/artist_dashboard_page.dart';
import 'features/legal/cookie_consent_page.dart';
import 'features/public/landing_page.dart';
import 'features/public/linktree_page.dart';
import 'features/public/demo_confirm_form_page.dart';
import 'features/public/pending_release_form_page.dart';

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
  late Future<(AuthSession?, bool)> _initFuture;
  AuthSession? _activeSession;
  bool? _cookieConsentGiven;
  bool _showResetPassword = false;
  String? _resetToken;
  bool _showLogin = false;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: _apiBaseUrl);
    _initFuture = Future(() async {
      final session = await loadSession();
      final consent = await getCookieConsent();
      return (session, consent);
    });
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
    redirect.redirectPathToHash();
    final primary = _primaryColor();
    // Public forms: /pending-release?token=xxx, /demo-confirm?token=xxx, or hash URLs /#/pending-release?token=xxx, /#/demo-confirm?token=xxx
    String? segment;
    String? token;
    final pathSegments = Uri.base.pathSegments.where((s) => s.isNotEmpty).toList();
    final frag = Uri.base.fragment;
    if (pathSegments.isNotEmpty && Uri.base.queryParameters['token'] != null) {
      segment = pathSegments[0].toLowerCase();
      token = Uri.base.queryParameters['token'];
    } else if (frag.startsWith('/')) {
      try {
        final u = Uri.parse('http://h$frag');
        if (u.pathSegments.isNotEmpty) segment = u.pathSegments[0].toLowerCase();
        token = u.queryParameters['token'];
      } catch (_) {}
    }
    if (segment != null && token != null && token.trim().isNotEmpty) {
      if (segment == 'pending-release') {
        return MaterialApp(
          title: AppConfig.labelName,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: primary,
              primary: primary,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: PendingReleaseFormPage(
            apiClient: ApiClient(baseUrl: _apiBaseUrl),
            token: token.trim(),
          ),
        );
      }
      if (segment == 'demo-confirm') {
        return MaterialApp(
          title: AppConfig.labelName,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: primary,
              primary: primary,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          home: DemoConfirmFormPage(
            apiClient: ApiClient(baseUrl: _apiBaseUrl),
            token: token.trim(),
          ),
        );
      }
    }
    // Public linktree route: /l/{artistId} or hash URL /#/l/{artistId} (e.g. /l/68 or /#/l/68)
    List<String> segments = pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 2 && frag.startsWith('/')) {
      try {
        final u = Uri.parse('http://h$frag');
        segments = u.pathSegments.where((s) => s.isNotEmpty).toList();
      } catch (_) {}
    }
    if (segments.length >= 2 &&
        segments[0].toLowerCase() == 'l' &&
        int.tryParse(segments[1]) != null) {
      final artistId = int.parse(segments[1]);
      return MaterialApp(
        title: AppConfig.labelName,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primary,
            primary: primary,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: LinktreePage(
          apiClient: ApiClient(baseUrl: _apiBaseUrl),
          artistId: artistId,
        ),
      );
    }
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
      home: FutureBuilder<(AuthSession?, bool)>(
        future: _initFuture,
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
                    Image.asset(
                      'assets/images/zalmanim_logo.png',
                      height: 80,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 16),
                    CircularProgressIndicator(color: primary),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data;
          final consent = _cookieConsentGiven ?? data?.$2 ?? false;
          if (data != null && !consent) {
            return CookieConsentPage(
              onAccept: () => setState(() => _cookieConsentGiven = true),
            );
          }
          final session = _activeSession ?? data?.$1;
          if (session != null && session.role == 'artist') {
            return ArtistDashboardPage(
              apiClient: _apiClient,
              token: session.token,
              onLogout: () async {
                await clearSession();
                setState(() {
                  _activeSession = null;
                  _initFuture = Future(() async {
                    final s = await loadSession();
                    final c = await getCookieConsent();
                    return (s, c);
                  });
                });
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
                      Icon(ZalmanimIcons.block, size: 48, color: Colors.grey[600]),
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
                          setState(() {
                          _initFuture = Future(() async {
                            final s = await loadSession();
                            final c = await getCookieConsent();
                            return (s, c);
                          });
                        });
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
              onLoggedIn: (session) => setState(() {
                _activeSession = session;
                _initFuture = Future(() async {
                  final s = await loadSession();
                  final c = await getCookieConsent();
                  return (s, c);
                });
              }),
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
