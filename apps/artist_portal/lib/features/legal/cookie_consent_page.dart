import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../core/consent_storage.dart';
import 'privacy_policy_page.dart';
import 'terms_of_use_page.dart';

/// GDPR-style cookie and terms consent. User must accept to continue.
class CookieConsentPage extends StatelessWidget {
  const CookieConsentPage({
    super.key,
    required this.onAccept,
  });

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final appName = AppConfig.labelName;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cookie & consent'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                'We use cookies and similar technologies',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Text(
                    'To use $appName we need your consent:\n\n'
                    '• Essential cookies: Required for login, session and security. '
                    'These are necessary for the service to work.\n\n'
                    '• Preferences: We may store your choices (e.g. "Remember me") in your browser or device.\n\n'
                    'We do not use advertising or third-party tracking cookies without your consent. '
                    'By clicking "Accept all" you agree to our use of cookies and to our Terms of Use and Privacy Policy. '
                    'You can choose "Essential only" to limit storage to what is strictly necessary.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const TermsOfUsePage(),
                        ),
                      );
                    },
                    child: const Text('Terms of Use'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PrivacyPolicyPage(),
                        ),
                      );
                    },
                    child: const Text('Privacy Policy'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _accept(context, acceptAll: true),
                child: const Text('Accept all'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _accept(context, acceptAll: false),
                child: const Text('Essential only'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context, {required bool acceptAll}) async {
    if (acceptAll) {
      await setCookieConsentAccepted();
    } else {
      await setEssentialOnlyConsent();
    }
    if (context.mounted) {
      onAccept();
    }
  }
}
