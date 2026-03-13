import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';

/// Terms of Use page. Content uses [AppConfig.labelName].
class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final appName = AppConfig.labelName;
    final fullText = _buildFullText(appName);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Use'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy full text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Terms of Use copied to clipboard')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SelectableText(
            fullText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _buildFullText(String appName) => '''
$appName – Terms of Use

Last updated: March 2025

1. Acceptance of Terms
By accessing or using $appName ("Service"), you agree to be bound by these Terms of Use. If you do not agree, do not use the Service.

2. Description of Service
$appName provides an artist portal and label services. We reserve the right to modify, suspend or discontinue the Service at any time.

3. Account and Security
You are responsible for keeping your credentials secure and for all activity under your account. You must notify us promptly of any unauthorized use.

4. Acceptable Use
You agree not to use the Service for any unlawful purpose or in any way that could damage, disable or impair the Service or other users' access. You must comply with all applicable laws and regulations.

5. Intellectual Property
The Service and its content (excluding user content) are owned by us or our licensors. You may not copy, modify or distribute our materials without permission.

6. Privacy
Your use of the Service is also governed by our Privacy Policy. By using the Service you consent to the collection and use of information as described there.

7. Limitation of Liability
To the maximum extent permitted by law, we shall not be liable for any indirect, incidental, special or consequential damages arising from your use of the Service.

8. Changes
We may update these Terms from time to time. Continued use of the Service after changes constitutes acceptance of the revised Terms.

9. Contact
For questions about these Terms, please contact the administrator of your $appName instance.
''';
}
