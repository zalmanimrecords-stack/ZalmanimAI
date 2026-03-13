import 'package:flutter/material.dart';

import 'package:labelops_client/core/app_reload_stub.dart' if (dart.library.html) 'package:labelops_client/core/app_reload_web.dart' as app_reload;
import '../../../core/session_storage.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';
import '../mail_settings_content.dart';
import 'email_templates_tab.dart';
import 'logs_tab.dart';
import 'users_tab.dart';

/// Settings tab: contains sub-tabs (Users, Mail settings, Email templates, Logs, General).
class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
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
                const _GeneralSubTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mail settings sub-tab: server mail (SMTP, demo rejection, Google) + artist reminder template.
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
