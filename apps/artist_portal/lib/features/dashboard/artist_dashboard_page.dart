import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/zalmanim_icons.dart';

class ArtistDashboardPage extends StatefulWidget {
  const ArtistDashboardPage({
    super.key,
    required this.apiClient,
    required this.token,
    this.onLogout,
  });

  final ApiClient apiClient;
  final String token;
  final Future<void> Function()? onLogout;

  @override
  State<ArtistDashboardPage> createState() => _ArtistDashboardPageState();
}

const List<MapEntry<String, String>> _socialKeys = [
  MapEntry('website', 'Website'),
  MapEntry('soundcloud', 'SoundCloud'),
  MapEntry('facebook', 'Facebook'),
  MapEntry('instagram', 'Instagram'),
  MapEntry('twitter_1', 'Twitter / X'),
  MapEntry('youtube', 'YouTube'),
  MapEntry('tiktok', 'TikTok'),
  MapEntry('spotify', 'Spotify'),
  MapEntry('apple_music', 'Apple Music'),
  MapEntry('linktree', 'Linktree'),
  MapEntry('other_1', 'Other link 1'),
  MapEntry('other_2', 'Other link 2'),
  MapEntry('other_3', 'Other link 3'),
];

class _ArtistDashboardPageState extends State<ArtistDashboardPage> {
  final titleController = TextEditingController();
  final demoMessageController = TextEditingController();
  final profileNameController = TextEditingController();
  final profileNotesController = TextEditingController();
  final profileWebsiteController = TextEditingController();
  final profileFullNameController = TextEditingController();
  final Map<String, TextEditingController> socialControllers = {};

  bool loading = true;
  bool uploading = false;
  bool savingProfile = false;
  bool changingPassword = false;
  bool submittingDemo = false;
  bool uploadingMedia = false;
  bool requestingCampaign = false;
  String? error;
  Map<String, dynamic>? dashboard;
  List<dynamic> demos = [];
  List<dynamic> mediaList = [];
  int mediaUsedBytes = 0;
  int mediaQuotaBytes = 50 * 1024 * 1024;
  List<dynamic> campaignRequests = [];

