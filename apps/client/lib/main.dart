import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/session.dart';
import 'core/session_storage.dart';
import 'features/admin/admin_dashboard_page.dart';
import 'features/artist/artist_dashboard_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/reset_password_page.dart';

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
    if (!mounted) return;
    setState(() {
      _session = session;
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
    return MaterialApp(
      title: 'LabelOps',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7A5E)),
        useMaterial3: true,
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
    final session = _session;
    if (session != null) {
      if (session.role == 'admin' || session.role == 'manager') {
        return AdminDashboardPage(
          apiClient: _apiClient,
          session: session,
          onLogout: _handleLogout,
        );
      }
      return ArtistDashboardPage(
        apiClient: _apiClient,
        session: session,
        onLogout: _handleLogout,
      );
    }
    return LoginPage(
      apiClient: _apiClient,
      initialError: _authError,
      onLoginSuccess: _handleLoginSuccess,
    );
  }
}
