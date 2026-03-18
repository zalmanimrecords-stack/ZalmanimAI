import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/zalmanim_icons.dart';

/// Mail settings UI: SMTP, test, Google Mail. (Demo rejection template is in Email Templates.)
/// Used in System Settings page and in Settings > Mail settings tab.
class MailSettingsContent extends StatefulWidget {
  const MailSettingsContent({
    super.key,
    required this.apiClient,
    required this.token,
    this.initialSettings,
  });

  final ApiClient apiClient;
  final String token;
  /// When provided (e.g. from System Settings page), use this instead of loading.
  final Map<String, dynamic>? initialSettings;

  @override
  State<MailSettingsContent> createState() => _MailSettingsContentState();
}

class _MailSettingsContentState extends State<MailSettingsContent> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _settings;
  bool _savingMail = false;
  bool _testingMail = false;
  bool _sendingTestMail = false;
  bool _connectingGoogle = false;
  String? _mailSaveError;
  String? _mailTestMessage;

  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpFromEmailController = TextEditingController();
  final _smtpUserController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _emailsPerHourController = TextEditingController();
  final _emailFooterController = TextEditingController();
  final _testEmailController = TextEditingController();
  bool _smtpUseTls = true;
  bool _smtpUseSsl = false;

  @override
  void dispose() {
    _smtpHostController.dispose();
    _smtpPortController.dispose();
    _smtpFromEmailController.dispose();
    _smtpUserController.dispose();
    _smtpPasswordController.dispose();
    _emailsPerHourController.dispose();
    _emailFooterController.dispose();
    _testEmailController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialSettings != null) {
      _settings = widget.initialSettings;
      _loading = false;
      _fillMailFormFromSettings(_settings!);
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.apiClient.fetchSystemSettings(widget.token);
      if (mounted) {
        setState(() {
          _settings = data;
          _loading = false;
          _mailSaveError = null;
          _fillMailFormFromSettings(data);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _fillMailFormFromSettings(Map<String, dynamic> s) {
    _smtpHostController.text = s['smtp_host'] as String? ?? 'smtp.gmail.com';
    _smtpPortController.text = (s['smtp_port'] as int?)?.toString() ?? '587';
    _smtpFromEmailController.text = s['smtp_from_email'] as String? ?? '';
    _smtpUserController.text = '';
    _smtpPasswordController.text = '';
    _emailsPerHourController.text = (s['emails_per_hour'] as int?)?.toString() ?? '30';
    _emailFooterController.text = s['email_footer'] as String? ?? '';
    _smtpUseTls = s['smtp_use_tls'] as bool? ?? true;
    _smtpUseSsl = s['smtp_use_ssl'] as bool? ?? false;
  }

  int? get _smtpPort => int.tryParse(_smtpPortController.text.trim());
  int? get _emailsPerHour => int.tryParse(_emailsPerHourController.text.trim());

  Future<void> _saveMailSettings() async {
    setState(() {
      _savingMail = true;
      _mailSaveError = null;
      _mailTestMessage = null;
    });
    try {
      final data = await widget.apiClient.updateSystemSettingsMail(
        token: widget.token,
        smtpHost: _smtpHostController.text.trim(),
        smtpPort: _smtpPort,
        smtpFromEmail: _smtpFromEmailController.text.trim(),
        smtpUseTls: _smtpUseTls,
        smtpUseSsl: _smtpUseSsl,
        smtpUser: _smtpUserController.text.trim(),
        smtpPassword: _smtpPasswordController.text.trim().isEmpty ? null : _smtpPasswordController.text.trim(),
        emailsPerHour: _emailsPerHour,
        emailFooter: _emailFooterController.text,
      );
      if (mounted) {
        setState(() {
          _settings = data;
          _savingMail = false;
          _mailSaveError = null;
          _fillMailFormFromSettings(data);
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mail settings saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _savingMail = false;
          _mailSaveError = e.toString();
        });
      }
    }
  }

  Future<void> _testSmtpConnection() async {
    setState(() {
      _testingMail = true;
      _mailSaveError = null;
      _mailTestMessage = null;
    });
    try {
      final result = await widget.apiClient.testSystemSettingsMail(
        token: widget.token,
        smtpHost: _smtpHostController.text.trim(),
        smtpPort: _smtpPort,
        smtpFromEmail: _smtpFromEmailController.text.trim(),
        smtpUseTls: _smtpUseTls,
        smtpUseSsl: _smtpUseSsl,
        smtpUser: _smtpUserController.text.trim(),
        smtpPassword: _smtpPasswordController.text.trim().isEmpty ? null : _smtpPasswordController.text.trim(),
        emailsPerHour: _emailsPerHour,
      );
      if (mounted) {
        setState(() {
          _mailTestMessage = result['message'] as String? ?? 'SMTP test completed.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _mailSaveError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _testingMail = false);
    }
  }

  Future<void> _sendTestEmail() async {
    final testEmail = _testEmailController.text.trim();
    if (testEmail.isEmpty) {
      setState(() => _mailSaveError = 'Enter a test email address first.');
      return;
    }
    setState(() {
      _sendingTestMail = true;
      _mailSaveError = null;
      _mailTestMessage = null;
    });
    try {
      final result = await widget.apiClient.testSystemSettingsMail(
        token: widget.token,
        smtpHost: _smtpHostController.text.trim(),
        smtpPort: _smtpPort,
        smtpFromEmail: _smtpFromEmailController.text.trim(),
        smtpUseTls: _smtpUseTls,
        smtpUseSsl: _smtpUseSsl,
        smtpUser: _smtpUserController.text.trim(),
        smtpPassword: _smtpPasswordController.text.trim().isEmpty ? null : _smtpPasswordController.text.trim(),
        emailsPerHour: _emailsPerHour,
        testEmail: testEmail,
      );
      if (mounted) {
        setState(() {
          _mailTestMessage = result['message'] as String? ?? 'Test email sent.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _mailSaveError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _sendingTestMail = false);
    }
  }

  Future<void> _connectGoogleMail() async {
    setState(() {
      _connectingGoogle = true;
      _mailSaveError = null;
    });
    try {
      final redirectUri = Uri.base.replace(queryParameters: const {}, fragment: '').toString();
      final authUrl = await widget.apiClient.startGoogleMailConnect(
        token: widget.token,
        redirectUri: redirectUri,
      );
      final launched = await launchUrl(Uri.parse(authUrl), webOnlyWindowName: '_self');
      if (!launched && mounted) {
        setState(() => _mailSaveError = 'Could not open Google authorization page.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _mailSaveError = e.toString());
      }
    } finally {
      if (mounted) setState(() => _connectingGoogle = false);
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SelectableText(value.isEmpty ? '(not set)' : value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () => Clipboard.setData(ClipboardData(text: _error!)),
            ),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final s = _settings!;
    final googleConfigured = s['google_oauth_configured'] as bool? ?? false;
    final gmailConnected = s['gmail_connected'] as bool? ?? false;
    final facebookConfigured = s['facebook_oauth_configured'] as bool? ?? false;
    final gmailConnectedEmail = s['gmail_connected_email'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Mail server (SMTP)'),
          const Text(
            'Edit mail server details below. Values are stored in the server database and override environment variables.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Global email footer',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This text is appended automatically to every outgoing email from the system.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailFooterController,
                    decoration: const InputDecoration(
                      labelText: 'Email footer',
                      hintText: 'Appended automatically to every outgoing email.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    minLines: 3,
                    textInputAction: TextInputAction.newline,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        TextField(
          controller: _smtpHostController,
          decoration: const InputDecoration(
            labelText: 'SMTP host',
            hintText: 'smtp.gmail.com',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _smtpPortController,
          decoration: const InputDecoration(
            labelText: 'SMTP port',
            hintText: '587 or 465',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _smtpFromEmailController,
          decoration: const InputDecoration(
            labelText: 'From email',
            hintText: 'noreply@example.com',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _smtpUserController,
          decoration: const InputDecoration(
            labelText: 'SMTP user (optional)',
            hintText: 'Leave blank to keep current',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _smtpPasswordController,
          decoration: const InputDecoration(
            labelText: 'SMTP password (optional)',
            hintText: 'Leave blank to keep current',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _emailsPerHourController,
          decoration: const InputDecoration(
            labelText: 'Emails per hour limit',
            hintText: '30',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: _smtpUseTls,
              onChanged: (v) => setState(() => _smtpUseTls = v ?? true),
            ),
            const Text('Use TLS (STARTTLS)'),
          ],
        ),
        Row(
          children: [
            Checkbox(
              value: _smtpUseSsl,
              onChanged: (v) => setState(() => _smtpUseSsl = v ?? false),
            ),
            const Text('Use SSL (implicit, e.g. port 465)'),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _testEmailController,
          decoration: const InputDecoration(
            labelText: 'Test email address',
            hintText: 'you@example.com',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 24),
        if (_mailSaveError != null) ...[
          const SizedBox(height: 8),
          SelectableText(_mailSaveError!, style: const TextStyle(color: Colors.red)),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy error',
            onPressed: () => Clipboard.setData(ClipboardData(text: _mailSaveError!)),
          ),
        ],
        if (_mailTestMessage != null) ...[
          const SizedBox(height: 8),
          SelectableText(_mailTestMessage!, style: const TextStyle(color: Colors.green)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _savingMail ? null : _saveMailSettings,
          icon: _savingMail ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(ZalmanimIcons.save),
          label: Text(_savingMail ? 'Saving...' : 'Save mail settings'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _testingMail || _sendingTestMail ? null : _testSmtpConnection,
                icon: _testingMail ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(ZalmanimIcons.networkCheck),
                label: Text(_testingMail ? 'Testing...' : 'Test SMTP'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _sendingTestMail || _testingMail ? null : _sendTestEmail,
                icon: _sendingTestMail ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(ZalmanimIcons.send),
                label: Text(_sendingTestMail ? 'Sending...' : 'Send test email'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _row('Status', (s['email_configured'] as bool? ?? false) ? 'Configured' : 'Not configured'),
        const SizedBox(height: 24),
        _sectionTitle('Google Mail'),
        _row('Google OAuth', googleConfigured ? 'Configured on server' : 'Missing GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET'),
        _row('Facebook OAuth', facebookConfigured ? 'Configured on server' : 'Missing META_CLIENT_ID / META_CLIENT_SECRET'),
        _row('Gmail connection', gmailConnected ? 'Connected' : 'Not connected'),
        _row('Connected account', gmailConnectedEmail),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: googleConfigured && !_connectingGoogle ? _connectGoogleMail : null,
          icon: _connectingGoogle ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(ZalmanimIcons.alternateEmail),
          label: Text(_connectingGoogle ? 'Opening Google...' : (gmailConnected ? 'Reconnect Gmail account' : 'Connect Gmail account')),
        ),
        ],
      ),
    );
  }
}
