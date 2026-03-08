import 'package:flutter/material.dart';

import 'core/api_client.dart';
import 'core/app_config.dart';
import 'core/session.dart';
import 'core/session_storage.dart';
import 'features/admin/admin_dashboard_page.dart';
import 'features/artist/artist_dashboard_page.dart';
import 'features/auth/login_page.dart';

void main() {
  runApp(const LabelOpsApp());
}

/// API base URL for requests: app_config (or dart-define) + "api" if needed.
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

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient(baseUrl: _apiBaseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LabelOps',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7A5E)),
        useMaterial3: true,
      ),
      home: FutureBuilder<AuthSession?>(
        future: loadSession(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          final session = snapshot.data;
          if (session != null) {
            if (session.role == 'admin') {
              return AdminDashboardPage(apiClient: _apiClient, token: session.token);
            }
            return ArtistDashboardPage(apiClient: _apiClient, token: session.token);
          }
          return LoginPage(apiClient: _apiClient);
        },
      ),
    );
  }
}
