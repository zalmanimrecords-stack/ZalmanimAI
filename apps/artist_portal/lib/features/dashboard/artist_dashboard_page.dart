import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../core/demo_genre_options.dart';
import '../../core/url_launcher_util.dart';
import '../../core/zalmanim_icons.dart';
import '../../widgets/app_version_badge.dart';

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

const List<MapEntry<String, String>> _minisiteThemes = [
  MapEntry('ocean', 'Ocean'),
  MapEntry('sunset', 'Sunset'),
  MapEntry('mono', 'Mono'),
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
  final minisiteHeadlineController = TextEditingController();
  final minisiteBioController = TextEditingController();
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
  String _minisiteTheme = 'ocean';
  bool _minisiteIsPublic = true;
  List<int> _minisiteGalleryMediaIds = const [];

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
    minisiteHeadlineController.dispose();
    minisiteBioController.dispose();
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

  List<Map<String, dynamic>> _imageMediaItems() {
    return mediaList
        .whereType<Map<String, dynamic>>()
        .where((item) {
          final contentType = (item['content_type'] ?? '').toString().toLowerCase();
          final filename = (item['filename'] ?? '').toString().toLowerCase();
          return contentType.startsWith('image/') ||
              filename.endsWith('.png') ||
              filename.endsWith('.jpg') ||
              filename.endsWith('.jpeg') ||
              filename.endsWith('.webp') ||
              filename.endsWith('.gif');
        })
        .toList(growable: false);
  }

  String _themeLabel(String value) {
    return _minisiteThemes
            .firstWhere(
              (entry) => entry.key == value,
              orElse: () => const MapEntry('ocean', 'Ocean'),
            )
            .value;
  }

  void _setMinisitePublic(bool value) {
    setState(() => _minisiteIsPublic = value);
  }

  void _setMinisiteTheme(String value) {
    setState(() => _minisiteTheme = value);
  }

  void _toggleMinisiteGalleryImage(int mediaId, bool selected) {
    setState(() {
      final next = _minisiteGalleryMediaIds.toList(growable: true);
      if (selected) {
        if (!next.contains(mediaId)) next.add(mediaId);
      } else {
        next.remove(mediaId);
      }
      _minisiteGalleryMediaIds = next;
    });
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
          minisiteHeadlineController.text =
              extra['minisite_headline']?.toString() ?? '';
          minisiteBioController.text =
              extra['minisite_bio']?.toString() ?? '';
          for (final e in _socialKeys) {
            socialControllers[e.key]?.text = extra[e.key]?.toString() ?? '';
          }
          final pid = extra['profile_image_media_id'];
          final lid = extra['logo_media_id'];
          _profileImageMediaId = pid is int ? pid : null;
          _logoMediaId = lid is int ? lid : null;
          final theme = extra['minisite_theme']?.toString().trim().toLowerCase();
          _minisiteTheme = _minisiteThemes.any((e) => e.key == theme)
              ? theme!
              : 'ocean';
          _minisiteIsPublic = extra['minisite_is_public'] != false;
          final rawGallery = extra['minisite_gallery_media_ids'];
          if (rawGallery is List) {
            _minisiteGalleryMediaIds = rawGallery
                .whereType<int>()
                .where((item) => item > 0)
                .toList(growable: false);
          } else {
            _minisiteGalleryMediaIds = const [];
          }
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
        'minisite_theme': _minisiteTheme,
        'minisite_is_public': _minisiteIsPublic,
        'minisite_gallery_media_ids': _minisiteGalleryMediaIds,
        'minisite_headline': minisiteHeadlineController.text.trim(),
        'minisite_bio': minisiteBioController.text.trim(),
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
  Widget build(BuildContext context) => buildArtistDashboardPage(context);
}

extension _ArtistDashboardPageUi on _ArtistDashboardPageState {
  Widget buildArtistDashboardPage(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final compact = _isCompactLayout(context);
    final horizontalPadding = compact ? 16.0 : 20.0;
    final releases = (dashboard?['releases'] as List<dynamic>? ?? const []);
    final tasks = (dashboard?['tasks'] as List<dynamic>? ?? const []);
    final pendingReleases =
        (dashboard?['pending_releases'] as List<dynamic>? ?? const []);
    final artistMap = dashboard?['artist'] as Map<String, dynamic>?;
    final artistName = artistMap?['name']?.toString() ?? 'Artist';

    if (!loading && error == null) {
      return Scaffold(
        appBar: AppBar(
          titleSpacing: compact ? 12 : null,
          title: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Image.asset(
                'assets/images/zalmanim_logo.png',
                height: compact ? 26 : 32,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 4),
              AppVersionBadge(
                tooltipPrefix: 'Artist portal version',
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .onPrimary
                    .withValues(alpha: 0.10),
                borderColor: Theme.of(context)
                    .colorScheme
                    .onPrimary
                    .withValues(alpha: 0.16),
                textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onPrimary
                          .withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
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
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(icon: Icon(Icons.home_outlined), text: 'Home'),
              Tab(icon: Icon(Icons.send_outlined), text: 'Demos'),
              Tab(icon: Icon(Icons.library_music_outlined), text: 'Releases'),
              Tab(icon: Icon(Icons.mail_outline), text: 'Messages'),
              Tab(icon: Icon(Icons.folder_outlined), text: 'Media'),
              Tab(icon: Icon(Icons.person_outline), text: 'Account'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _homeTabChildren(
                context,
                primary: primary,
                artistName: artistName,
                releases: releases,
                tasks: tasks,
                pendingReleases: pendingReleases,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _demosTabChildren(
                context,
                primary: primary,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _releasesTabChildren(
                context,
                primary: primary,
                releases: releases,
                pendingReleases: pendingReleases,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _messagesTabChildren(
                context,
                primary: primary,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _mediaTabChildren(
                context,
                primary: primary,
                artistMap: artistMap,
              ),
            ),
            _tabListView(
              context,
              horizontalPadding: horizontalPadding,
              compact: compact,
              children: _accountTabChildren(
                context,
                primary: primary,
                artistMap: artistMap,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: compact ? 12 : null,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/images/zalmanim_logo.png',
              height: compact ? 26 : 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 4),
            AppVersionBadge(
              tooltipPrefix: 'Artist portal version',
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              backgroundColor:
                  Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.10),
              borderColor:
                  Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.16),
              textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onPrimary
                        .withValues(alpha: 0.92),
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
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
                    padding: EdgeInsets.all(horizontalPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          error!,
                          style: TextStyle(color: Theme.of(context).colorScheme.error),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => Clipboard.setData(ClipboardData(text: error!)),
                          icon: const Icon(ZalmanimIcons.copy),
                          label: const Text('Copy error'),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
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

  Widget _tabListView(
    BuildContext context, {
    required List<Widget> children,
    required double horizontalPadding,
    required bool compact,
  }) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          compact ? 16 : 20,
          horizontalPadding,
          28,
        ),
        children: children,
      ),
    );
  }

  List<Widget> _homeTabChildren(
    BuildContext context, {
    required Color primary,
    required String artistName,
    required List<dynamic> releases,
    required List<dynamic> tasks,
    required List<dynamic> pendingReleases,
  }) {
    return [
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, $artistName',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use the tabs under the logo to switch between Home, Demos, Releases, Messages, Media, and Account.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[700], height: 1.4),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _summaryChip(context, primary, '${releases.length} releases'),
                _summaryChip(context, primary, '${demos.length} demos'),
                _summaryChip(
                    context, primary, '${pendingReleases.length} pending'),
                _summaryChip(context, primary, '${tasks.length} tasks'),
                _summaryChip(
                    context, primary, '${inboxThreads.length} messages'),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionTitle(context, 'Jump to', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open a section without scrolling a long page.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: Icon(Icons.send_outlined, size: 18, color: primary),
                  label: const Text('Demos'),
                  onPressed: () => _tabController.animateTo(1),
                ),
                ActionChip(
                  avatar: Icon(Icons.library_music_outlined,
                      size: 18, color: primary),
                  label: const Text('Releases'),
                  onPressed: () => _tabController.animateTo(2),
                ),
                ActionChip(
                  avatar: Icon(Icons.mail_outline, size: 18, color: primary),
                  label: const Text('Messages'),
                  onPressed: () => _tabController.animateTo(3),
                ),
                ActionChip(
                  avatar: Icon(Icons.folder_outlined, size: 18, color: primary),
                  label: const Text('Media'),
                  onPressed: () => _tabController.animateTo(4),
                ),
                ActionChip(
                  avatar: Icon(Icons.person_outline, size: 18, color: primary),
                  label: const Text('Account'),
                  onPressed: () => _tabController.animateTo(5),
                ),
              ],
            ),
            if (pendingReleases.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'You have ${pendingReleases.length} pending release'
                '${pendingReleases.length == 1 ? '' : 's'} ? review them in the Releases tab.',
                style: TextStyle(fontSize: 13, color: Colors.grey[800]),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => _tabController.animateTo(2),
                  icon: const Icon(Icons.library_music_outlined, size: 18),
                  label: const Text('Open Releases'),
                ),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'Tasks', primary),
      if (tasks.isEmpty)
        _emptyStateCard(context, primary, 'No tasks right now.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final t in tasks) ...[
                _taskTile(context, primary, t as Map<String, dynamic>),
                if (t != tasks.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'Campaign requests', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ask the label to run a campaign for one of your releases.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: requestingCampaign ? null : _requestCampaign,
              child: Text(
                requestingCampaign
                    ? 'Sending...'
                    : 'Request campaign for a release',
              ),
            ),
            if (campaignRequests.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'My requests',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final request in campaignRequests)
                _campaignRequestTile(
                  context,
                  primary,
                  request as Map<String, dynamic>,
                ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _demosTabChildren(
    BuildContext context, {
    required Color primary,
  }) {
    return [
      _sectionTitle(context, 'Send demo', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your name and email are taken from your profile. Enter track name and musical style, then add a message or file.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: demoTrackNameController,
              decoration: const InputDecoration(
                labelText: 'Track name',
                hintText: 'Name of the track',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedDemoGenre,
              decoration: const InputDecoration(
                labelText: 'Musical style',
                border: OutlineInputBorder(),
              ),
              hint: const Text('Select style'),
              items: [
                for (final group in demoGenreGroups) ...[
                  DropdownMenuItem<String>(
                    enabled: false,
                    value: '__$group',
                    child: Text(
                      group,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (final option
                      in demoGenreOptions.where((item) => item.group == group))
                    DropdownMenuItem<String>(
                      value: option.value,
                      child: Text(option.value),
                    ),
                ],
              ],
              onChanged: (value) =>
                  setState(() => _selectedDemoGenre = value), // ignore: invalid_use_of_protected_member
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
              child: Text(
                submittingDemo
                    ? 'Submitting...'
                    : 'Pick file and submit demo',
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'My demos', primary),
      if (demos.isEmpty)
        _emptyStateCard(context, primary, 'No demos yet.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final d in demos) ...[
                _demoTile(context, primary, d as Map<String, dynamic>),
                if (d != demos.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _releasesTabChildren(
    BuildContext context, {
    required Color primary,
    required List<dynamic> releases,
    required List<dynamic> pendingReleases,
  }) {
    return [
      _sectionTitle(context, 'Pending releases', primary),
      if (pendingReleases.isEmpty)
        _emptyStateCard(context, primary, 'No pending releases right now.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final r in pendingReleases) ...[
                _pendingReleaseTile(context, primary, r as Map<String, dynamic>),
                if (r != pendingReleases.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'My releases', primary),
      if (releases.isEmpty)
        _emptyStateCard(context, primary, 'No releases yet.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final r in releases) ...[
                _releaseTile(context, primary, r as Map<String, dynamic>),
                if (r != releases.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _messagesTabChildren(
    BuildContext context, {
    required Color primary,
  }) {
    return [
      _sectionTitle(context, 'Message the label', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send a message to the label. You will see replies here and can continue the conversation.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageToLabelController,
              decoration: const InputDecoration(
                labelText: 'Your message',
                hintText:
                    'Ideas, requests, complaints and any other topic are welcome. You are invited to contact us.',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: sendingMessageToLabel ? null : _sendMessageToLabel,
              child: sendingMessageToLabel
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Send message'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _sectionTitle(context, 'Your messages', primary),
      if (inboxThreads.isEmpty)
        _emptyStateCard(context, primary, 'No messages yet.')
      else
        _card(
          context,
          primary,
          Column(
            children: [
              for (final t in inboxThreads) ...[
                _inboxThreadTile(context, primary, t as Map<String, dynamic>),
                if (t != inboxThreads.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _mediaTabChildren(
    BuildContext context, {
    required Color primary,
    required Map<String, dynamic>? artistMap,
  }) {
    return [
      _sectionTitle(context, 'My media', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your media folder (up to 50 MB total). Used: ${(mediaUsedBytes / (1024 * 1024)).toStringAsFixed(1)} / ${(mediaQuotaBytes / (1024 * 1024)).toStringAsFixed(0)} MB.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: uploadingMedia
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(ZalmanimIcons.upload),
              label: Text(
                uploadingMedia ? 'Uploading...' : 'Upload image or file',
              ),
              onPressed: uploadingMedia || mediaUsedBytes >= mediaQuotaBytes
                  ? null
                  : _uploadMedia,
            ),
            if (mediaUsedBytes >= mediaQuotaBytes)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Quota reached. Delete files to free space.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      if (mediaList.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _emptyStateCard(
            context,
            primary,
            'No media uploaded yet.',
          ),
        )
      else ...[
        const SizedBox(height: 12),
        _card(
          context,
          primary,
          Column(
            children: [
              for (final m in mediaList) ...[
                _mediaTile(context, primary, m as Map<String, dynamic>),
                if (m != mediaList.last) const Divider(height: 20),
              ],
            ],
          ),
        ),
      ],
      if (artistMap != null && artistMap['id'] != null) ...[
        const SizedBox(height: 24),
        _sectionTitle(context, 'Minisite images', primary),
        _card(
          context,
          primary,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pick a profile image and logo from your uploads (shown on your public minisite).',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              _LinktreeImageRow(
                label: 'Profile image',
                currentMediaId: _profileImageMediaId,
                mediaList: mediaList,
                onSet: _setProfileImageForLinktree,
              ),
              const SizedBox(height: 8),
              _LinktreeImageRow(
                label: 'Logo',
                currentMediaId: _logoMediaId,
                mediaList: mediaList,
                onSet: _setLogoForLinktree,
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 32),
    ];
  }

  List<Widget> _accountTabChildren(
    BuildContext context, {
    required Color primary,
    required Map<String, dynamic>? artistMap,
  }) {
    return [
      _sectionTitle(context, 'My profile', primary),
      _card(
        context,
        primary,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: profileNameController,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: profileFullNameController,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: profileWebsiteController,
              decoration: const InputDecoration(
                labelText: 'Website',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: profileNotesController,
              decoration: const InputDecoration(
                labelText: 'Internal notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            const Text(
              'Social & links (for your minisite)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ..._socialKeys.map(
              (e) => Padding(
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
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: savingProfile ? null : _saveProfile,
              child: Text(savingProfile ? 'Saving...' : 'Save profile'),
            ),
          ],
        ),
      ),
      if (artistMap != null && artistMap['id'] != null) ...[
        const SizedBox(height: 24),
        _sectionTitle(context, 'My minisite', primary),
        _card(
          context,
          primary,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Build a small public page for your artist project.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public share page'),
                subtitle: const Text(
                  'Turn this on to let fans, curators, and social followers open your minisite.',
                ),
                value: _minisiteIsPublic,
                onChanged: _setMinisitePublic,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _minisiteTheme,
                decoration: const InputDecoration(
                  labelText: 'Theme',
                  border: OutlineInputBorder(),
                ),
                items: _minisiteThemes
                    .map(
                      (entry) => DropdownMenuItem<String>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null || value.isEmpty) return;
                  _setMinisiteTheme(value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minisiteHeadlineController,
                decoration: const InputDecoration(
                  labelText: 'Headline',
                  hintText: 'Melodic techno producer from Tel Aviv',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: minisiteBioController,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell people who you are, what you release, and what they should listen to.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              Text(
                'Brand images',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your main profile image and optional logo from your uploads.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              _LinktreeImageRow(
                label: 'Profile image',
                currentMediaId: _profileImageMediaId,
                mediaList: _imageMediaItems(),
                onSet: _setProfileImageForLinktree,
              ),
              const SizedBox(height: 8),
              _LinktreeImageRow(
                label: 'Logo',
                currentMediaId: _logoMediaId,
                mediaList: _imageMediaItems(),
                onSet: _setLogoForLinktree,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Gallery images',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: uploadingMedia ? null : _uploadMedia,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(uploadingMedia ? 'Uploading...' : 'Upload image'),
                  ),
                ],
              ),
              Text(
                'Pick a few images to give your minisite more personality.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 8),
              if (_imageMediaItems().isEmpty)
                Text(
                  'No image uploads yet. Upload artwork, press shots, or brand visuals to build the page.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _imageMediaItems().map((item) {
                    final mediaId = item['id'] as int?;
                    if (mediaId == null) return const SizedBox.shrink();
                    final selected = _minisiteGalleryMediaIds.contains(mediaId);
                    return FilterChip(
                      selected: selected,
                      label: Text((item['filename'] ?? 'image').toString()),
                      onSelected: (value) => _toggleMinisiteGalleryImage(mediaId, value),
                    );
                  }).toList(growable: false),
                ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final link = _linktreeUrlFor(artistMap['id']);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share link',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _minisiteIsPublic
                            ? () => openUrlOrCopy(context, link)
                            : null,
                        child: _isCompactLayout(context)
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(
                                    link,
                                    style: TextStyle(
                                      color: _minisiteIsPublic ? primary : Colors.grey[500],
                                      decoration: _minisiteIsPublic
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Icon(
                                    Icons.open_in_new,
                                    size: 18,
                                    color: _minisiteIsPublic ? primary : Colors.grey[500],
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      link,
                                      style: TextStyle(
                                        color: _minisiteIsPublic ? primary : Colors.grey[500],
                                        decoration: _minisiteIsPublic
                                            ? TextDecoration.underline
                                            : TextDecoration.none,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.open_in_new,
                                    size: 18,
                                    color: _minisiteIsPublic ? primary : Colors.grey[500],
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _minisiteIsPublic
                            ? 'Theme: ${_themeLabel(_minisiteTheme)}. Save your profile, then share this page anywhere.'
                            : 'Your minisite is hidden right now. Turn on Public share page and save to publish it.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
      const SizedBox(height: 24),
      _sectionTitle(context, 'Security', primary),
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
      const SizedBox(height: 32),
    ];
  }

  Widget _emptyStateCard(BuildContext context, Color primary, String text) {
    return _card(
      context,
      primary,
      Text(
        text,
        style: TextStyle(color: Colors.grey[600]),
      ),
    );
  }

  Widget _campaignRequestTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final message = (item['message']?.toString().trim() ?? '');
    final subtitle = message.isEmpty
        ? item['status']?.toString() ?? ''
        : '${item['status']} - $message';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.campaign, color: primary),
      title: Text(item['release_title']?.toString() ?? 'No release'),
      subtitle: Text(subtitle),
    );
  }

  Widget _inboxThreadTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> thread,
  ) {
    final id = thread['id'] as int? ?? 0;
    final preview = (thread['last_message_preview'] ?? '').toString();
    final updated =
        (thread['last_message_at'] ?? thread['updated_at'] ?? '').toString();
    final hasReply = thread['has_label_reply'] == true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        hasReply ? Icons.mark_email_read : Icons.mail_outline,
        color: primary,
      ),
      title: Text(
        preview.isEmpty
            ? 'No subject'
            : preview.length > 60
                ? '${preview.substring(0, 60)}...'
                : preview,
        style: const TextStyle(fontSize: 14),
      ),
      subtitle: Text(
        hasReply ? 'Replied - $updated' : updated,
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ),
      onTap: () => _openInboxThread(id),
    );
  }

  Widget _demoTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final msg = item['message']?.toString().trim() ?? '';
    final title = msg.isEmpty
        ? 'Demo #${item['id']}'
        : (msg.length > 50 ? '${msg.substring(0, 50)}...' : msg);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.send, color: primary),
      title: Text(title),
      subtitle: Text('Status: ${item['status']}'),
    );
  }

  Widget _pendingReleaseTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final comments = item['comments'] as List<dynamic>? ?? const [];
    final images = item['image_options'] as List<dynamic>? ?? const [];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.music, color: primary),
      title: Text((item['release_title'] ?? 'Pending release').toString()),
      subtitle: Text(
        'Status: ${(item['status'] ?? 'pending').toString()} - ${comments.length} message(s) - ${images.length} image option(s)',
      ),
      trailing: OutlinedButton(
        onPressed: () => _openPendingReleaseDialog(item),
        child: const Text('Open release page'),
      ),
    );
  }

  Widget _releaseTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.music, color: primary),
      title: Text(item['title'] as String),
      subtitle: Text('Status: ${item['status']}'),
    );
  }

  Widget _taskTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(ZalmanimIcons.taskAlt, color: primary),
      title: Text(item['title'] as String),
      subtitle: Text('${item['status']} | ${item['details']}'),
    );
  }

  Widget _mediaTile(
    BuildContext context,
    Color primary,
    Map<String, dynamic> item,
  ) {
    final id = item['id'] as int;
    final filename = item['filename'] as String? ?? 'file';
    final size = item['size_bytes'] as int? ?? 0;
    return ListTile(
      contentPadding: EdgeInsets.zero,
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
  }

  Widget _summaryChip(BuildContext context, Color primary, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _card(BuildContext context, Color primary, Widget child) {
    final compact = _isCompactLayout(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 16 : 12),
        side: BorderSide(color: primary.withValues(alpha: 0.3), width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: child,
      ),
    );
  }
}

/// Row for choosing a Linktree profile image or logo from the artist's media.
class _LinktreeImageRow extends StatelessWidget {
  const _LinktreeImageRow({
    required this.label,
    required this.currentMediaId,
    required this.mediaList,
    required this.onSet,
  });

  final String label;
  final int? currentMediaId;
  final List<dynamic> mediaList;
  final void Function(int mediaId) onSet;

  String? _filenameForId(int? id) {
    if (id == null) return null;
    for (final m in mediaList) {
      if (m is Map && (m['id'] as int?) == id) return m['filename']?.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentName = _filenameForId(currentMediaId);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        final button = TextButton.icon(
          onPressed: mediaList.isEmpty
              ? null
              : () async {
                  final id = await showDialog<int>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Set $label'),
                      content: SizedBox(
                        width: 320,
                        child: mediaList.isEmpty
                            ? const Text('Upload an image in My media first.')
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: mediaList.length,
                                itemBuilder: (_, i) {
                                  final m = mediaList[i] as Map<String, dynamic>;
                                  final mid = m['id'] as int?;
                                  final fn = m['filename']?.toString() ?? 'file';
                                  return ListTile(
                                    title: Text(fn),
                                    onTap: () => Navigator.of(ctx).pop(mid),
                                  );
                                },
                              ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  );
                  if (id != null) onSet(id);
                },
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: const Text('Set from my media'),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label: ${currentName ?? 'Not set'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
              const SizedBox(height: 6),
              button,
            ],
          );
        }
        return Row(
          children: [
            Expanded(
              child: Text(
                '$label: ${currentName ?? 'Not set'}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ),
            button,
          ],
        );
      },
    );
  }
}

