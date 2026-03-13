import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/zalmanim_icons.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, required this.apiClient, this.initialEmail, required this.onBack});

  final ApiClient apiClient;
  final String? initialEmail;
  final VoidCallback onBack;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final emailController = TextEditingController();
  bool loading = false;
  bool sent = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) emailController.text = widget.initialEmail!;
  }

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      setState(() => error = 'Please enter your email');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await widget.apiClient.requestPasswordReset(email: email);
      if (mounted) setState(() { sent = true; loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString().replaceFirst('Exception: ', '');
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot password'),
        leading: IconButton(
          icon: const Icon(ZalmanimIcons.arrowBack),
          onPressed: widget.onBack,
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            margin: const EdgeInsets.all(20),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: sent
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(ZalmanimIcons.markEmailRead, size: 48, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 16),
                        const Text(
                          'Check your email',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          'If an account exists with ${emailController.text}, you will receive a reset link shortly. The link expires in 1 hour.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: widget.onBack,
                          child: const Text('Back to login'),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Enter your email and we’ll send you a link to reset your password.',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: emailController,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SelectableText(error!, style: const TextStyle(color: Colors.red)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy, size: 20),
                                tooltip: 'Copy error',
                                onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: loading ? null : _submit,
                          child: loading
                              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Send reset link'),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: widget.onBack,
                          child: const Text('Back to login'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
