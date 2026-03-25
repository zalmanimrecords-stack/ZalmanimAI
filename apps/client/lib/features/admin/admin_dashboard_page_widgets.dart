part of 'admin_dashboard_page.dart';

// --- Artist details dialog tabs: Info and Logs ---

class _ArtistInfoTab extends StatelessWidget {
  const _ArtistInfoTab({required this.artistMap, required this.onEdit});

  final Map<String, dynamic> artistMap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final extra = artistMap['extra'] as Map<String, dynamic>? ?? {};
    final name = (artistMap['name'] ?? '').toString();
    final email = (artistMap['email'] ?? '').toString();
    final notes = (artistMap['notes'] ?? '').toString();
    final brand = (extra['artist_brand'] ?? name).toString();
    final fullName = (extra['full_name'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _infoRow('Brand', brand),
          if (fullName.isNotEmpty) _infoRow('Full name', fullName),
          _infoRow('Email', email),
          if (notes.isNotEmpty) _infoRow('Notes', notes),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onEdit,
            icon: const Icon(ZalmanimIcons.edit, size: 18),
            label: const Text('Edit artist'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          SelectableText(value, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}

class _ArtistLogsTab extends StatefulWidget {
  const _ArtistLogsTab({
    required this.apiClient,
    required this.token,
    required this.artistId,
  });

  final ApiClient apiClient;
  final String token;
  final int artistId;

  @override
  State<_ArtistLogsTab> createState() => _ArtistLogsTabState();
}

class _ArtistLogsTabState extends State<_ArtistLogsTab> {
  List<dynamic> _logs = [];
  bool _loading = true;
  String? _error;

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
      final list = await widget.apiClient
          .fetchArtistActivity(widget.token, widget.artistId);
      if (!mounted) return;
      setState(() {
        _logs = list;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_logs.isEmpty) {
      return const Center(child: Text('No activity logged yet.'));
    }
    return ListView.builder(
      shrinkWrap: true,
      itemCount: _logs.length,
      itemBuilder: (_, i) {
        final log = _logs[i] as Map<String, dynamic>;
        final type = (log['activity_type'] ?? '').toString();
        final details = (log['details'] ?? '').toString();
        final createdAt = log['created_at'];
        String dateStr = '';
        if (createdAt != null) {
          try {
            final dt = DateTime.parse(createdAt.toString());
            dateStr =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          } catch (_) {
            dateStr = createdAt.toString();
          }
        }
        return ListTile(
          leading: Icon(
            type == 'reminder_email'
                ? ZalmanimIcons.email
                : ZalmanimIcons.history,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: Text(type == 'reminder_email' ? 'Reminder email sent' : type),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(dateStr, style: const TextStyle(fontSize: 12)),
              if (details.isNotEmpty)
                SelectableText(details, style: const TextStyle(fontSize: 11)),
            ],
          ),
          dense: true,
        );
      },
    );
  }
}

class UsersManagementPage extends StatefulWidget {
  const UsersManagementPage(
      {super.key, required this.apiClient, required this.token});

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
                    initialValue: role,
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
                    initialValue: artistId,
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
        SnackBar(content: Text(e.toString())),
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
      return Center(child: Text(_error!));
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

/// Link to download the demo MP3 file (fetches with auth, then triggers browser download).
class _DemoDownloadMp3Link extends StatefulWidget {
  const _DemoDownloadMp3Link({
    required this.demoId,
    required this.apiClient,
    required this.token,
  });

  final int demoId;
  final ApiClient apiClient;
  final String token;

  @override
  State<_DemoDownloadMp3Link> createState() => _DemoDownloadMp3LinkState();
}

class _DemoDownloadMp3LinkState extends State<_DemoDownloadMp3Link> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await widget.apiClient.downloadDemoSubmissionFile(
        token: widget.token,
        id: widget.demoId,
      );
      if (!mounted) return;
      triggerBrowserDownload(
        bytes,
        'demo_${widget.demoId}.mp3',
        mimeType: 'audio/mpeg',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download started.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: FilledButton.icon(
        onPressed: _downloading ? null : _download,
        icon: _downloading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.download, size: 20),
        label: Text(_downloading ? 'Downloading...' : 'Download MP3'),
      ),
    );
  }
}

class _SoundCloudEmbedWidget extends StatefulWidget {
  const _SoundCloudEmbedWidget({required this.soundCloudUrl});

  final String soundCloudUrl;

  @override
  State<_SoundCloudEmbedWidget> createState() => _SoundCloudEmbedWidgetState();
}

class _SoundCloudEmbedWidgetState extends State<_SoundCloudEmbedWidget> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    final encoded = Uri.encodeComponent(widget.soundCloudUrl);
    final embedUrl =
        'https://w.soundcloud.com/player/?url=$encoded&color=%23ff5500&auto_play=false&hide_related=false&show_comments=true&show_user=true&show_reposts=false&show_teaser=true';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(embedUrl));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 166,
      width: double.infinity,
      child: WebViewWidget(controller: _controller),
    );
  }
}

/// Normalizes JSON `id` (int, double, or string) for list lookups.
int? _coerceArtistId(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}
