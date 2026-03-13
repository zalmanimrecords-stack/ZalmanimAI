import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/zalmanim_icons.dart';
import '../../core/backup_download_stub.dart'
    if (dart.library.html) '../../core/backup_download_web.dart' as backup_download;

/// System settings: mail server editable; OAuth read-only from env.
class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key, required this.apiClient, required this.token});

  final ApiClient apiClient;
  final String token;

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _settings;
  bool _savingMail = false;
  bool _testingMail = false;
  bool _sendingTestMail = false;
  bool _connectingGoogle = false;
  String? _mailSaveError;
  String? _mailTestMessage;
  bool _backupLoading = false;
  bool _restoreLoading = false;
  String? _backupRestoreMessage;

  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpFromEmailController = TextEditingController();
  final _smtpUserController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _emailsPerHourController = TextEditingController();
  final _testEmailController = TextEditingController();
  final _demoRejectionSubjectController = TextEditingController();
  final _demoRejectionBodyController = TextEditingController();
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
    _testEmailController.dispose();
    _demoRejectionSubjectController.dispose();
    _demoRejectionBodyController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
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
    _smtpUseTls = s['smtp_use_tls'] as bool? ?? true;
    _smtpUseSsl = s['smtp_use_ssl'] as bool? ?? false;
    _demoRejectionSubjectController.text = s['demo_rejection_subject'] as String? ?? '';
    _demoRejectionBodyController.text = s['demo_rejection_body'] as String? ?? '';
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
        demoRejectionSubject: _demoRejectionSubjectController.text.trim(),
        demoRejectionBody: _demoRejectionBodyController.text.trim(),
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

  Future<void> _downloadBackup() async {
    setState(() {
      _backupLoading = true;
      _backupRestoreMessage = null;
    });
    try {
      final result = await widget.apiClient.downloadBackup(widget.token);
      backup_download.downloadBackupFile(result.bytes, result.filename);
      if (mounted) {
        setState(() {
          _backupLoading = false;
          _backupRestoreMessage = 'Backup downloaded.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup downloaded.')),
        );
      }
    } on UnsupportedError catch (_) {
      if (mounted) {
        setState(() {
          _backupLoading = false;
          _backupRestoreMessage = 'Download is only supported on web. Use GET /api/admin/backup with your token.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _backupLoading = false;
          _backupRestoreMessage = e.toString();
        });
      }
    }
  }

  Future<void> _restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.bytes == null || f.bytes!.isEmpty) {
      if (mounted) {
        setState(() => _backupRestoreMessage = 'No file data.');
      }
      return;
    }
    setState(() {
      _restoreLoading = true;
      _backupRestoreMessage = null;
    });
    try {
      await widget.apiClient.restoreBackup(
        token: widget.token,
        fileBytes: f.bytes!,
        filename: f.name,
      );
      if (mounted) {
        setState(() {
          _restoreLoading = false;
          _backupRestoreMessage = 'Restore completed successfully.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore completed successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _restoreLoading = false;
          _backupRestoreMessage = e.toString();
        });
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Settings'),
        leading: IconButton(
          icon: const Icon(ZalmanimIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sectionTitle('Mail server (SMTP)'),
        const Text(
          'Edit mail server details below. Values are stored in the server database and override environment variables.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
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
        _sectionTitle('Demo rejection email'),
        const Text(
          'When you mark a demo as rejected, an email is sent to the artist. Edit the subject and body below. '
          'Placeholders: {artist_name}, {artist_portal_url}, {zalmanim_website}.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _demoRejectionSubjectController,
          decoration: const InputDecoration(
            labelText: 'Rejection email subject',
            hintText: 'Thank you for your demo submission',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _demoRejectionBodyController,
          decoration: const InputDecoration(
            labelText: 'Rejection email body',
            hintText: 'Hi {artist_name}, ...',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          maxLines: 8,
          textInputAction: TextInputAction.newline,
        ),
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
        const SizedBox(height: 24),
        _sectionTitle('OAuth / Redirects (read-only)'),
        const Text(
          'OAuth URLs are set via server environment. Restart the server after changing them.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        _row('OAuth redirect base', s['oauth_redirect_base'] as String? ?? ''),
        _row('OAuth success redirect', s['oauth_success_redirect'] as String? ?? ''),
        const SizedBox(height: 24),
        _sectionTitle('Backup / Restore'),
        const Text(
          'Download a full backup of all DB data (JSON). Use the same file on another system to restore via Restore.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (_backupRestoreMessage != null) ...[
          SelectableText(
            _backupRestoreMessage!,
            style: TextStyle(
              color: _backupRestoreMessage!.startsWith('Restore completed') || _backupRestoreMessage == 'Backup downloaded.'
                  ? Colors.green
                  : Colors.red,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _backupLoading ? null : _downloadBackup,
                icon: _backupLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(ZalmanimIcons.backup),
                label: Text(_backupLoading ? 'Preparing...' : 'Download backup'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _restoreLoading ? null : _restoreBackup,
                icon: _restoreLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(ZalmanimIcons.restore),
                label: Text(_restoreLoading ? 'Restoring...' : 'Restore from file'),
              ),
            ),
          ],
        ),
      ],
    );
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
}



