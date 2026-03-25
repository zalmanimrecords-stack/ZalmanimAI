import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/demo_genre_options.dart';
import '../../core/url_launcher_util.dart';
import '../../core/zalmanim_icons.dart';
import '../../widgets/app_version_badge.dart';
part 'artist_dashboard_page_ui.dart';


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

class _ArtistDashboardPageState extends State<ArtistDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final demoTrackNameController = TextEditingController();
  String? _selectedDemoGenre;
  final demoMessageController = TextEditingController();
  final profileNameController = TextEditingController();
  final profileNotesController = TextEditingController();
  final profileWebsiteController = TextEditingController();
  final profileFullNameController = TextEditingController();
  final messageToLabelController = TextEditingController();
  final Map<String, TextEditingController> socialControllers = {};

  bool loading = true;
  bool savingProfile = false;
  bool changingPassword = false;
  bool submittingDemo = false;
  bool uploadingMedia = false;
  bool requestingCampaign = false;
  bool sendingMessageToLabel = false;
  String? error;
  Map<String, dynamic>? dashboard;
  List<dynamic> demos = [];
  List<dynamic> mediaList = [];
  int mediaUsedBytes = 0;
  int mediaQuotaBytes = 50 * 1024 * 1024;
  List<dynamic> campaignRequests = [];
  List<dynamic> inboxThreads = [];
  int? _profileImageMediaId;
  int? _logoMediaId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    for (final e in _socialKeys) {
      socialControllers[e.key] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    demoTrackNameController.dispose();
    demoMessageController.dispose();
    profileNameController.dispose();
    profileNotesController.dispose();
    profileWebsiteController.dispose();
    profileFullNameController.dispose();
    messageToLabelController.dispose();
    for (final c in socialControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isCompactLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 720;

  String _portalBaseUrl() {
    final configured = AppConfig.publicBaseUrl.trim();
    if (configured.isNotEmpty) {
      return configured.endsWith('/')
          ? configured.substring(0, configured.length - 1)
          : configured;
    }
    final base = Uri.base;
    if (base.hasScheme &&
        (base.scheme == 'http' || base.scheme == 'https') &&
        base.host.isNotEmpty) {
      return base.origin;
    }
    return 'https://artists.zalmanim.com';
  }

  String _linktreeUrlFor(dynamic artistId) =>
      '${_portalBaseUrl()}/#/l/$artistId';

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
          final pid = extra['profile_image_media_id'];
          final lid = extra['logo_media_id'];
          _profileImageMediaId = pid is int ? pid : null;
          _logoMediaId = lid is int ? lid : null;
        }
      }
      final demosResult = await widget.apiClient.fetchArtistDemos(widget.token);
      final mediaData = await widget.apiClient.fetchArtistMediaWithQuota(widget.token);
      final mediaItems = mediaData['items'];
      final used = mediaData['used_bytes'] is int ? mediaData['used_bytes'] as int : 0;
      final quota = mediaData['quota_bytes'] is int ? mediaData['quota_bytes'] as int : 50 * 1024 * 1024;
      final campaignReqs = await widget.apiClient.fetchCampaignRequests(widget.token);
      final inbox = await widget.apiClient.fetchMyInboxThreads(widget.token);
      setState(() {
        dashboard = result;
        demos = demosResult;
        mediaList = mediaItems is List ? mediaItems : [];
        mediaUsedBytes = used;
        mediaQuotaBytes = quota;
        campaignRequests = campaignReqs;
        inboxThreads = inbox;
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

  Future<void> _setProfileImageForLinktree(int mediaId) async {
    try {
      await widget.apiClient.updateArtistProfile(
        widget.token,
        profileImageMediaId: mediaId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile image set for Linktree')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: SelectableText(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _setLogoForLinktree(int mediaId) async {
    try {
      await widget.apiClient.updateArtistProfile(
        widget.token,
        logoMediaId: mediaId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo set for Linktree')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: SelectableText(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
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

  Future<void> _requestCampaign() async {
    final releases = (dashboard?['releases'] as List<dynamic>? ?? []);
    if (releases.isEmpty) {
      setState(() => error = 'You have no releases yet.');
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
    final trackName = demoTrackNameController.text.trim();
    final musicalStyle = _selectedDemoGenre?.trim() ?? '';
    if (trackName.isEmpty) {
      setState(() => error = 'Track name is required');
      return;
    }
    if (musicalStyle.isEmpty) {
      setState(() => error = 'Musical style is required');
      return;
    }
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
        trackName: trackName,
        musicalStyle: musicalStyle,
        message: demoMessageController.text.trim(),
        fileBytes: bytes,
        filename: filename,
      );
      demoTrackNameController.clear();
      setState(() => _selectedDemoGenre = null);
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
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.any,
    );
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

  Future<void> _sendMessageToLabel() async {
    final body = messageToLabelController.text.trim();
    if (body.isEmpty) {
      setState(() => error = 'Please enter a message.');
      return;
    }
    setState(() {
      sendingMessageToLabel = true;
      error = null;
    });
    try {
      await widget.apiClient.sendMessageToLabel(widget.token, body);
      messageToLabelController.clear();
      await _load();
      if (mounted) {
        setState(() => sendingMessageToLabel = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent to the label.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          sendingMessageToLabel = false;
          error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _openInboxThread(int threadId) async {
    try {
      final thread = await widget.apiClient.fetchInboxThread(widget.token, threadId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final messages = thread['messages'] as List<dynamic>? ?? [];
          return AlertDialog(
            title: const Text('Your messages'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final m in messages) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (m['sender'] ?? '').toString() == 'label' ? 'Label' : 'You',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: (m['sender'] ?? '').toString() == 'label'
                                  ? Theme.of(ctx).colorScheme.primary
                                  : Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 4),
                          SelectableText((m['body'] ?? '').toString()),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(e.toString().replaceFirst('Exception: ', '')),
            action: SnackBarAction(
              label: 'Copy',
              onPressed: () => Clipboard.setData(ClipboardData(text: e.toString())),
            ),
          ),
        );
      }
    }
  }

  String _pendingReleaseValue(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'Yes' : 'No';
    if (value is Iterable) {
      return value.map((item) => item?.toString() ?? '').join(', ');
    }
      return value.toString().trim();
  }

  String _pendingReleaseLabel(String key) {
    const labels = <String, String>{
      'artist_name': 'Artist name',
      'artist_email': 'Artist email',
      'artist_brand': 'Artist brand',
      'full_name': 'Full name',
      'created_at': 'Submitted',
      'updated_at': 'Updated',
      'track_title': 'Track title',
      'catalog_number': 'Catalog number',
      'release_number': 'Release number',
      'release_date': 'Release date',
      'wav_download_url': 'WAV download link',
      'musical_style': 'Musical style',
      'genre': 'Genre',
      'marketing_text': 'Marketing text',
      'release_story': 'Story / meaning',
      'notes': 'Notes',
      'mastering_required': 'Mastering required',
      'mastering_headroom_confirmed': '6 dB headroom confirmed',
    };
    return labels[key] ??
        key
            .split('_')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ');
  }

  Map<String, dynamic> _pendingReleaseMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Widget _pendingReleaseField(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final isLink = _isHttpUrl(value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            '$label: $value',
            style: const TextStyle(height: 1.35),
          ),
          if (isLink)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OutlinedButton.icon(
                onPressed: () => openUrlOrCopy(context, value),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open link'),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _pendingReleaseFieldsFromMap(
    BuildContext context,
    Map<String, dynamic> source, {
    Set<String> excludedKeys = const <String>{},
  }) {
    final widgets = <Widget>[];
    for (final entry in source.entries) {
      if (excludedKeys.contains(entry.key)) continue;
      final value = _pendingReleaseValue(entry.value);
      if (value.isEmpty) continue;
      widgets.add(
        _pendingReleaseField(
          context,
          label: _pendingReleaseLabel(entry.key),
          value: value,
        ),
      );
    }
    return widgets;
  }

  Future<void> _selectPendingReleaseImage(
      Map<String, dynamic> item, String imageId) async {
    try {
      await widget.apiClient.selectPendingReleaseImage(
        widget.token,
        pendingReleaseId: item['id'] as int,
        imageId: imageId,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image selection updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _togglePendingReleaseNotifications(
      Map<String, dynamic> item, bool muted) async {
    try {
      await widget.apiClient.updatePendingReleaseNotifications(
        widget.token,
        pendingReleaseId: item['id'] as int,
        notificationsMuted: muted,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              muted
                  ? 'Further release update emails muted'
                  : 'Release update emails enabled',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _addPendingReleaseComment(Map<String, dynamic> item) async {
    final controller = TextEditingController();
    try {
      final body = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Add message to release'),
          content: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Message',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Post'),
            ),
          ],
        ),
      );
      if (body == null || body.trim().isEmpty) return;
      await widget.apiClient.addPendingReleaseComment(
        widget.token,
        pendingReleaseId: item['id'] as int,
        body: body.trim(),
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message posted to release')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openPendingReleaseDialog(Map<String, dynamic> item) async {
    if (!mounted) return;
    var detail = item;
    final pendingReleaseId = item['id'];
    if (pendingReleaseId is int) {
      try {
        detail = await widget.apiClient.fetchPendingReleaseDetail(
          widget.token,
          pendingReleaseId,
        );
      } catch (_) {}
    }
    if (!context.mounted) return;
    final pageContext = context;
    final releaseData = _pendingReleaseMap(detail['release_data']);
    final artistData = _pendingReleaseMap(detail['artist_data']);
    final comments = detail['comments'] as List<dynamic>? ?? const [];
    final imageOptions = detail['image_options'] as List<dynamic>? ?? const [];
    final selectedImageId = (detail['selected_image_id'] ?? '').toString();
    final notificationsMuted = detail['notifications_muted'] == true;
    final overviewFields = <Widget>[
      if (_pendingReleaseValue(detail['artist_name']).isNotEmpty)
        _pendingReleaseField(
          pageContext,
          label: 'Artist name',
          value: _pendingReleaseValue(detail['artist_name']),
        ),
      if (_pendingReleaseValue(detail['artist_email']).isNotEmpty)
        _pendingReleaseField(
          pageContext,
          label: 'Artist email',
          value: _pendingReleaseValue(detail['artist_email']),
        ),
      if (_pendingReleaseValue(detail['created_at']).isNotEmpty)
        _pendingReleaseField(
          pageContext,
          label: 'Submitted',
          value: _pendingReleaseValue(detail['created_at']),
        ),
    ];
    final artistFields = _pendingReleaseFieldsFromMap(pageContext, artistData);
    final releaseFields = _pendingReleaseFieldsFromMap(
      pageContext,
      releaseData,
      excludedKeys: const <String>{
        'image_options',
        'selected_image_id',
        'notifications_muted',
      },
    );
    final imageCards = imageOptions.map((rawImage) {
      final image = _pendingReleaseMap(rawImage);
      if (image.isEmpty) return const SizedBox.shrink();
      final imageId = (image['id'] ?? '').toString();
      final imageUrl = (image['url'] ?? '').toString();
      final isSelected = imageId == selectedImageId;
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  widget.apiClient.resolveMediaUrl(imageUrl),
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Text('Could not preview image'),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              (image['filename'] ?? 'Image').toString(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Current selection',
                  style: TextStyle(
                    color: Theme.of(pageContext).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: isSelected
                  ? null
                  : () async {
                      Navigator.of(pageContext).pop();
                      await _selectPendingReleaseImage(detail, imageId);
                    },
              icon: const Icon(Icons.check_circle_outline),
              label: Text(isSelected ? 'Selected' : 'Choose this image'),
            ),
          ],
        ),
      );
    }).toList();
    final commentCards = comments.map((rawComment) {
      final comment = _pendingReleaseMap(rawComment);
      if (comment.isEmpty) return const SizedBox.shrink();
      final sender = (comment['sender'] ?? '').toString() == 'artist' ? 'You' : 'Label';
      final createdAt = (comment['created_at'] ?? '').toString();
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              createdAt.isEmpty ? sender : '$sender - $createdAt',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text((comment['body'] ?? '').toString()),
          ],
        ),
      );
    }).toList();

    await showDialog<void>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text((detail['release_title'] ?? 'Pending release').toString()),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Status: ${(detail['status'] ?? 'pending').toString()}',
                  style: TextStyle(color: Colors.grey[700]),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mute update emails'),
                  subtitle: const Text(
                    'Turn this on if you do not want more emails for changes on this release page.',
                  ),
                  value: notificationsMuted,
                  onChanged: (value) async {
                    Navigator.of(dialogContext).pop();
                    await _togglePendingReleaseNotifications(detail, value);
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Overview',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                ...overviewFields,
                if (artistFields.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Artist details',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  ...artistFields,
                ],
                const SizedBox(height: 8),
                const Text(
                  'Release images',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 8),
                if (imageCards.where((widget) => widget is! SizedBox).isEmpty)
                  Text(
                    'No image options yet. Once the label uploads artwork here, you will be able to choose your preferred image.',
                    style: TextStyle(color: Colors.grey[600]),
                  )
                else
                  ...imageCards,
                if (releaseFields.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Release details',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  ...releaseFields,
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Release forum',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(dialogContext).pop();
                        await _addPendingReleaseComment(detail);
                      },
                      icon: const Icon(Icons.forum_outlined),
                      label: const Text('Add message'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (commentCards.where((widget) => widget is! SizedBox).isEmpty)
                  Text(
                    'No messages yet.',
                    style: TextStyle(color: Colors.grey[600]),
                  )
                else
                  ...commentCards,
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      buildArtistDashboardPage(this, context);
}
