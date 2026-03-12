import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/session_storage.dart';
import '../../widgets/api_connection_indicator.dart';
import '../admin/admin_dashboard_page.dart';
import '../artist/artist_dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.apiClient, this.initialError});

  final ApiClient apiClient;
  final String? initialError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController(text: 'admin@label.local');
  final passwordController = TextEditingController(text: 'admin123');
  bool rememberMe = true;
  bool loading = false;
  bool googleLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    error = widget.initialError;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LabelOps'),
        actions: [ApiConnectionIndicator(apiClient: widget.apiClient)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('LabelOps Login', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CheckboxListTile(
                      value: rememberMe,
                      onChanged: (v) => setState(() => rememberMe = v ?? true),
                      title: const Text('Remember me'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (error != null)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: 'Copy error',
                          onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                        ),
                      ],
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading || googleLoading ? null : _login,
                      child: loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: loading || googleLoading ? null : _loginWithGoogle,
                      icon: googleLoading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.login),
                      label: const Text('Continue with Google'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Seed users: admin@label.local/admin123 or artist@label.local/artist123'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final AuthSession session = await widget.apiClient.login(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      await _completeLogin(session);
    } catch (e) {
      final msg = e.toString();
      final isConnection = msg.contains('Failed to fetch') || msg.contains('Connection refused') || msg.contains('SocketException');
      setState(() => error = isConnection
          ? 'Cannot reach API at ${widget.apiClient.baseUrl}. Backend running? Stop the app and run again (full restart). Or run: docker compose up -d'
          : msg);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() {
      googleLoading = true;
      error = null;
    });
    try {
      final authUrl = await widget.apiClient.startGoogleLogin(redirectUri: Uri.base.replace(queryParameters: const {}, fragment: '').toString());
      final launched = await launchUrl(Uri.parse(authUrl), webOnlyWindowName: '_self');
      if (!launched && mounted) {
        setState(() => error = 'Could not open Google sign-in.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted) setState(() => googleLoading = false);
    }
  }

  Future<void> _completeLogin(AuthSession session) async {
    if (!mounted) return;
    if (rememberMe) {
      await saveSession(session);
    } else {
      await clearSession();
    }
    if (!mounted) return;
    if (session.role == 'admin') {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => AdminDashboardPage(apiClient: widget.apiClient, token: session.token),
      ));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ArtistDashboardPage(apiClient: widget.apiClient, token: session.token),
      ));
    }
  }
}

