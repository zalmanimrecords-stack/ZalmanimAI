import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Privacy Policy page including cookie disclosure (GDPR-oriented).
/// Content can be customized per deployment.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({
    super.key,
    this.appName = 'LabelOps',
  });

  final String appName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy full text',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _fullText));
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
            _fullText,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String get _fullText => '''
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
We process your data on the basis of:
• Contract: to provide the Service and perform our agreement with you.
• Legitimate interests: to operate, secure and improve the Service.
• Consent: where we ask for your explicit consent (e.g. non-essential cookies or marketing).

5. Cookies and Local Storage
We use cookies and local storage for:
• Essential purposes: session and authentication ("Remember me"), security, and basic operation of the Service. These are necessary and do not require consent.
• Preferences: to remember your settings (e.g. language, theme) where offered. These may be stored after you accept cookies.
We do not use non-essential advertising or tracking cookies without your consent. You can accept all cookies, or only essential cookies, when prompted. You can change your choice later via your browser or app settings where available.

6. How We Use Your Data
We use your data to: provide and maintain the Service; authenticate you; communicate with you about the Service; ensure security and prevent abuse; and comply with legal obligations.

7. Data Sharing
We do not sell your personal data. We may share data with: service providers who assist in operating the Service (under strict confidentiality); and authorities when required by law.

8. Data Retention
We retain your data for as long as your account is active or as needed to provide the Service, and for a reasonable period thereafter for legal and safety reasons. You may request deletion of your account and associated data from your administrator.

9. Your Rights (GDPR)
Where the GDPR applies, you have the right to: access your data; rectify inaccurate data; erase your data in certain cases; restrict or object to processing; data portability; and to withdraw consent. You also have the right to lodge a complaint with a supervisory authority. Contact your $appName administrator to exercise these rights.

10. Security
We implement appropriate technical and organizational measures to protect your personal data against unauthorized access, loss or alteration.

11. Changes
We may update this Privacy Policy from time to time. We will notify you of material changes where required by law. Continued use of the Service after changes constitutes acceptance of the updated policy.

12. Contact
For privacy-related questions or to exercise your rights, please contact the administrator of your $appName instance.
''';
}
