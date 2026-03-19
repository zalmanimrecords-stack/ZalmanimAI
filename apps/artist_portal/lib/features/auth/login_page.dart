import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/session.dart';
import '../../core/session_storage.dart';
import '../../core/zalmanim_icons.dart';
import '../../widgets/app_version_badge.dart';
import '../legal/privacy_policy_page.dart';
import '../legal/terms_of_use_page.dart';
import 'forgot_password_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.apiClient,
    required this.onLoggedIn,
    this.onBack,
  });

  final ApiClient apiClient;
  final ValueChanged<AuthSession> onLoggedIn;
  final VoidCallback? onBack;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool rememberMe = true;
  bool loading = false;
  bool obscurePassword = true;
  String? error;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => error = 'Please enter email and password');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final session =
          await widget.apiClient.login(email: email, password: password);
      if (session.role != 'artist') {
        setState(() {
          error =
              'This portal is for artists only. Use the management app for admin access.';
          loading = false;
        });
        return;
      }
      await saveSession(session, rememberMe: rememberMe);
      widget.onLoggedIn(session);
    } catch (e) {
      setState(() {
        error = e.toString().replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                primary.withValues(alpha: 0.12),
                primary.withValues(alpha: 0.04),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(compact ? 16 : 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Expanded(
                              child: widget.onBack == null
                                  ? const SizedBox(height: 24)
                                  : Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: widget.onBack,
                                        icon:
                                            const Icon(ZalmanimIcons.arrowBack),
                                        label: const Text('Back'),
                                      ),
                                    ),
                            ),
                            AppVersionBadge(
                              tooltipPrefix: 'Artist portal version',
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Image.asset(
                        'assets/images/zalmanim_logo.png',
                        height: compact ? 64 : 72,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ZalmanimIcons.alienIcon(size: 28, color: primary),
                          const SizedBox(width: 12),
                          ZalmanimIcons.jellyfishIcon(size: 28, color: primary),
                          const SizedBox(width: 12),
                          ZalmanimIcons.squidIcon(size: 28, color: primary),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppConfig.labelName,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Artist sign in',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                      SizedBox(height: compact ? 24 : 40),
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(compact ? 18 : 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: emailController,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(ZalmanimIcons.email),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: passwordController,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  border: const OutlineInputBorder(),
                                  prefixIcon: const Icon(ZalmanimIcons.lock),
                                  suffixIcon: IconButton(
                                    onPressed: () => setState(
                                      () =>
                                          obscurePassword = !obscurePassword,
                                    ),
                                    icon: Icon(
                                      obscurePassword
                                          ? ZalmanimIcons.visibility
                                          : ZalmanimIcons.visibilityOff,
                                    ),
                                  ),
                                ),
                                obscureText: obscurePassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _login(),
                              ),
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                value: rememberMe,
                                onChanged: loading
                                    ? null
                                    : (value) => setState(
                                          () => rememberMe = value ?? false,
                                        ),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text('Remember me'),
                                dense: true,
                              ),
                              if (error != null) ...[
                                const SizedBox(height: 16),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      ZalmanimIcons.errorOutline,
                                      size: 20,
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: SelectableText(
                                        error!,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        ZalmanimIcons.copy,
                                        size: 20,
                                      ),
                                      tooltip: 'Copy error',
                                      onPressed: () => Clipboard.setData(
                                        ClipboardData(text: error!),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: loading
                                      ? null
                                      : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ForgotPasswordPage(
                                                apiClient: widget.apiClient,
                                                initialEmail: emailController
                                                        .text
                                                        .trim()
                                                        .isNotEmpty
                                                    ? emailController.text.trim()
                                                    : null,
                                                onBack: () =>
                                                    Navigator.of(context).pop(),
                                              ),
                                            ),
                                          ),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: loading ? null : _login,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: loading
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('Sign in'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const TermsOfUsePage(),
                              ),
                            ),
                            child: const Text('Terms of Use'),
                          ),
                          Text(
                            '·',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PrivacyPolicyPage(),
                              ),
                            ),
                            child: const Text('Privacy Policy'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
