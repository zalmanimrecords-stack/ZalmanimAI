import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Admin users tab: list users, add/edit/deactivate. Admin-only.
class UsersTab extends StatefulWidget {
  const UsersTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  Map<String, dynamic>? _loginStats;
  bool _loadingStats = false;
  String? _statsError;

  AdminDashboardDelegate get delegate => widget.delegate;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (_loadingStats) return;
    setState(() {
      _loadingStats = true;
      _statsError = null;
    });
    try {
      final stats = await delegate.apiClient.fetchLoginStats(delegate.token);
      if (!mounted) return;
      setState(() {
        _loginStats = stats;
        _loadingStats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statsError = e.toString();
        _loadingStats = false;
      });
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      delegate.loadUsers(),
      _loadStats(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final users = delegate.usersList;
    final recentLogins =
        (_loginStats?['recent_logins'] as List<dynamic>? ?? const []);
    final usersLast30Days =
        _loginStats?['users_logged_in_last_30_days'] as int? ?? 0;
    final artistsLast30Days =
        _loginStats?['artists_logged_in_last_30_days'] as int? ?? 0;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Users',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                FilledButton.icon(
                  onPressed: delegate.showAddUserDialog,
                  icon: const Icon(ZalmanimIcons.add),
                  label: const Text('Add user'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _LoginStatsSection(
                  loading: _loadingStats,
                  error: _statsError,
                  usersLast30Days: usersLast30Days,
                  artistsLast30Days: artistsLast30Days,
                  recentLogins: recentLogins,
                  onRetry: _loadStats,
                ),
                const SizedBox(height: 16),
                if (users.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Center(
                      child: Text('No users yet. Add a user to get started.'),
                    ),
                  )
                else
                  ...[
                    for (var index = 0; index < users.length; index++) ...[
                      _UserCard(
                        user: users[index] as Map<String, dynamic>,
                        onEdit: delegate.showEditUserDialog,
                        onToggleActive: delegate.updateUserActive,
                      ),
                      if (index < users.length - 1) const SizedBox(height: 8),
                    ],
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginStatsSection extends StatelessWidget {
  const _LoginStatsSection({
    required this.loading,
    required this.error,
    required this.usersLast30Days,
    required this.artistsLast30Days,
    required this.recentLogins,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final int usersLast30Days;
  final int artistsLast30Days;
  final List<dynamic> recentLogins;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(
              title: 'Users active in 30 days',
              value: loading ? '...' : '$usersLast30Days',
              icon: ZalmanimIcons.adminPanel,
            ),
            _StatCard(
              title: 'Artists active in 30 days',
              value: loading ? '...' : '$artistsLast30Days',
              icon: ZalmanimIcons.graphicEq,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Recent connections',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: loading ? null : onRetry,
                      tooltip: 'Refresh activity',
                      icon: const Icon(ZalmanimIcons.refresh),
                    ),
                  ],
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  )
                else if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        TextButton(onPressed: onRetry, child: const Text('Retry')),
                      ],
                    ),
                  )
                else if (recentLogins.isEmpty)
                  Text(
                    'No login activity yet.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Column(
                    children: [
                      for (var index = 0; index < recentLogins.length; index++) ...[
                        _RecentLoginTile(item: recentLogins[index] as Map<String, dynamic>),
                        if (index < recentLogins.length - 1) const Divider(height: 1),
                      ],
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentLoginTile extends StatelessWidget {
  const _RecentLoginTile({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final name = (item['name'] ?? item['email'] ?? '').toString();
    final email = (item['email'] ?? '').toString();
    final source = (item['source'] ?? '').toString();
    final role = (item['role'] ?? '').toString();
    final isActive = item['is_active'] as bool? ?? true;
    final badgeText = source == 'artist_portal' ? 'Artist portal' : role;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(
          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
        ),
      ),
      title: Text(name),
      subtitle: Text(
        '$email • ${_formatIso((item['last_login_at'] ?? '').toString())}',
      ),
      trailing: Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isActive)
            Text(
              'Inactive',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onEdit,
    required this.onToggleActive,
  });

  final Map<String, dynamic> user;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final void Function(Map<String, dynamic>, bool) onToggleActive;

  @override
  Widget build(BuildContext context) {
    final id = user['id'] as int?;
    final email = (user['email'] ?? '').toString();
    final fullName = (user['full_name'] ?? '').toString();
    final role = (user['role'] ?? '').toString();
    final isActive = user['is_active'] as bool? ?? true;
    final lastLogin = user['last_login_at'];
    final lastLoginStr =
        lastLogin != null ? _formatIso(lastLogin.toString()) : '-';

    return Card(
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: SelectableText(
                fullName.isNotEmpty ? '$fullName ($email)' : email,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? null
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _roleColor(context, role).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                role,
                style: TextStyle(
                  fontSize: 12,
                  color: _roleColor(context, role),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!isActive)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Chip(
                  label: const Text('Inactive'),
                  labelStyle: const TextStyle(fontSize: 11),
                  backgroundColor:
                      Theme.of(context).colorScheme.errorContainer,
                ),
              ),
          ],
        ),
        subtitle: SelectableText('Last login: $lastLoginStr'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(ZalmanimIcons.edit),
              tooltip: 'Edit user',
              onPressed: () => onEdit(user),
            ),
            if (id != null)
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (value) {
                  if (value == 'toggle_active') {
                    onToggleActive(user, !isActive);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle_active',
                    child: Text(
                      isActive ? 'Deactivate user' : 'Activate user',
                    ),
                  ),
                ],
                icon: const Icon(ZalmanimIcons.moreVert),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatIso(String iso) {
  try {
    final dt = DateTime.tryParse(iso);
    if (dt != null) {
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
  } catch (_) {}
  return iso;
}

Color _roleColor(BuildContext context, String role) {
  switch (role) {
    case 'admin':
      return Colors.purple;
    case 'manager':
      return Colors.blue;
    case 'artist':
      return Colors.teal;
    default:
      return Theme.of(context).colorScheme.primary;
  }
}
