import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:labelops_client/core/app_reload_stub.dart' if (dart.library.html) 'package:labelops_client/core/app_reload_web.dart' as app_reload;
import '../../../core/backup_download_stub.dart'
    if (dart.library.html) '../../../core/backup_download_web.dart' as backup_download;
import '../../../core/session_storage.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import '../mail_settings_content.dart';
import 'db_tab.dart';
import 'email_templates_tab.dart';
import 'logs_tab.dart';
import 'users_tab.dart';

/// Settings tab: contains sub-tabs (Users, Mail settings, Email templates, Logs, DB, Backup, General).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: TabBar(
              tabs: [
                Tab(
                  icon: Icon(
                    ZalmanimIcons.account,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Users',
                ),
                Tab(
                  icon: Icon(
                    ZalmanimIcons.email,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Mail settings',
                ),
                Tab(
                  icon: Icon(
                    Icons.description_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Email templates',
                ),
                Tab(
                  icon: Icon(
                    Icons.history_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Logs',
                ),
                Tab(
                  icon: Icon(
                    Icons.storage_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'DB',
                ),
                Tab(
                  icon: Icon(
                    ZalmanimIcons.backup,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Backup',
                ),
                Tab(
                  icon: Icon(
                    ZalmanimIcons.settings,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'General',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                UsersTab(delegate: delegate),
                MailSettingsSubTab(delegate: delegate),
                EmailTemplatesTab(delegate: delegate),
                LogsTab(delegate: delegate),
                DbTab(delegate: delegate),
                BackupSubTab(delegate: delegate),
                const _GeneralSubTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mail settings sub-tab: server mail (SMTP, Google) + artist reminder shortcut. Email templates live in Email templates.
class MailSettingsSubTab extends StatelessWidget {
  const MailSettingsSubTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Artist reminder emails',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Default subject and body for reminder emails sent from Reports > Artist reminders.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => delegate.showArtistReminderMailSettingsDialog(context),
                    icon: const Icon(ZalmanimIcons.edit, size: 18),
                    label: const Text('Edit default subject & body'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: SingleChildScrollView(
            child: MailSettingsContent(
              apiClient: delegate.apiClient,
              token: delegate.token,
            ),
          ),
        ),
      ],
    );
  }
}

/// Backup / Restore sub-tab: download full DB backup (JSON) or restore from file.
class BackupSubTab extends StatefulWidget {
  const BackupSubTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<BackupSubTab> createState() => _BackupSubTabState();
}

class _BackupSubTabState extends State<BackupSubTab> {
  bool _backupLoading = false;
  bool _restoreLoading = false;
  String? _backupRestoreMessage;

  Future<void> _downloadBackup() async {
    setState(() {
      _backupLoading = true;
      _backupRestoreMessage = null;
    });
    try {
      final result = await widget.delegate.apiClient.downloadBackup(widget.delegate.token);
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
          _backupRestoreMessage =
              'Download is only supported on web. Use GET /api/admin/backup with your token.';
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
      await widget.delegate.apiClient.restoreBackup(
        token: widget.delegate.token,
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Backup / Restore',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Download a full backup of all DB data (JSON). Use the same file on another system to restore via Restore.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (_backupRestoreMessage != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            _backupRestoreMessage!,
                            style: TextStyle(
                              color: _backupRestoreMessage!.startsWith('Restore completed') ||
                                      _backupRestoreMessage == 'Backup downloaded.'
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 20),
                          tooltip: 'Copy',
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: _backupRestoreMessage!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _backupLoading ? null : _downloadBackup,
                          icon: _backupLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(ZalmanimIcons.backup),
                          label: Text(_backupLoading ? 'Preparing...' : 'Download backup'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _restoreLoading ? null : _restoreBackup,
                          icon: _restoreLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(ZalmanimIcons.restore),
                          label: Text(_restoreLoading ? 'Restoring...' : 'Restore from file'),
                        ),
                      ),
                    ],
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

/// General options: clear cache and reload.
class _GeneralSubTab extends StatefulWidget {
  const _GeneralSubTab();

  @override
  State<_GeneralSubTab> createState() => _GeneralSubTabState();
}

class _GeneralSubTabState extends State<_GeneralSubTab> {
  bool _clearing = false;

  Future<void> _clearCacheAndReload() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cache and reload'),
        content: const Text(
          'This will clear all local data (session, cookie consent, saved templates) and reload the app from the server. You will need to sign in again.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear and reload'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    await clearAllAppCache();
    if (!mounted) return;
    app_reload.reloadApp();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Clear cache and reload',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Clear all local cache and reload the app from the server. Use this if you see stale data or after server updates. You will be signed out and need to sign in again.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _clearing ? null : _clearCacheAndReload,
                    icon: _clearing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 20),
                    label: Text(_clearing ? 'Clearing...' : 'Clear cache and reload'),
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
