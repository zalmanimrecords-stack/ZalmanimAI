import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

/// Consumes a one-time login token from the email link (`?login_token=...`),
/// signs the user in, and hands the session back. On failure it routes to login.
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
  final Future<void> Function(AuthSession session) onLoggedIn;
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
      await widget.onLoggedIn(session);
    } catch (e) {
      widget.onFailed(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Signing you in…'),
          ],
        ),
      ),
    );
  }
}
