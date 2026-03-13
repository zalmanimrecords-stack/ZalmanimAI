import 'package:flutter/material.dart';

import '../admin_dashboard_delegate.dart';

/// Admin users tab: list users, add/edit/deactivate. Admin-only.
class UsersTab extends StatelessWidget {
  const UsersTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    final users = delegate.usersList;
    return RefreshIndicator(
      onRefresh: delegate.loadUsers,
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
                  icon: const Icon(Icons.add),
                  label: const Text('Add user'),
                ),
              ],
            ),
          ),
          Expanded(
            child: users.isEmpty
                ? const Center(child: Text('No users yet. Add a user to get started.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: users.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final u = users[index] as Map<String, dynamic>;
                      final id = u['id'] as int?;
                      final email = (u['email'] ?? '').toString();
                      final fullName = (u['full_name'] ?? '').toString();
                      final role = (u['role'] ?? '').toString();
                      final isActive = u['is_active'] as bool? ?? true;
                      final lastLogin = u['last_login_at'];
                      final lastLoginStr = lastLogin != null
                          ? _formatIso(lastLogin.toString())
                          : '—';
                      return Card(
                        child: ListTile(
                          title: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  fullName.isNotEmpty ? '$fullName ($email)' : email,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isActive ? null : Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _roleColor(context, role).withValues(alpha: 0.2),
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
                                    backgroundColor: Theme.of(context).colorScheme.errorContainer,
                                  ),
                                ),
                            ],
                          ),
                          subtitle: SelectableText('Last login: $lastLoginStr'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit user',
                                onPressed: () => delegate.showEditUserDialog(u),
                              ),
                              if (id != null)
                                PopupMenuButton<String>(
                                  tooltip: 'More',
                                  onSelected: (value) {
                                    if (value == 'toggle_active') {
                                      delegate.updateUserActive(u, !isActive);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'toggle_active',
                                      child: Text(isActive ? 'Deactivate user' : 'Activate user'),
                                    ),
                                  ],
                                  icon: const Icon(Icons.more_vert),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _formatIso(String iso) {
    try {
      final dt = DateTime.tryParse(iso);
      if (dt != null) return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}
    return iso;
  }

  static Color _roleColor(BuildContext context, String role) {
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
}
