import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/zalmanim_icons.dart';
import '../../core/backup_download_stub.dart'
    if (dart.library.html) '../../core/backup_download_web.dart' as backup_download;
import 'mail_settings_content.dart';

/// System settings: mail (via [MailSettingsContent]), OAuth read-only, backup/restore.
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
  bool _backupLoading = false;
  bool _restoreLoading = false;
  String? _backupRestoreMessage;

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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        MailSettingsContent(
          apiClient: widget.apiClient,
          token: widget.token,
          initialSettings: s,
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



