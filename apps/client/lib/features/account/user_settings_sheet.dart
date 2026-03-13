import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';

class UserSettingsSheet extends StatefulWidget {
  const UserSettingsSheet({
    super.key,
    required this.apiClient,
    required this.session,
    required this.onLogout,
    this.onRefresh,
  });

  final ApiClient apiClient;
  final AuthSession session;
  final Future<void> Function() onLogout;
  final Future<void> Function()? onRefresh;

  @override
  State<UserSettingsSheet> createState() => _UserSettingsSheetState();
}

class _UserSettingsSheetState extends State<UserSettingsSheet> {
  bool _sendingReset = false;
  bool _refreshing = false;
  bool _loggingOut = false;
  String? _message;
  String? _error;

  String get _displayName {
    final fullName = widget.session.fullName?.trim() ?? '';
    if (fullName.isNotEmpty) return fullName;
    final email = widget.session.email?.trim() ?? '';
    if (email.isNotEmpty) return email;
    return 'User';
  }

  String get _roleLabel {
    switch (widget.session.role) {
      case 'admin':
        return 'Administrator';
      case 'manager':
        return 'Manager';
      case 'artist':
        return 'Artist';
      default:
        return widget.session.role;
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = widget.session.email?.trim() ?? '';
    if (email.isEmpty) {
      setState(() {
        _error = 'No email is available for this account.';
        _message = null;
      });
      return;
    }

    setState(() {
      _sendingReset = true;
      _error = null;
      _message = null;
    });

    try {
      await widget.apiClient.requestPasswordReset(email: email);
      if (!mounted) return;
      setState(() {
        _message = 'A password reset link was sent to $email if the account exists.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _sendingReset = false);
      }
    }
  }

  Future<void> _refresh() async {
    if (widget.onRefresh == null) return;
    setState(() {
      _refreshing = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.onRefresh!();
      if (!mounted) return;
      setState(() {
        _message = 'The screen was refreshed successfully.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _logout() async {
    setState(() {
      _loggingOut = true;
      _error = null;
      _message = null;
    });
    try {
      await widget.onLogout();
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = widget.session.email?.trim();
    final initials = _displayName.isEmpty
        ? 'U'
        : _displayName.characters.first.toUpperCase();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'User settings',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    child: Text(
                      initials,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          style: theme.textTheme.titleMedium,
                        ),
                        if (email != null && email.isNotEmpty)
                          Text(
                            email,
                            style: theme.textTheme.bodyMedium,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Role: $_roleLabel',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.lock_reset),
                      title: const Text('Reset password'),
                      subtitle: Text(
                        email == null || email.isEmpty
                            ? 'No email is available for this account.'
                            : 'Send a reset link to $email',
                      ),
                      trailing: _sendingReset
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right),
                      onTap: _sendingReset || _loggingOut ? null : _sendPasswordReset,
                    ),
                    if (widget.onRefresh != null)
                      const Divider(height: 1),
                    if (widget.onRefresh != null)
                      ListTile(
                        leading: const Icon(Icons.refresh),
                        title: const Text('Refresh current screen'),
                        subtitle: const Text('Reload account data and dashboard content'),
                        trailing: _refreshing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: _refreshing || _loggingOut ? null : _refresh,
                      ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.logout,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Log out',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text('Sign out from this device and return to login'),
                      trailing: _loggingOut
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.chevron_right,
                              color: theme.colorScheme.error,
                            ),
                      onTap: _loggingOut ? null : _logout,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Common account actions are available here: password recovery, session control, and a quick refresh for the current workspace.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(
                  _message!,
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
