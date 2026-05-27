import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/zalmanim_icons.dart';

/// Standalone users & permissions management screen (navigate via [Navigator]).
class UsersManagementPage extends StatefulWidget {
  const UsersManagementPage({
    super.key,
    required this.apiClient,
    required this.token,
  });

  final ApiClient apiClient;
  final String token;

  @override
  State<UsersManagementPage> createState() => _UsersManagementPageState();
}

class _UsersManagementPageState extends State<UsersManagementPage> {
  bool _loading = true;
  String? _error;
  List<dynamic> _users = const [];
  List<dynamic> _artists = const [];

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
      final results = await Future.wait([
        widget.apiClient.fetchUsers(widget.token),
        widget.apiClient.fetchArtists(widget.token,
            includeInactive: true, limit: 200, offset: 0),
      ]);
      if (!mounted) return;
      setState(() {
        _users = results[0];
        _artists = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _showUserDialog({Map<String, dynamic>? user}) async {
    final isEdit = user != null;
    final emailController =
        TextEditingController(text: user?['email'] as String? ?? '');
    final nameController =
        TextEditingController(text: user?['full_name'] as String? ?? '');
    final passwordController = TextEditingController();
    String role = (user?['role'] as String? ?? 'artist').toLowerCase();
    bool isActive = user?['is_active'] as bool? ?? true;
    int? artistId = user?['artist_id'] as int?;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(isEdit ? 'Edit user' : 'Create user'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(
                        labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: 'Full name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: isEdit
                          ? 'New password (optional)'
                          : 'Password (optional)',
                      border: const OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(
                        labelText: 'Role', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(
                          value: 'manager', child: Text('Manager')),
                      DropdownMenuItem(value: 'artist', child: Text('Artist')),
                    ],
                    onChanged: (value) =>
                        setStateDialog(() => role = value ?? role),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: artistId,
                    decoration: const InputDecoration(
                        labelText: 'Linked artist',
                        border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('No linked artist')),
                      ..._artists.map((artist) {
                        final map = artist as Map<String, dynamic>;
                        return DropdownMenuItem<int?>(
                          value: map['id'] as int,
                          child: Text((map['name'] ?? map['email']).toString()),
                        );
                      }),
                    ],
                    onChanged: (value) =>
                        setStateDialog(() => artistId = value),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: isActive,
                    onChanged: (value) =>
                        setStateDialog(() => isActive = value),
                    title: const Text('Active user'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(isEdit ? 'Save' : 'Create')),
          ],
        ),
      ),
    );

    if (saved != true) {
      emailController.dispose();
      nameController.dispose();
      passwordController.dispose();
      return;
    }

    final body = <String, dynamic>{
      'email': emailController.text.trim(),
      'full_name': nameController.text.trim(),
      'role': role,
      'is_active': isActive,
      'artist_id': artistId,
    };
    if (passwordController.text.trim().isNotEmpty) {
      body['password'] = passwordController.text.trim();
    }

    try {
      if (isEdit) {
        await widget.apiClient
            .updateUser(token: widget.token, id: user['id'] as int, body: body);
      } else {
        await widget.apiClient.createUser(token: widget.token, body: body);
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEdit ? 'User updated.' : 'User created.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText(e.toString())),
      );
    } finally {
      emailController.dispose();
      nameController.dispose();
      passwordController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users & Permissions'),
        leading: IconButton(
          icon: const Icon(ZalmanimIcons.arrowBack),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(ZalmanimIcons.refresh)),
          IconButton(
              onPressed: _loading ? null : () => _showUserDialog(),
              icon: const Icon(ZalmanimIcons.personAdd)),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: SelectableText(_error!));
    }
    if (_users.isEmpty) {
      return const Center(child: Text('No users configured yet.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final user = _users[index] as Map<String, dynamic>;
        final identities = user['identities'] as List<dynamic>? ?? const [];
        final providers = identities
            .map((item) =>
                ((item as Map<String, dynamic>)['provider'] ?? '').toString())
            .where((item) => item.isNotEmpty)
            .join(', ');
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(
                  ((user['full_name'] ?? user['email'] ?? '?').toString())
                      .substring(0, 1)
                      .toUpperCase()),
            ),
            title: Text((user['full_name'] as String?)?.isNotEmpty == true
                ? user['full_name'] as String
                : user['email'] as String),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user['email'] as String? ?? ''),
                Text(
                    'Role: ${(user['role'] ?? '').toString()}${(user['is_active'] as bool? ?? false) ? '' : ' • inactive'}'),
                if ((user['artist_name'] as String?)?.isNotEmpty == true)
                  Text('Artist: ${user['artist_name']}'),
                Text(
                    'Providers: ${providers.isEmpty ? 'password/manual' : providers}'),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(ZalmanimIcons.edit),
              onPressed: () => _showUserDialog(user: user),
            ),
          ),
        );
      },
    );
  }
}
