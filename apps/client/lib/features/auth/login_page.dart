import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/zalmanim_icons.dart';
import '../../widgets/api_connection_indicator.dart';
import '../legal/privacy_policy_page.dart';
import '../legal/terms_of_use_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.apiClient,
    required this.onLoginSuccess,
    this.initialError,
  });

  final ApiClient apiClient;
  final Future<void> Function(AuthSession session, {required bool rememberMe})
      onLoginSuccess;
  final String? initialError;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool rememberMe = false;
  bool loading = false;
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
        title: Image.asset(
          'assets/images/zalmanim_logo.png',
          height: 32,
          fit: BoxFit.contain,
        ),
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
                  Image.asset(
                    'assets/images/zalmanim_logo.png',
                    height: 64,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ZalmanimIcons.alienIcon(size: 28, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      ZalmanimIcons.jellyfishIcon(size: 28, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 12),
                      ZalmanimIcons.squidIcon(size: 28, color: Theme.of(context).colorScheme.primary),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Login', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: loading
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ForgotPasswordPage(
                                    apiClient: widget.apiClient,
                                    initialEmail: emailController.text.trim().isNotEmpty ? emailController.text.trim() : null,
                                    onBack: () => Navigator.of(context).pop(),
                                  ),
                                ),
                              ),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CheckboxListTile(
                      value: rememberMe,
                      onChanged: (v) => setState(() => rememberMe = v ?? false),
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
                          icon: const Icon(ZalmanimIcons.copy, size: 20),
                          tooltip: 'Copy error',
                          onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                        ),
                      ],
                    ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: loading ? null : _login,
                      child: loading
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Use your system user credentials.'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const TermsOfUsePage(appName: 'LabelOps'),
                          ),
                        ),
                        child: const Text('Terms of Use'),
                      ),
                      Text(' · ', style: Theme.of(context).textTheme.bodySmall),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PrivacyPolicyPage(appName: 'LabelOps'),
                          ),
                        ),
                        child: const Text('Privacy Policy'),
                      ),
                    ],
                  ),
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

  Future<void> _completeLogin(AuthSession session) async {
    if (!mounted) return;
    await widget.onLoginSuccess(session, rememberMe: rememberMe);
  }
}
