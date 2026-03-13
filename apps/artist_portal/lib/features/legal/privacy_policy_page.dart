import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_config.dart';

/// Privacy Policy page including cookie disclosure (GDPR-oriented).
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appName = AppConfig.labelName;
    final fullText = _buildFullText(appName);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy full text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: fullText));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Privacy Policy copied to clipboard')),
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
$appName – Privacy Policy

Last updated: March 2025

1. Introduction
This Privacy Policy explains how we collect, use and protect your personal data when you use $appName ("Service"), in line with applicable data protection laws including the GDPR where applicable.

2. Data Controller
The data controller is the operator of your $appName instance (your label or organization). Contact your administrator for identity and contact details.

3. Personal Data We Collect
• Account data: email, name, and authentication-related data you provide when signing in (including via social login).
• Usage data: how you use the Service (e.g. actions within the app, session information) to provide and improve the Service.
• Technical data: device/browser information, IP address, and similar data necessary for security and operation.

4. Legal Basis (GDPR)
We process your data on the basis of: Contract (to provide the Service); Legitimate interests (to operate, secure and improve the Service); and Consent where we ask for your explicit consent (e.g. non-essential cookies or marketing).

5. Cookies and Local Storage
We use cookies and local storage for: Essential purposes (session and authentication, "Remember me", security); and Preferences (e.g. settings). We do not use non-essential advertising or tracking cookies without your consent. You can accept all cookies or only essential cookies when prompted.

6. How We Use Your Data
We use your data to provide and maintain the Service, authenticate you, communicate with you, ensure security, and comply with legal obligations.

7. Data Sharing
We do not sell your personal data. We may share data with service providers (under strict confidentiality) and authorities when required by law.

8. Data Retention
We retain your data for as long as your account is active or as needed to provide the Service, and for a reasonable period thereafter. You may request deletion from your administrator.

9. Your Rights (GDPR)
Where the GDPR applies, you have the right to access, rectify, erase, restrict or object to processing, data portability, and to withdraw consent. You may lodge a complaint with a supervisory authority. Contact your $appName administrator to exercise these rights.

10. Security
We implement appropriate measures to protect your personal data against unauthorized access, loss or alteration.

11. Changes
We may update this Privacy Policy from time to time. Continued use after changes constitutes acceptance of the updated policy.

12. Contact
For privacy-related questions or to exercise your rights, please contact the administrator of your $appName instance.
''';
}
