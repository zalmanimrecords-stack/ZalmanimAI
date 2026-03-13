import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/session.dart';
import '../account/user_settings_sheet.dart';
import '../../widgets/api_connection_indicator.dart';

class ArtistDashboardPage extends StatefulWidget {
  const ArtistDashboardPage({
    super.key,
    required this.apiClient,
    required this.session,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final AuthSession session;
  final Future<void> Function() onLogout;
  String get token => session.token;

  @override
  State<ArtistDashboardPage> createState() => _ArtistDashboardPageState();
}

class _ArtistDashboardPageState extends State<ArtistDashboardPage> {
  final titleController = TextEditingController();
  final demoMessageController = TextEditingController();
  final profileNameController = TextEditingController();
  final profileNotesController = TextEditingController();
  final profileWebsiteController = TextEditingController();
  final profileFullNameController = TextEditingController();

  bool loading = true;
  bool uploading = false;
  bool savingProfile = false;
  bool submittingDemo = false;
  bool uploadingMedia = false;
  String? error;
  Map<String, dynamic>? dashboard;
  List<dynamic> demos = [];
  List<dynamic> mediaList = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _openUserSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (context) => UserSettingsSheet(
        apiClient: widget.apiClient,
        session: widget.session,
        onLogout: widget.onLogout,
        onRefresh: _load,
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will return to the login screen on this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onLogout();
    }
  }

  @override
  void dispose() {
    titleController.dispose();
    demoMessageController.dispose();
    profileNameController.dispose();
    profileNotesController.dispose();
    profileWebsiteController.dispose();
    profileFullNameController.dispose();
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
        }
      }
      final demosResult = await widget.apiClient.fetchArtistDemos(widget.token);
      final mediaResult = await widget.apiClient.fetchArtistMedia(widget.token);
      setState(() {
        dashboard = result;
        demos = demosResult;
        mediaList = mediaResult;
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
            ? 'Cannot reach API at ${widget.apiClient.baseUrl}. Backend running?'
            : msg;
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
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => savingProfile = false);
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
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
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
      setState(() => error = e.toString());
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
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => uploadingMedia = false);
    }
  }

  Future<void> _downloadMedia(int mediaId, String filename) async {
    try {
      final bytes = await widget.apiClient.downloadArtistMedia(widget.token, mediaId);
      // On web we could trigger a download; on mobile use a file saver.
      // For simplicity show a snackbar; full file save would use path_provider + File.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded $filename (${bytes.length} bytes)')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString());
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
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final releases = (dashboard?['releases'] as List<dynamic>? ?? const []);
    final tasks = (dashboard?['tasks'] as List<dynamic>? ?? const []);
    final artistMap = dashboard?['artist'] as Map<String, dynamic>?;
    final artistName = artistMap?['name']?.toString() ?? 'Artist';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Artist Portal'),
        actions: [
          ApiConnectionIndicator(apiClient: widget.apiClient, onConnectionRestored: _load),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'User details',
            onPressed: _openUserSettings,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
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
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy),
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
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'Welcome, $artistName',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 16),

                      // My profile
                      _sectionTitle('My profile'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: profileNameController,
                                decoration: const InputDecoration(labelText: 'Display name'),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: profileFullNameController,
                                decoration: const InputDecoration(labelText: 'Full name'),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: profileWebsiteController,
                                decoration: const InputDecoration(labelText: 'Website'),
                                keyboardType: TextInputType.url,
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: profileNotesController,
                                decoration: const InputDecoration(labelText: 'Notes'),
                                maxLines: 2,
                              ),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: savingProfile ? null : _saveProfile,
                                child: Text(savingProfile ? 'Saving...' : 'Save profile'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Send demo
                      _sectionTitle('Send demo'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Submit a demo with an optional message and file. The label will review it.',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: demoMessageController,
                                decoration: const InputDecoration(
                                  labelText: 'Message (optional)',
                                  hintText: 'Describe your demo...',
                                ),
                                maxLines: 2,
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: submittingDemo ? null : _submitDemo,
                                child: Text(submittingDemo ? 'Submitting...' : 'Pick file and submit demo'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // My demos
                      _sectionTitle('My demos'),
                      if (demos.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No demos yet.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ...demos.map((d) {
                          final item = d as Map<String, dynamic>;
                          return ListTile(
                            leading: const Icon(Icons.send),
                            title: Text(
                              () {
                                final msg = item['message']?.toString().trim() ?? '';
                                if (msg.isEmpty) return 'Demo #${item['id']}';
                                return msg.length > 50 ? '${msg.substring(0, 50)}...' : msg;
                              }(),
                            ),
                            subtitle: Text('Status: ${item['status']}'),
                          );
                        }),
                      const SizedBox(height: 20),

                      // Upload new music (release)
                      _sectionTitle('Upload new music'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: titleController,
                                decoration: const InputDecoration(labelText: 'Track title'),
                              ),
                              const SizedBox(height: 8),
                              FilledButton(
                                onPressed: uploading ? null : _pickAndUploadRelease,
                                child: Text(uploading ? 'Uploading...' : 'Select file and upload'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // My releases
                      _sectionTitle('My releases'),
                      if (releases.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No releases yet.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ...releases.map((r) {
                          final item = r as Map<String, dynamic>;
                          return ListTile(
                            leading: const Icon(Icons.music_note),
                            title: Text(item['title'] as String),
                            subtitle: Text('Status: ${item['status']}'),
                          );
                        }),
                      const SizedBox(height: 20),

                      // My media
                      _sectionTitle('My media'),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your media folder for files you want to keep here.',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                icon: uploadingMedia
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.upload_file),
                                label: Text(uploadingMedia ? 'Uploading...' : 'Upload file'),
                                onPressed: uploadingMedia ? null : _uploadMedia,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (mediaList.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(left: 16, top: 4),
                          child: Text('No files yet.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ...mediaList.map((m) {
                          final item = m as Map<String, dynamic>;
                          final id = item['id'] as int;
                          final filename = item['filename'] as String? ?? 'file';
                          final size = item['size_bytes'] as int? ?? 0;
                          return ListTile(
                            leading: const Icon(Icons.folder),
                            title: Text(filename),
                            subtitle: Text('${(size / 1024).toStringAsFixed(1)} KB'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.download),
                                  tooltip: 'Download',
                                  onPressed: () => _downloadMedia(id, filename),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'Delete',
                                  onPressed: () => _deleteMedia(id),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 20),

                      // System tasks
                      _sectionTitle('System tasks'),
                      if (tasks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('No tasks.', style: TextStyle(color: Colors.grey)),
                        )
                      else
                        ...tasks.map((t) {
                          final item = t as Map<String, dynamic>;
                          return ListTile(
                            leading: const Icon(Icons.task_alt),
                            title: Text(item['title'] as String),
                            subtitle: Text('${item['status']} | ${item['details']}'),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}
