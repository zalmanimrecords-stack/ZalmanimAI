import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';

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
  String? _mailSaveError;

  final _smtpHostController = TextEditingController();
  final _smtpPortController = TextEditingController();
  final _smtpFromEmailController = TextEditingController();
  final _smtpUserController = TextEditingController();
  final _smtpPasswordController = TextEditingController();
  final _emailsPerHourController = TextEditingController();
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
    _smtpHostController.text = s['smtp_host'] as String? ?? '';
    _smtpPortController.text = (s['smtp_port'] as int?)?.toString() ?? '587';
    _smtpFromEmailController.text = s['smtp_from_email'] as String? ?? '';
    _smtpUserController.text = ''; // Never pre-fill user/password from API
    _smtpPasswordController.text = '';
    _emailsPerHourController.text = (s['emails_per_hour'] as int?)?.toString() ?? '30';
    _smtpUseTls = s['smtp_use_tls'] as bool? ?? true;
    _smtpUseSsl = s['smtp_use_ssl'] as bool? ?? false;
  }

  Future<void> _saveMailSettings() async {
    setState(() {
      _savingMail = true;
      _mailSaveError = null;
    });
    try {
      final port = int.tryParse(_smtpPortController.text.trim());
      final emailsPerHour = int.tryParse(_emailsPerHourController.text.trim());
      final pwd = _smtpPasswordController.text.trim();
      final data = await widget.apiClient.updateSystemSettingsMail(
        token: widget.token,
        smtpHost: _smtpHostController.text.trim(),
        smtpPort: port,
        smtpFromEmail: _smtpFromEmailController.text.trim(),
        smtpUseTls: _smtpUseTls,
        smtpUseSsl: _smtpUseSsl,
        smtpUser: _smtpUserController.text.trim(),
        smtpPassword: pwd.isEmpty ? null : pwd,
        emailsPerHour: emailsPerHour,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
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
            hintText: 'e.g. smtp.example.com',
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
        if (_mailSaveError != null) ...[
          const SizedBox(height: 8),
          SelectableText(_mailSaveError!, style: const TextStyle(color: Colors.red)),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy error',
            onPressed: () => Clipboard.setData(ClipboardData(text: _mailSaveError!)),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _savingMail ? null : _saveMailSettings,
          icon: _savingMail ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
          label: Text(_savingMail ? 'Saving...' : 'Save mail settings'),
        ),
        const SizedBox(height: 8),
        _row('Status', (s['email_configured'] as bool? ?? false) ? 'Configured' : 'Not configured'),
        const SizedBox(height: 24),
        _sectionTitle('OAuth / Redirects (read-only)'),
        const Text(
          'OAuth URLs are set via server environment. Restart the server after changing them.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        _row('OAuth redirect base', s['oauth_redirect_base'] as String? ?? ''),
        _row('OAuth success redirect', s['oauth_success_redirect'] as String? ?? ''),
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
