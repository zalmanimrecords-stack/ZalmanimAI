import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/session_storage.dart';

/// Consumes a one-time login token from the email link (`?login_token=...`),
/// signs the artist in, and saves the session. On failure it routes back to login.
class MagicLoginPage extends StatefulWidget {
  const MagicLoginPage({
    super.key,
    required this.apiClient,
    required this.token,
    required this.onLoggedIn,
    required this.onFailed,
  });

  final ApiClient apiClient;
  final String token;
  final ValueChanged<AuthSession> onLoggedIn;
  final ValueChanged<String> onFailed;

  @override
  State<MagicLoginPage> createState() => _MagicLoginPageState();
}

class _MagicLoginPageState extends State<MagicLoginPage> {
  @override
  void initState() {
    super.initState();
    _consume();
  }

  Future<void> _consume() async {
    try {
      final session = await widget.apiClient.magicLogin(widget.token);
      if (session.role != 'artist') {
        widget.onFailed(
            'This portal is for artists only. Use the management app for admin access.');
        return;
      }
      await saveSession(session, rememberMe: true);
      widget.onLoggedIn(session);
    } catch (e) {
      widget.onFailed(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primary),
            const SizedBox(height: 16),
            const Text('Signing you in…'),
          ],
        ),
      ),
    );
  }
}