  @override
  void initState() {
    super.initState();
    for (final e in _socialKeys) {
      socialControllers[e.key] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    titleController.dispose();
    demoMessageController.dispose();
    profileNameController.dispose();
    profileNotesController.dispose();
    profileWebsiteController.dispose();
    profileFullNameController.dispose();
    for (final c in socialControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.apiClient.fetchArtistDashboard(widget.token);
      final profile = result['artist'] as Map<String, dynamic>?;
      if (profile != null) {
        profileNameController.text = profile['name']?.toString() ?? '';
        profileNotesController.text = profile['notes']?.toString() ?? '';
        final extra = profile['extra'];
        if (extra is Map<String, dynamic>) {
          profileWebsiteController.text = extra['website']?.toString() ?? '';
          profileFullNameController.text = extra['full_name']?.toString() ?? '';
          for (final e in _socialKeys) {
            socialControllers[e.key]?.text = extra[e.key]?.toString() ?? '';
          }
        }
      }
      final demosResult = await widget.apiClient.fetchArtistDemos(widget.token);
      final mediaData = await widget.apiClient.fetchArtistMediaWithQuota(widget.token);
      final mediaItems = mediaData['items'];
      final used = mediaData['used_bytes'] is int ? mediaData['used_bytes'] as int : 0;
      final quota = mediaData['quota_bytes'] is int ? mediaData['quota_bytes'] as int : 50 * 1024 * 1024;
      final campaignReqs = await widget.apiClient.fetchCampaignRequests(widget.token);
      setState(() {
        dashboard = result;
        demos = demosResult;
        mediaList = mediaItems is List ? mediaItems : [];
        mediaUsedBytes = used;
        mediaQuotaBytes = quota;
        campaignRequests = campaignReqs;
        error = null;
        loading = false;
      });
    } catch (e) {
      final msg = e.toString();
      final isConnectionError = msg.contains('Failed to fetch') ||
          msg.contains('Connection refused') ||
          msg.contains('SocketException') ||
          msg.contains('ClientException');
      setState(() {
        error = isConnectionError
            ? 'Cannot reach server. Please try again later.'
            : msg.replaceFirst('Exception: ', '');
        loading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      savingProfile = true;
      error = null;
    });
    try {
      final extra = <String, dynamic>{
        if (profileWebsiteController.text.trim().isNotEmpty) 'website': profileWebsiteController.text.trim(),
        if (profileFullNameController.text.trim().isNotEmpty) 'full_name': profileFullNameController.text.trim(),
      };
      for (final e in _socialKeys) {
        final v = socialControllers[e.key]?.text.trim() ?? '';
        if (v.isNotEmpty) extra[e.key] = v;
      }
      await widget.apiClient.updateArtistProfile(
        widget.token,
        name: profileNameController.text.trim().isEmpty ? null : profileNameController.text.trim(),
        notes: profileNotesController.text.trim().isEmpty ? null : profileNotesController.text.trim(),
        extra: extra.isEmpty ? null : extra,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => savingProfile = false);
    }
  }

  Future<void> _changePassword() async {
    final current = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        final n = TextEditingController();
        return AlertDialog(
          title: const Text('Change password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: c,
                decoration: const InputDecoration(labelText: 'Current password', border: OutlineInputBorder()),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: n,
                decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder()),
                obscureText: true,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (n.text.length >= 6) Navigator.of(ctx).pop('${c.text}|||${n.text}');
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
    if (current == null || !current.contains('|||')) return;
    final parts = current.split('|||');
    if (parts.length != 2 || parts[1].length < 6) return;
    setState(() {
      changingPassword = true;
      error = null;
    });
    try {
      await widget.apiClient.changePassword(
        widget.token,
        currentPassword: parts[0],
        newPassword: parts[1],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated')));
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => changingPassword = false);
    }
  }

  Future<void> _pickAndUploadRelease() async {
    if (titleController.text.trim().isEmpty) {
      setState(() => error = 'Please enter track title first');
      return;
    }
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.bytes == null || f.bytes!.isEmpty) {
      setState(() => error = 'Could not read file. Please try again.');
      return;
    }
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      await widget.apiClient.uploadRelease(
        token: widget.token,
        title: titleController.text.trim(),
        fileBytes: f.bytes!,
        filename: f.name,
      );
      titleController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploaded')));
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _requestCampaign() async {
    final releases = (dashboard?['releases'] as List<dynamic>? ?? []);
    if (releases.isEmpty) {
      setState(() => error = 'You have no releases yet. Upload music first.');
      return;
    }
    int? selectedReleaseId = releases.isNotEmpty ? (releases.first as Map<String, dynamic>)['id'] as int? : null;
    final messageController = TextEditingController();
    final result = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setDialogState) {
            return AlertDialog(
              title: const Text('Request campaign'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select release:'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: selectedReleaseId,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        for (final r in releases)
                          DropdownMenuItem<int>(
                            value: (r as Map<String, dynamic>)['id'] as int,
                            child: Text((r['title'] as String?) ?? 'Release'),
                          ),
                      ],
                      onChanged: (v) => setDialogState(() => selectedReleaseId = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      decoration: const InputDecoration(
                        labelText: 'Message (optional)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(null), child: const Text('Cancel')),
                FilledButton(
                  onPressed: selectedReleaseId == null ? null : () => Navigator.of(ctx).pop(selectedReleaseId),
                  child: const Text('Send request'),
                ),
              ],
            );
          },
        );
      },
    );
    final message = messageController.text.trim();
    messageController.dispose();
    if (result == null) return;
    selectedReleaseId = result;
    setState(() {
      requestingCampaign = true;
      error = null;
    });
    try {
      await widget.apiClient.createCampaignRequest(
        widget.token,
        releaseId: result,
        message: message.isEmpty ? null : message,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Campaign request sent')),
        );
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => requestingCampaign = false);
    }
  }

  Future<void> _submitDemo() async {
    setState(() {
      submittingDemo = true;
      error = null;
    });
    try {
      List<int>? bytes;
      String filename = 'demo.mp3';
      final result = await FilePicker.platform.pickFiles(withData: true);
      if (result != null && result.files.isNotEmpty) {
        final f = result.files.single;
        if (f.bytes != null && f.bytes!.isNotEmpty) {
          bytes = f.bytes;
          filename = f.name;
        }
      }
      await widget.apiClient.submitArtistDemo(
        widget.token,
        message: demoMessageController.text.trim(),
        fileBytes: bytes,
        filename: filename,
      );
      demoMessageController.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demo submitted')),
        );
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => submittingDemo = false);
    }
  }

  Future<void> _uploadMedia() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.single;
    if (f.bytes == null || f.bytes!.isEmpty) {
      setState(() => error = 'Could not read file.');
      return;
    }
    setState(() {
      uploadingMedia = true;
      error = null;
    });
    try {
      await widget.apiClient.uploadArtistMedia(
        widget.token,
        fileBytes: f.bytes!,
        filename: f.name,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File uploaded to My Media')),
        );
      }
    } catch (e) {
      setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => uploadingMedia = false);
    }
  }

  Future<void> _downloadMedia(int mediaId, String filename) async {
    try {
      final bytes = await widget.apiClient.downloadArtistMedia(widget.token, mediaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded $filename (${bytes.length} bytes)')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _deleteMedia(int mediaId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.apiClient.deleteArtistMedia(widget.token, mediaId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File deleted')));
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final releases = (dashboard?['releases'] as List<dynamic>? ?? const []);
    final tasks = (dashboard?['tasks'] as List<dynamic>? ?? const []);
    final artistMap = dashboard?['artist'] as Map<String, dynamic>?;
    final artistName = artistMap?['name']?.toString() ?? 'Artist';

    return Scaffold(
      appBar: AppBar(
        title: Image.asset(
          'assets/images/zalmanim_logo.png',
          height: 32,
          fit: BoxFit.contain,
        ),
        actions: [
          IconButton(
            icon: const Icon(ZalmanimIcons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await widget.onLogout?.call();
            },
          ),
        ],
      ),
      body: loading
          ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/zalmanim_logo.png',
                        height: 80,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 16),
                      CircularProgressIndicator(color: primary),
                    ],
                  ),
            )
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            error!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(ZalmanimIcons.copy),
                          tooltip: 'Copy error',
                          onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Welcome, $artistName',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: primary,
                            ),
                      ),
                      const SizedBox(height: 20),
                      _sectionTitle(context, 'My profile', primary),
                      _card(
                        context,
                        primary,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: profileNameController,
                              decoration: const InputDecoration(labelText: 'Display name', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: profileFullNameController,
                              decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: profileWebsiteController,
                              decoration: const InputDecoration(labelText: 'Website', border: OutlineInputBorder()),
                              keyboardType: TextInputType.url,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: profileNotesController,
                              decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Social & links (for your Linktree page)',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            ..._socialKeys.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TextField(
                                controller: socialControllers[e.key],
                                decoration: InputDecoration(
                                  labelText: e.value,
                                  border: const OutlineInputBorder(),
                                  hintText: 'https://...',
                                ),
                                keyboardType: TextInputType.url,
                              ),
                            )),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: savingProfile ? null : _saveProfile,
                              child: Text(savingProfile ? 'Saving...' : 'Save profile'),
                            ),
                          ],
                        ),
                      ),
                      if (artistMap != null && artistMap['id'] != null) ...[
                        const SizedBox(height: 12),
                        _card(
                          context,
                          primary,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'My Linktree page',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                '${Uri.base.origin}/l/${artistMap['id']}',
                                style: TextStyle(color: primary, decoration: TextDecoration.underline),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Share this link for a styled page with all your links.',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _card(
                        context,
                        primary,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Change portal password'),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: changingPassword ? null : _changePassword,
                              child: Text(changingPassword ? 'Updating...' : 'Change password'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'Send demo', primary),
                      _card(
                        context,
                        primary,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your name and email are taken from your profile. Add only a message and/or file below.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: demoMessageController,
                              decoration: const InputDecoration(
                                labelText: 'Message (optional)',
                                hintText: 'Describe your demo...',
                                border: OutlineInputBorder(),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: submittingDemo ? null : _submitDemo,
                              child: Text(submittingDemo ? 'Submitting...' : 'Pick file and submit demo'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'My demos', primary),
                      if (demos.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No demos yet.', style: TextStyle(color: Colors.grey[600])),
                        )
                      else
                        ...demos.map((d) {
                          final item = d as Map<String, dynamic>;
                          final msg = item['message']?.toString().trim() ?? '';
                          final title = msg.isEmpty ? 'Demo #${item['id']}' : (msg.length > 50 ? '${msg.substring(0, 50)}...' : msg);
                          return ListTile(
                            leading: Icon(ZalmanimIcons.send, color: primary),
                            title: Text(title),
                            subtitle: Text('Status: ${item['status']}'),
                          );
                        }),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'Upload new music', primary),
                      _card(
                        context,
                        primary,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: titleController,
                              decoration: const InputDecoration(labelText: 'Track title', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: uploading ? null : _pickAndUploadRelease,
                              child: Text(uploading ? 'Uploading...' : 'Select file and upload'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'My releases', primary),
                      if (releases.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No releases yet.', style: TextStyle(color: Colors.grey[600])),
                        )
                      else
                        ...releases.map((r) {
                          final item = r as Map<String, dynamic>;
                          return ListTile(
                            leading: Icon(ZalmanimIcons.music, color: primary),
                            title: Text(item['title'] as String),
                            subtitle: Text('Status: ${item['status']}'),
                          );
                        }),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'Request campaign', primary),
                      _card(
                        context,
                        primary,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ask the label to run a campaign for one of your releases.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: requestingCampaign ? null : _requestCampaign,
                              child: Text(requestingCampaign ? 'Sending...' : 'Request campaign for a release'),
                            ),
                            if (campaignRequests.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Text('My requests', style: TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              ...campaignRequests.map((r) {
                                final item = r as Map<String, dynamic>;
                                return ListTile(
                                  leading: Icon(ZalmanimIcons.campaign, color: primary),
                                  title: Text(item['release_title']?.toString() ?? 'No release'),
                                  subtitle: Text('${item['status']}${(item['message']?.toString().trim() ?? '').isNotEmpty ? ' · ${item['message']}' : ''}'),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'My media', primary),
                      _card(
                        context,
                        primary,
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your media folder (up to 50 MB total). Used: ${(mediaUsedBytes / (1024 * 1024)).toStringAsFixed(1)} / ${(mediaQuotaBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: uploadingMedia
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(ZalmanimIcons.upload),
                              label: Text(uploadingMedia ? 'Uploading...' : 'Upload file'),
                              onPressed: uploadingMedia || mediaUsedBytes >= mediaQuotaBytes ? null : _uploadMedia,
                            ),
                            if (mediaUsedBytes >= mediaQuotaBytes)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  'Quota reached. Delete files to free space.',
                                  style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (mediaList.isNotEmpty)
                        ...mediaList.map((m) {
                          final item = m as Map<String, dynamic>;
                          final id = item['id'] as int;
                          final filename = item['filename'] as String? ?? 'file';
                          final size = item['size_bytes'] as int? ?? 0;
                          return ListTile(
                            leading: Icon(ZalmanimIcons.folder, color: primary),
                            title: Text(filename),
                            subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(ZalmanimIcons.download),
                                  tooltip: 'Download',
                                  onPressed: () => _downloadMedia(id, filename),
                                ),
                                IconButton(
                                  icon: const Icon(ZalmanimIcons.delete),
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteMedia(id),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 24),
                      _sectionTitle(context, 'Tasks', primary),
                      if (tasks.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No tasks.', style: TextStyle(color: Colors.grey[600])),
                        )
                      else
                        ...tasks.map((t) {
                          final item = t as Map<String, dynamic>;
                          return ListTile(
                            leading: Icon(ZalmanimIcons.taskAlt, color: primary),
                            title: Text(item['title'] as String),
                            subtitle: Text('${item['status']} | ${item['details']}'),
                          );
                        }),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, Color primary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: primary,
            ),
      ),
    );
  }

  Widget _card(BuildContext context, Color primary, Widget child) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}
