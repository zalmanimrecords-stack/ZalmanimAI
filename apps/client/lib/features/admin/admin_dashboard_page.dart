import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api_client.dart';
import 'file_download.dart';
import '../../core/session.dart';
import '../../core/session_storage.dart';
import '../../core/zalmanim_icons.dart';
import '../account/user_settings_sheet.dart';
import '../../widgets/ambient_underwater_shell.dart';
import '../../widgets/app_version_badge.dart';
import '../../widgets/api_connection_indicator.dart';
import 'admin_dashboard_delegate.dart';
import 'tabs/artists_tab.dart';
import 'tabs/audience_tab.dart';
import 'tabs/campaigns_section_tab.dart';
import 'tabs/demos_tab.dart';
import 'tabs/inbox_tab.dart';
import 'tabs/releases_section_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/settings_tab.dart';
import 'tabs/signed_in_artists_report_dialog.dart';

part 'admin_dashboard_page_widgets.dart';

// Default subject/body for artist reminder emails (used by Reports > Artist reminders).
const String _defaultReminderSubject =
    'Checking in - do you have new music for us?';
const String _defaultReminderBody = r'''Hi {name},

Hope you're doing well. We're reaching out to see if you have any new music you'd like to send us. We'd love to hear from you.

Best regards''';

const List<_ReminderTemplateField> _reminderTemplateFields = [
  _ReminderTemplateField(
      'name', 'Artist name', 'Preferred display name for the artist'),
  _ReminderTemplateField(
      'artist_brand', 'Artist brand', 'Artist brand field from the profile'),
  _ReminderTemplateField(
      'full_name', 'Full name', 'Artist full name from the profile'),
  _ReminderTemplateField('email', 'Email', 'Primary artist email address'),
  _ReminderTemplateField('website', 'Website', 'Artist website URL'),
  _ReminderTemplateField('facebook', 'Facebook', 'Facebook URL'),
  _ReminderTemplateField('twitter_1', 'Twitter 1', 'First Twitter/X URL'),
  _ReminderTemplateField('twitter_2', 'Twitter 2', 'Second Twitter/X URL'),
  _ReminderTemplateField('instagram', 'Instagram', 'Instagram URL'),
  _ReminderTemplateField('spotify', 'Spotify', 'Spotify URL'),
  _ReminderTemplateField('soundcloud', 'SoundCloud', 'SoundCloud URL'),
  _ReminderTemplateField('youtube', 'YouTube', 'YouTube URL'),
  _ReminderTemplateField('tiktok', 'TikTok', 'TikTok URL'),
  _ReminderTemplateField('apple_music', 'Apple Music', 'Apple Music URL'),
  _ReminderTemplateField('other_1', 'Other 1', 'Additional artist link'),
  _ReminderTemplateField('other_2', 'Other 2', 'Additional artist link'),
  _ReminderTemplateField('other_3', 'Other 3', 'Additional artist link'),
  _ReminderTemplateField(
      'address', 'Address', 'Address from the artist profile'),
  _ReminderTemplateField(
      'comments', 'Comments', 'Internal comments stored on the artist'),
  _ReminderTemplateField('notes', 'Notes', 'Artist notes'),
  _ReminderTemplateField(
      'source_row', 'Source row', 'Original import source row'),
];

const Map<String, String> _sampleReminderTemplateValues = {
  'name': 'Test Artist',
  'artist_brand': 'Test Artist',
  'full_name': 'Test Artist',
  'email': 'test.artist@example.com',
  'website': 'https://example.com',
  'facebook': 'https://facebook.com/testartist',
  'twitter_1': 'https://x.com/testartist',
  'twitter_2': 'https://x.com/testartist_label',
  'instagram': 'https://instagram.com/testartist',
  'spotify': 'https://open.spotify.com/artist/testartist',
  'soundcloud': 'https://soundcloud.com/testartist',
  'youtube': 'https://youtube.com/@testartist',
  'tiktok': 'https://tiktok.com/@testartist',
  'apple_music': 'https://music.apple.com/artist/testartist',
  'other_1': 'https://beatport.com/artist/testartist',
  'other_2': 'https://bandcamp.com/testartist',
  'other_3': 'https://residentadvisor.net/dj/testartist',
  'address': 'Tel Aviv, Israel',
  'comments': 'Looking for new demos this quarter.',
  'notes': 'Prefers melodic techno and progressive house.',
  'source_row': 'release-management.csv:42',
};

class _ReminderTemplateField {
  const _ReminderTemplateField(this.key, this.label, this.description);

  final String key;
  final String label;
  final String description;

  String get token => '{$key}';
}

class _RenderedReminderEmail {
  const _RenderedReminderEmail({
    required this.subject,
    required this.bodyHtml,
    required this.bodyText,
  });

  final String subject;
  final String bodyHtml;
  final String bodyText;
}

Map<String, String> _buildReminderTemplateValues(Map<String, dynamic>? artist) {
  final item = artist ?? const <String, dynamic>{};
  final extra = item['extra'] is Map<String, dynamic>
      ? item['extra'] as Map<String, dynamic>
      : const <String, dynamic>{};
  final name =
      (extra['artist_brand'] ?? item['name'] ?? item['email'] ?? 'there')
          .toString()
          .trim();

  String readValue(String key) {
    if (key == 'name') return name;
    final direct = item[key];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }
    final extraValue = extra[key];
    if (extraValue != null && extraValue.toString().trim().isNotEmpty) {
      return extraValue.toString().trim();
    }
    return '';
  }

  return {
    for (final field in _reminderTemplateFields)
      field.key: readValue(field.key),
  };
}

String _applyReminderTemplate(String template, Map<String, String> values) {
  var output = template;
  for (final entry in values.entries) {
    output = output.replaceAll(
      RegExp('\\{${RegExp.escape(entry.key)}\\}', caseSensitive: false),
      entry.value,
    );
  }
  return output;
}

bool _looksLikeHtml(String value) =>
    RegExp(r'<[a-zA-Z][\s\S]*>').hasMatch(value);

String _renderReminderHtml(String value, Map<String, String> values) {
  final rendered = _applyReminderTemplate(value, values);
  if (_looksLikeHtml(rendered)) return rendered;
  return const HtmlEscape(HtmlEscapeMode.element)
      .convert(rendered)
      .replaceAll('\n', '<br>');
}

String _htmlToPlainText(String value) {
  return value
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</li>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

_RenderedReminderEmail _renderReminderEmail({
  required String subjectTemplate,
  required String bodyTemplate,
  required Map<String, String> values,
}) {
  final subject = _applyReminderTemplate(subjectTemplate, values).trim();
  final bodyHtml = _renderReminderHtml(bodyTemplate, values).trim();
  final bodyText = _htmlToPlainText(bodyHtml);
  return _RenderedReminderEmail(
    subject: subject,
    bodyHtml: bodyHtml,
    bodyText: bodyText,
  );
}

void _insertIntoController(TextEditingController controller, String value) {
  final selection = controller.selection;
  if (!selection.isValid) {
    controller.text += value;
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);
    return;
  }
  final start = selection.start < 0 ? controller.text.length : selection.start;
  final end = selection.end < 0 ? controller.text.length : selection.end;
  final newText = controller.text.replaceRange(start, end, value);
  controller.value = controller.value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: start + value.length),
    composing: TextRange.empty,
  );
}

void _wrapControllerSelection(
  TextEditingController controller, {
  required String before,
  required String after,
  String? placeholder,
}) {
  final selection = controller.selection;
  final start = selection.isValid ? selection.start : controller.text.length;
  final end = selection.isValid ? selection.end : controller.text.length;
  final normalizedStart = start < 0 ? controller.text.length : start;
  final normalizedEnd = end < 0 ? controller.text.length : end;
  final selectedText = normalizedStart < normalizedEnd
      ? controller.text.substring(normalizedStart, normalizedEnd)
      : (placeholder ?? '');
  final replacement = '$before$selectedText$after';
  final newText = controller.text.replaceRange(
    normalizedStart,
    normalizedEnd,
    replacement,
  );
  final caretOffset = normalizedStart + before.length + selectedText.length;
  controller.value = controller.value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: caretOffset),
    composing: TextRange.empty,
  );
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({
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
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin
    implements AdminDashboardDelegate {
  static const int _pageSize = 50;

  bool loading = false;
  bool showInactiveArtists = false;
  List<dynamic> artists = const [];
  List<dynamic> demoSubmissions = const [];
  List<dynamic> _allArtistsForSelection = const [];
  final _artistSearchController = TextEditingController();
  String _artistSearchQuery = '';
  Timer? _artistSearchDebounce;
  List<dynamic> catalogTracks = const [];
  List<dynamic> adminReleases = const [];
  List<dynamic> campaigns = const [];
  List<dynamic> campaignRequests = const [];
  List<dynamic> pendingReleases = const [];
  List<dynamic> inboxThreads = const [];
  List<dynamic> audiences = const [];
  List<dynamic> audienceSubscribers = const [];
  int? _selectedAudienceId;
  List<dynamic> users = const [];
  final _releasesSearchController = TextEditingController();
  String _releasesSearchQuery = '';
  String? error;

  late TabController _tabController;
  bool _loadedArtists = false;
  bool _loadedDemos = false;
  bool _loadedInbox = false;
  bool _loadedReleases = false;
  bool _loadedCampaigns = false;
  bool _loadedCampaignRequests = false;
  bool _loadedPendingReleases = false;
  bool _loadedAudiences = false;
  bool _loadedUsers = false;
  bool _artistsHasMore = true;
  bool _artistsLoadingMore = false;
  bool _catalogHasMore = true;
  bool _catalogLoadingMore = false;
  bool _adminReleasesHasMore = true;
  bool _adminReleasesLoadingMore = false;
  bool _campaignsHasMore = true;
  bool _campaignsLoadingMore = false;
  bool _loadingAllArtistsForSelection = false;

  int get _unreadInboxCount => inboxThreads.fold<int>(0, (total, item) {
        if (item is! Map<String, dynamic>) return total;
        final unreadCount = item['unread_count'];
        if (unreadCount is num) return total + unreadCount.toInt();
        return total;
      });

  int _artistsSortColumn = 0;
  bool _artistsSortAsc = true;
  int? _catalogSortColumnIndex;
  bool _catalogSortAsc = true;
  int _releasesSortBy = 0;
  bool _releasesSortAsc = true;
  int _campaignsSortBy = 0;
  bool _campaignsSortAsc = true;

  /// Last system update from Git (from /health), shown in the app bar next to the logo.
  String? _lastGitUpdate;

  /// Dashboard header: active artists count and total releases count.
  int? _artistsCount;
  int? _releasesCount;

  /// Demos that still appear on the Demos tab (exclude approved and pending_release).
  List<dynamic> get _demosOnScreen => demoSubmissions.where((d) {
        final s = (d['status'] ?? 'demo').toString();
        return s != 'approved' && s != 'pending_release';
      }).toList();

  /// Demo counts for top bar: in review and awaiting treatment (from demos still on screen).
  int get _demosInReviewCount => _demosOnScreen
      .where((d) => (d['status'] ?? '').toString() == 'in_review')
      .length;
  int get _demosPendingCount => _demosOnScreen.where((d) {
        final s = (d['status'] ?? 'demo').toString();
        return s == 'demo' || s.isEmpty;
      }).length;

  @override
  ApiClient get apiClient => widget.apiClient;

  @override
  String get token => widget.session.token;

  @override
  bool get isLoading => loading;

  @override
  String? get errorMessage => error;

  @override
  void clearError() => setState(() => error = null);

  @override
  List<dynamic> get artistsList => artists;

  @override
  TextEditingController get artistSearchController => _artistSearchController;

  @override
  int get artistsSortColumn => _artistsSortColumn;

  @override
  bool get artistsSortAsc => _artistsSortAsc;

  @override
  bool get artistsHasMore => _artistsHasMore;

  @override
  bool get artistsLoadingMore => _artistsLoadingMore;

  @override
  void setArtistsSort(int column, bool asc) => setState(() {
        _artistsSortColumn = column;
        _artistsSortAsc = asc;
      });

  @override
  List<dynamic> get adminReleasesList => adminReleases;

  @override
  List<dynamic> get demoSubmissionsList => _demosOnScreen;

  @override
  List<dynamic> get catalogTracksList => catalogTracks;

  @override
  List<dynamic> get artistsListForReleases =>
      _allArtistsForSelection.isNotEmpty ? _allArtistsForSelection : artists;

  @override
  TextEditingController get releasesSearchController =>
      _releasesSearchController;

  @override
  int? get catalogSortColumnIndex => _catalogSortColumnIndex;

  @override
  bool get catalogSortAsc => _catalogSortAsc;

  @override
  void setCatalogSort(int? column, bool asc) => setState(() {
        _catalogSortColumnIndex = column;
        _catalogSortAsc = asc;
      });

  @override
  int get releasesSortBy => _releasesSortBy;

  @override
  bool get releasesSortAsc => _releasesSortAsc;

  @override
  bool get releasesPageHasMore => _catalogHasMore || _adminReleasesHasMore;

  @override
  bool get releasesPageLoadingMore =>
      _catalogLoadingMore || _adminReleasesLoadingMore;

  @override
  void setReleasesSort(int by, bool asc) => setState(() {
        _releasesSortBy = by;
        _releasesSortAsc = asc;
      });

  @override
  List<dynamic> get campaignsList => campaigns;

  @override
  List<dynamic> get audiencesList => audiences;

  @override
  List<dynamic> get audienceSubscribersList => audienceSubscribers;

  @override
  int? get selectedAudienceId => _selectedAudienceId;

  @override
  List<dynamic> get connectionsList => const [];

  @override
  List<dynamic> get hubConnectorsList => const [];

  @override
  int get campaignsSortBy => _campaignsSortBy;

  @override
  bool get campaignsSortAsc => _campaignsSortAsc;

  @override
  bool get campaignsHasMore => _campaignsHasMore;

  @override
  bool get campaignsLoadingMore => _campaignsLoadingMore;

  @override
  void setCampaignsSort(int by, bool asc) => setState(() {
        _campaignsSortBy = by;
        _campaignsSortAsc = asc;
      });

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _tabController.addListener(_onTabChanged);
    _artistSearchController.addListener(_onArtistSearchChanged);
    _releasesSearchController.addListener(_onReleasesSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTabIfNeeded());
    _fetchLastGitUpdate();
    _fetchDashboardStats();
    // Load demos on init so the top bar can show "in review" and "pending" counts.
    _loadDemoSubmissions(withOverlay: false);
    _loadInbox(withOverlay: false);
  }

  Future<void> _fetchLastGitUpdate() async {
    final health = await widget.apiClient.fetchHealth();
    if (!mounted) return;
    final last = health?['last_git_update'];
    setState(() {
      _lastGitUpdate = _formatLastGitUpdate(last);
    });
    // Retry once after a short delay if server did not return last_git_update (e.g. slow start or timeout).
    if (_lastGitUpdate == null && mounted) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final healthRetry = await widget.apiClient.fetchHealth();
      if (!mounted) return;
      final lastRetry = healthRetry?['last_git_update'];
      setState(() => _lastGitUpdate = _formatLastGitUpdate(lastRetry));
    }
  }

  Future<void> _fetchDashboardStats() async {
    try {
      final stats =
          await widget.apiClient.fetchAdminDashboardStats(widget.token);
      if (!mounted) return;
      setState(() {
        _artistsCount = stats['artists_count'] is int
            ? stats['artists_count'] as int
            : null;
        _releasesCount = stats['releases_count'] is int
            ? stats['releases_count'] as int
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _artistsCount = null;
        _releasesCount = null;
      });
    }
  }

  void _onArtistSearchChanged() {
    final query = _artistSearchController.text.trim().toLowerCase();
    if (_artistSearchQuery == query) return;
    setState(() => _artistSearchQuery = query);
    _artistSearchDebounce?.cancel();
    _artistSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      loadArtists();
    });
  }

  void _onReleasesSearchChanged() {
    final query = _releasesSearchController.text.trim().toLowerCase();
    if (_releasesSearchQuery == query) return;
    setState(() => _releasesSearchQuery = query);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    _loadTabIfNeeded();
  }

  void _loadTabIfNeeded() {
    switch (_tabController.index) {
      case 0:
        if (!_loadedArtists) _loadArtists();
        break;
      case 1:
        if (!_loadedDemos) _loadDemoSubmissions();
        break;
      case 2:
        if (!_loadedInbox) _loadInbox();
        break;
      case 3:
        if (!_loadedReleases) _loadReleases();
        if (!_loadedPendingReleases) _loadPendingReleases();
        break;
      case 4:
        if (!_loadedCampaigns) _loadCampaigns();
        if (!_loadedCampaignRequests) _loadCampaignRequests();
        break;
      case 5:
        if (!_loadedAudiences) _loadAudiences();
        break;
      case 7:
        if (!_loadedUsers) _loadUsers();
        break;
    }
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
        onRefresh: load,
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content:
            const Text('You will return to the login screen on this device.'),
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

  Future<void> _loadArtists(
      {bool reset = true, bool withOverlay = true}) async {
    if (_artistsLoadingMore || (!reset && !_artistsHasMore)) return;
    final showOverlay = withOverlay && (reset || artists.isEmpty);
    if (mounted) {
      setState(() {
        if (showOverlay) loading = true;
        _artistsLoadingMore = !reset;
        if (reset) _artistsHasMore = true;
      });
    }
    try {
      final list = await widget.apiClient.fetchArtists(
        widget.token,
        includeInactive: showInactiveArtists,
        search: _artistSearchQuery.isEmpty ? null : _artistSearchQuery,
        limit: _pageSize,
        offset: reset ? 0 : artists.length,
      );
      if (!mounted) return;
      setState(() {
        artists = reset ? list : [...artists, ...list];
        if (reset && _allArtistsForSelection.isNotEmpty) {
          _allArtistsForSelection = const [];
        }
        _artistsHasMore = list.length >= _pageSize;
        _artistsLoadingMore = false;
        if (showOverlay) loading = false;
        error = null;
        _loadedArtists = true;
      });
    } catch (e) {
      if (mounted) setState(() => _artistsLoadingMore = false);
      _setError(e);
      if (mounted) setState(() => _loadedArtists = true);
    }
  }

  Future<void> _loadReleases(
      {bool reset = true, bool withOverlay = true}) async {
    if ((_catalogLoadingMore || _adminReleasesLoadingMore) ||
        (!reset && !_catalogHasMore && !_adminReleasesHasMore)) {
      return;
    }
    final showOverlay = withOverlay &&
        (reset || (catalogTracks.isEmpty && adminReleases.isEmpty));
    if (mounted) {
      setState(() {
        if (showOverlay) loading = true;
        _catalogLoadingMore = !reset && _catalogHasMore;
        _adminReleasesLoadingMore = !reset && _adminReleasesHasMore;
        if (reset) {
          _catalogHasMore = true;
          _adminReleasesHasMore = true;
        }
      });
    }

    final catalogFuture = (reset || _catalogHasMore)
        ? widget.apiClient
            .fetchCatalogTracks(
              widget.token,
              limit: _pageSize,
              offset: reset ? 0 : catalogTracks.length,
            )
            .catchError((_) => <dynamic>[])
        : Future<List<dynamic>>.value(const <dynamic>[]);
    final releasesFuture = (reset || _adminReleasesHasMore)
        ? widget.apiClient
            .fetchAdminReleases(
              widget.token,
              limit: _pageSize,
              offset: reset ? 0 : adminReleases.length,
            )
            .catchError((_) => <dynamic>[])
        : Future<List<dynamic>>.value(const <dynamic>[]);

    try {
      final results = await Future.wait([catalogFuture, releasesFuture]);
      if (!mounted) return;
      final catalogPage = results[0];
      final releasesPage = results[1];
      setState(() {
        catalogTracks =
            reset ? catalogPage : [...catalogTracks, ...catalogPage];
        adminReleases =
            reset ? releasesPage : [...adminReleases, ...releasesPage];
        _catalogHasMore = catalogPage.length >= _pageSize;
        _adminReleasesHasMore = releasesPage.length >= _pageSize;
        _catalogLoadingMore = false;
        _adminReleasesLoadingMore = false;
        if (showOverlay) loading = false;
        error = null;
        _loadedReleases = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _catalogLoadingMore = false;
          _adminReleasesLoadingMore = false;
        });
      }
      _setError(e);
      if (mounted) setState(() => _loadedReleases = true);
    }
  }

  Future<void> _loadDemoSubmissions({bool withOverlay = true}) async {
    final showOverlay = withOverlay && demoSubmissions.isEmpty;
    if (mounted) {
      setState(() {
        if (showOverlay) loading = true;
      });
    }
    try {
      final list = await widget.apiClient.fetchDemoSubmissions(widget.token);
      if (!mounted) return;
      setState(() {
        demoSubmissions = list;
        if (showOverlay) loading = false;
        error = null;
        _loadedDemos = true;
      });
    } catch (e) {
      _setError(e);
      if (mounted) setState(() => _loadedDemos = true);
    }
  }

  Future<void> _loadUsers({bool withOverlay = true}) async {
    final showOverlay = withOverlay && users.isEmpty;
    if (mounted) {
      setState(() {
        if (showOverlay) loading = true;
      });
    }
    try {
      final list = await widget.apiClient.fetchUsers(widget.token);
      if (!mounted) return;
      setState(() {
        users = list;
        if (showOverlay) loading = false;
        error = null;
        _loadedUsers = true;
      });
    } catch (e) {
      _setError(e);
      if (mounted) setState(() => _loadedUsers = true);
    }
  }

  Future<void> _loadCampaigns(
      {bool reset = true, bool withOverlay = true}) async {
    if (_campaignsLoadingMore || (!reset && !_campaignsHasMore)) return;
    final showOverlay = withOverlay && (reset || campaigns.isEmpty);
    if (mounted) {
      setState(() {
        if (showOverlay) loading = true;
        _campaignsLoadingMore = !reset;
        if (reset) _campaignsHasMore = true;
      });
    }
    try {
      final list = await widget.apiClient.fetchCampaigns(
        widget.token,
        limit: _pageSize,
        offset: reset ? 0 : campaigns.length,
      );
      if (!mounted) return;
      setState(() {
        campaigns = reset ? list : [...campaigns, ...list];
        _campaignsHasMore = list.length >= _pageSize;
        _campaignsLoadingMore = false;
        if (showOverlay) loading = false;
        error = null;
        _loadedCampaigns = true;
      });
    } catch (e) {
      if (mounted) setState(() => _campaignsLoadingMore = false);
      _setError(e);
      if (mounted) setState(() => _loadedCampaigns = true);
    }
  }

  Future<void> _loadCampaignRequests({String? statusFilter}) async {
    if (mounted) setState(() => loading = true);
    try {
      final list = await widget.apiClient.fetchCampaignRequests(
        token: widget.token,
        statusFilter: statusFilter,
      );
      if (!mounted) return;
      setState(() {
        campaignRequests = list;
        loading = false;
        error = null;
        _loadedCampaignRequests = true;
      });
    } catch (e) {
      _setError(e);
      if (mounted) {
        setState(() {
          loading = false;
          _loadedCampaignRequests = true;
        });
      }
    }
  }

  Future<void> _updateCampaignRequestStatus(int requestId, String status,
      {String? adminNotes}) async {
    try {
      await widget.apiClient.updateCampaignRequest(
        token: widget.token,
        requestId: requestId,
        status: status,
        adminNotes: adminNotes,
      );
      if (!mounted) return;
      await _loadCampaignRequests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'Campaign request approved. The artist was sent an email with a link to submit their full release details.'
                : 'Campaign request $status',
          ),
        ),
      );
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _loadPendingReleases({String? statusFilter}) async {
    if (mounted) setState(() => loading = true);
    try {
      final list = await widget.apiClient.fetchPendingReleases(
        token: widget.token,
        statusFilter: statusFilter,
      );
      if (!mounted) return;
      setState(() {
        pendingReleases = list;
        loading = false;
        error = null;
        _loadedPendingReleases = true;
      });
    } catch (e) {
      _setError(e);
      if (mounted) {
        setState(() {
          loading = false;
          _loadedPendingReleases = true;
        });
      }
    }
  }

  Future<void> _sendPendingReleaseReminder(
      int pendingReleaseId, String artistName) async {
    try {
      final result = await widget.apiClient.sendPendingReleaseReminder(
        token: widget.token,
        pendingReleaseId: pendingReleaseId,
      );
      if (!mounted) return;
      final expiresAt = (result['expires_at'] ?? '').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            expiresAt.isEmpty
                ? 'Completion email sent to $artistName.'
                : 'Completion email sent to $artistName. Link valid until $expiresAt.',
          ),
        ),
      );
      await _loadPendingReleases();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _archivePendingRelease(
      int pendingReleaseId, String releaseTitle,
      {String? statusFilter}) async {
    try {
      final result = await widget.apiClient.archivePendingRelease(
        token: widget.token,
        pendingReleaseId: pendingReleaseId,
      );
      if (!mounted) return;
      final message = (result['message'] ?? '').toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty
                ? 'Pending release archived${releaseTitle.trim().isEmpty ? '.' : ': $releaseTitle'}'
                : message,
          ),
        ),
      );
      await _loadPendingReleases(statusFilter: statusFilter);
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _deletePendingRelease(
      int pendingReleaseId, String releaseTitle,
      {String? statusFilter}) async {
    try {
      await widget.apiClient.deletePendingRelease(
        token: widget.token,
        pendingReleaseId: pendingReleaseId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            releaseTitle.trim().isEmpty
                ? 'Pending release deleted.'
                : 'Pending release deleted: $releaseTitle',
          ),
        ),
      );
      await _loadPendingReleases(statusFilter: statusFilter);
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showPendingReleaseMessageDialog(
      Map<String, dynamic> pendingRelease) async {
    final artistName = (pendingRelease['artist_name'] ?? '').toString().trim();
    final artistEmail =
        (pendingRelease['artist_email'] ?? '').toString().trim();
    final releaseTitle =
        (pendingRelease['release_title'] ?? '').toString().trim();
    final artistId = pendingRelease['artist_id'] as int?;
    if (artistEmail.isEmpty) {
      _showErrorSnackBar('This pending release does not have an artist email.');
      return;
    }

    final subjectController = TextEditingController(
      text: releaseTitle.isEmpty
          ? 'About your release submission'
          : 'About your release submission: $releaseTitle',
    );
    final bodyController = TextEditingController(
      text: artistName.isEmpty ? 'Hi,\n\n' : 'Hi $artistName,\n\n',
    );
    var sending = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Message artist'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      artistEmail,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subjectController,
                      decoration: const InputDecoration(
                        labelText: 'Subject',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bodyController,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        hintText: 'Write your message to the artist...',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      maxLines: 10,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: sending
                    ? null
                    : () async {
                        final subject = subjectController.text.trim();
                        final body = bodyController.text.trim();
                        if (subject.isEmpty || body.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Subject and message are required.')),
                          );
                          return;
                        }
                        setDialogState(() => sending = true);
                        try {
                          final escapedBody =
                              const HtmlEscape(HtmlEscapeMode.element)
                                  .convert(body);
                          final htmlBody =
                              '<p>${escapedBody.replaceAll('\n', '<br>')}</p>';
                          await widget.apiClient.sendEmail(
                            token: widget.token,
                            toEmail: artistEmail,
                            subject: subject,
                            bodyText: body,
                            bodyHtml: htmlBody,
                            artistId: artistId,
                          );
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                artistName.isEmpty
                                    ? 'Message sent to $artistEmail.'
                                    : 'Message sent to $artistName.',
                              ),
                            ),
                          );
                          await _loadPendingReleases();
                        } catch (e) {
                          if (!ctx.mounted) return;
                          setDialogState(() => sending = false);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text(e
                                    .toString()
                                    .replaceFirst('Exception: ', ''))),
                          );
                        }
                      },
                icon: sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(sending ? 'Sending...' : 'Send'),
              ),
            ],
          ),
        ),
      );
    } finally {
      subjectController.dispose();
      bodyController.dispose();
    }
  }

  Future<void> _loadInbox({bool withOverlay = true}) async {
    if (mounted && withOverlay) setState(() => loading = true);
    try {
      final list =
          await widget.apiClient.fetchInboxThreads(token: widget.token);
      if (!mounted) return;
      setState(() {
        inboxThreads = list;
        if (withOverlay) loading = false;
        error = null;
        _loadedInbox = true;
      });
    } catch (e) {
      _setError(e);
      if (mounted) {
        setState(() {
          if (withOverlay) loading = false;
          _loadedInbox = true;
        });
      }
    }
  }

  Future<void> _loadAudiences(
      {bool reset = true, bool withOverlay = true}) async {
    final showOverlay = withOverlay && (reset || audiences.isEmpty);
    if (mounted) {
      setState(() {
        if (showOverlay) loading = true;
      });
    }
    try {
      final list = await widget.apiClient.fetchAudiences(widget.token);
      int? nextSelectedId = _selectedAudienceId;
      if (list.isEmpty) {
        nextSelectedId = null;
      } else {
        final ids = list.map((e) => (e as Map<String, dynamic>)['id']).toSet();
        if (nextSelectedId == null || !ids.contains(nextSelectedId)) {
          nextSelectedId = (list.first as Map<String, dynamic>)['id'] as int;
        }
      }
      List<dynamic> subscribers = audienceSubscribers;
      if (nextSelectedId != null) {
        subscribers = await widget.apiClient.fetchAudienceSubscribers(
          token: widget.token,
          audienceId: nextSelectedId,
        );
      } else {
        subscribers = const [];
      }
      if (!mounted) return;
      setState(() {
        audiences = list;
        audienceSubscribers = subscribers;
        _selectedAudienceId = nextSelectedId;
        if (showOverlay) loading = false;
        error = null;
        _loadedAudiences = true;
      });
    } catch (e) {
      _setError(e);
      if (mounted) setState(() => _loadedAudiences = true);
    }
  }

  Future<void> _ensureAllArtistsForSelectionLoaded() async {
    if (_allArtistsForSelection.isNotEmpty || _loadingAllArtistsForSelection) {
      return;
    }
    _loadingAllArtistsForSelection = true;
    try {
      final allArtists = <dynamic>[];
      var offset = 0;
      while (true) {
        final page = await widget.apiClient.fetchArtists(
          widget.token,
          includeInactive: showInactiveArtists,
          limit: _pageSize,
          offset: offset,
        );
        allArtists.addAll(page);
        if (page.length < _pageSize) break;
        offset += page.length;
      }
      if (!mounted) return;
      setState(() => _allArtistsForSelection = allArtists);
    } finally {
      _loadingAllArtistsForSelection = false;
    }
  }

  Future<void> _reloadAllTabs() async {
    if (mounted) setState(() => loading = true);
    await Future.wait([
      _loadArtists(reset: true, withOverlay: false),
      _loadDemoSubmissions(withOverlay: false),
      _loadReleases(reset: true, withOverlay: false),
      _loadPendingReleases(),
      _loadInbox(withOverlay: false),
      _loadCampaigns(reset: true, withOverlay: false),
      _loadAudiences(reset: true, withOverlay: false),
      _fetchDashboardStats(),
    ]);
    if (!mounted) return;
    setState(() => loading = false);
  }

  void _setError(Object e) {
    final msg = e.toString();
    // Treat 401 / invalid or expired token as session expired: logout so user can sign in again.
    if (msg.contains('401') ||
        msg.contains('Invalid or expired token') ||
        msg.contains('expired token')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Session expired. Please sign in again.')),
        );
      }
      widget.onLogout();
      return;
    }
    // Artist token used in LM: backend returns 403 with "Artists cannot access the LM system..."
    if (msg.contains('403') && msg.contains('Artists cannot access')) {
      const text =
          'Artists cannot access the LM system. Use the artist portal.';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText(text),
            action: SnackBarAction(
              label: 'Copy',
              onPressed: () => Clipboard.setData(ClipboardData(text: text)),
            ),
          ),
        );
      }
      widget.onLogout();
      return;
    }
    final isConnectionError = msg.contains('Failed to fetch') ||
        msg.contains('Connection refused') ||
        msg.contains('SocketException') ||
        msg.contains('ClientException');
    if (!mounted) return;
    setState(() {
      error = isConnectionError
          ? 'Cannot reach API at ${widget.apiClient.baseUrl}. Backend running?'
          : msg;
      loading = false;
    });
  }

  @override
  void dispose() {
    _artistSearchDebounce?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _artistSearchController.removeListener(_onArtistSearchChanged);
    _releasesSearchController.removeListener(_onReleasesSearchChanged);
    _artistSearchController.dispose();
    _releasesSearchController.dispose();
    super.dispose();
  }

  @override
  Future<void> load() => _reloadAllTabs();

  @override
  Future<void> loadArtists() => _loadArtists(reset: true);

  @override
  Future<void> loadDemoSubmissions() => _loadDemoSubmissions();

  @override
  Future<void> loadMoreArtists() =>
      _loadArtists(reset: false, withOverlay: false);

  @override
  Future<void> loadReleases() => _loadReleases(reset: true);

  @override
  Future<void> loadMoreReleasesPage() =>
      _loadReleases(reset: false, withOverlay: false);

  @override
  Future<void> loadCampaigns() => _loadCampaigns(reset: true);

  @override
  Future<void> loadAudiences() => _loadAudiences(reset: true);

  @override
  Future<void> loadMoreCampaigns() =>
      _loadCampaigns(reset: false, withOverlay: false);

  @override
  List<dynamic> get campaignRequestsList => campaignRequests;

  @override
  Future<void> loadCampaignRequests({String? statusFilter}) =>
      _loadCampaignRequests(statusFilter: statusFilter);

  @override
  void updateCampaignRequestStatus(int requestId, String status,
          {String? adminNotes}) =>
      _updateCampaignRequestStatus(requestId, status, adminNotes: adminNotes);

  @override
  List<dynamic> get pendingReleasesList => pendingReleases;

  @override
  Future<void> loadPendingReleases({String? statusFilter}) =>
      _loadPendingReleases(statusFilter: statusFilter);

  @override
  Future<void> sendPendingReleaseReminder(
          int pendingReleaseId, String artistName) =>
      _sendPendingReleaseReminder(pendingReleaseId, artistName);

  @override
  Future<void> archivePendingRelease(
          int pendingReleaseId, String releaseTitle,
          {String? statusFilter}) =>
      _archivePendingRelease(pendingReleaseId, releaseTitle,
          statusFilter: statusFilter);

  @override
  Future<void> deletePendingRelease(
          int pendingReleaseId, String releaseTitle,
          {String? statusFilter}) =>
      _deletePendingRelease(pendingReleaseId, releaseTitle,
          statusFilter: statusFilter);

  @override
  void showPendingReleaseMessageDialog(Map<String, dynamic> pendingRelease) =>
      _showPendingReleaseMessageDialog(pendingRelease);

  @override
  List<dynamic> get inboxThreadsList => inboxThreads;

  @override
  Future<void> loadInbox() => _loadInbox();

  @override
  void showInboxThreadDialog(int threadId) => _showInboxThreadDialog(threadId);

  @override
  Future<void> deleteInboxThread(int threadId, String artistName) =>
      _deleteInboxThread(threadId, artistName);

  Future<bool> _deleteInboxThread(int threadId, String artistName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete inbox thread?'),
        content: Text(
          'Delete the entire conversation with ${artistName.isEmpty ? 'this artist' : artistName}?\n\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    try {
      await widget.apiClient.deleteInboxThread(
        token: widget.token,
        threadId: threadId,
      );
      if (!mounted) return true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            artistName.isEmpty
                ? 'Inbox thread deleted.'
                : 'Deleted conversation with $artistName.',
          ),
        ),
      );
      await _loadInbox();
      return true;
    } catch (e) {
      _showErrorSnackBar(e.toString());
      return false;
    }
  }

  Future<void> _showInboxThreadDialog(int threadId) async {
    try {
      var threadData = await widget.apiClient
          .fetchInboxThread(token: widget.token, threadId: threadId);
      if (!mounted) return;
      unawaited(_loadInbox(withOverlay: false));
      final replyController = TextEditingController();
      bool sending = false;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              final messages = threadData['messages'] as List<dynamic>? ?? [];
              final artistName = (threadData['artist_name'] ?? '').toString();
              final artistEmail = (threadData['artist_email'] ?? '').toString();
              final screenSize = MediaQuery.sizeOf(ctx);
              return AlertDialog(
                insetPadding: EdgeInsets.symmetric(
                  horizontal: screenSize.width * 0.1,
                  vertical: screenSize.height * 0.1,
                ),
                title: Text('Inbox: $artistName'),
                content: SizedBox(
                  width: screenSize.width * 0.8,
                  height: screenSize.height * 0.8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(artistEmail,
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 16),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final m in messages) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (m['sender'] ?? '').toString() ==
                                                'label'
                                            ? 'Label (you)'
                                            : 'Artist',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color:
                                              (m['sender'] ?? '').toString() ==
                                                      'label'
                                                  ? Theme.of(ctx)
                                                      .colorScheme
                                                      .primary
                                                  : Colors.grey[700],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      SelectableText(
                                          (m['body'] ?? '').toString()),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const Divider(),
                      const Text('Reply (sends email to artist)',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: replyController,
                        decoration: const InputDecoration(
                          hintText: 'Type your reply...',
                          border: OutlineInputBorder(),
                          alignLabelWithHint: true,
                        ),
                        maxLines: 8,
                        minLines: 6,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final deleted =
                          await _deleteInboxThread(threadId, artistName);
                      if (deleted && ctx.mounted) {
                        Navigator.of(ctx).pop();
                      }
                    },
                    child: const Text('Delete'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: sending
                        ? null
                        : () async {
                            final body = replyController.text.trim();
                            if (body.isEmpty) return;
                            setDialogState(() => sending = true);
                            try {
                              threadData =
                                  await widget.apiClient.replyToInboxThread(
                                token: widget.token,
                                threadId: threadId,
                                body: body,
                              );
                              if (!ctx.mounted) return;
                              setDialogState(() => sending = false);
                              replyController.clear();
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Reply sent (email sent to artist).')),
                              );
                            } catch (e) {
                              if (ctx.mounted) {
                                setDialogState(() => sending = false);
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: SelectableText(e
                                        .toString()
                                        .replaceFirst('Exception: ', '')),
                                    action: SnackBarAction(
                                      label: 'Copy',
                                      onPressed: () => Clipboard.setData(
                                          ClipboardData(text: e.toString())),
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    child: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reply'),
                  ),
                ],
              );
            },
          );
        },
      );
      replyController.dispose();
      await _loadInbox();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  @override
  Future<void> selectAudience(int id) async {
    if (_selectedAudienceId == id && audienceSubscribers.isNotEmpty) return;
    try {
      setState(() {
        loading = true;
        _selectedAudienceId = id;
      });
      final subscribers = await widget.apiClient.fetchAudienceSubscribers(
        token: widget.token,
        audienceId: id,
      );
      if (!mounted) return;
      setState(() {
        audienceSubscribers = subscribers;
        loading = false;
        error = null;
      });
    } catch (e) {
      _setError(e);
    }
  }

  @override
  void showAddArtistDialog() => _showAddArtistDialog();

  @override
  void showEditArtistDialog(int id, {Map<String, dynamic>? initialArtist}) =>
      _showEditArtistDialog(id, initialArtist: initialArtist);

  @override
  void showSetArtistPasswordDialog(int artistId, String artistName) =>
      _showSetArtistPasswordDialog(artistId, artistName);

  @override
  void sendArtistPortalInvite(
          int artistId, String artistName, String artistEmail) =>
      _sendArtistPortalInvite(artistId, artistName, artistEmail);
  @override
  void sendArtistPortalInviteToAll() => _sendArtistPortalInviteToAll();

  @override
  void sendArtistUpdateProfileInvite(
          int artistId, String artistName, String artistEmail) =>
      _sendArtistUpdateProfileInvite(artistId, artistName, artistEmail);

  @override
  void removeArtist(int id, String name) => _removeArtist(id, name);

  @override
  void showMergeArtistsDialog() => _showMergeArtistsDialog();

  @override
  void showArtistReleases(int id, String name) => _showArtistReleases(id, name);

  @override
  void showArtistDetailsDialog(int id) => _showArtistDetailsDialog(id);

  @override
  void showGrooverInviteDialog() => _showGrooverInviteDialog();

  @override
  void showDemoDetailsDialog(Map<String, dynamic> submission) =>
      _showDemoDetailsDialog(submission);

  @override
  void showApproveDemoDialog(Map<String, dynamic> submission) =>
      _showApproveDemoDialog(submission);

  @override
  void updateDemoStatus(Map<String, dynamic> submission, String status) =>
      _updateDemoStatus(submission, status);

  @override
  Future<void> deleteDemoSubmission(Map<String, dynamic> submission) =>
      _deleteDemoSubmission(submission);

  @override
  void importCatalogCsv() => _importCatalogCsv();

  @override
  void syncReleasesFromCatalog() => _syncReleasesFromCatalog();

  @override
  void syncOriginalArtistsFromArtists() => _syncOriginalArtistsFromArtists();

  @override
  void createMissingOriginalArtists() => _createMissingOriginalArtists();

  @override
  void showSetArtistsDialog(Map<String, dynamic> release) =>
      _showSetArtistsDialog(release);

  @override
  void prepareCampaignFromRelease(
          int artistId, String artistName, Map<String, dynamic> release) =>
      _prepareCampaignFromRelease(artistId, artistName, release);

  @override
  void showCreateCampaignDialog({
    String? initialName,
    String? initialTitle,
    String? initialBody,
    int? initialArtistId,
  }) =>
      _showCreateCampaignDialog(
        initialName: initialName,
        initialTitle: initialTitle,
        initialBody: initialBody,
        initialArtistId: initialArtistId,
      );

  @override
  void showEditCampaignDialog(Map<String, dynamic> campaign) =>
      _showEditCampaignDialog(campaign);

  @override
  void showScheduleCampaignDialog(int campaignId) =>
      _showScheduleCampaignDialog(campaignId);

  @override
  void cancelCampaignSchedule(int id) => _cancelCampaignSchedule(id);

  @override
  void deleteCampaign(int id, String name) => _deleteCampaign(id, name);

  @override
  void showCreateAudienceDialog() => _showCreateAudienceDialog();

  @override
  void importMailchimpAudienceCsv() => _importMailchimpAudienceCsv();

  @override
  void showEditAudienceDialog(Map<String, dynamic> audience) =>
      _showCreateAudienceDialog(existingAudience: audience);

  @override
  void showAddAudienceSubscriberDialog() => _showAudienceSubscriberDialog();

  @override
  void showEditAudienceSubscriberDialog(Map<String, dynamic> subscriber) =>
      _showAudienceSubscriberDialog(existingSubscriber: subscriber);

  @override
  void toggleAudienceSubscriberStatus(Map<String, dynamic> subscriber) =>
      _toggleAudienceSubscriberStatus(subscriber);

  @override
  Future<void> promoteAudienceSubscriberToArtist(
          Map<String, dynamic> subscriber) =>
      _promoteAudienceSubscriberToArtist(subscriber);

  @override
  void showArtistRemindersReport(BuildContext context) =>
      _showArtistRemindersReport(context);

  @override
  void showSignedInArtistsReport(BuildContext context) =>
      _showSignedInArtistsReport(context);

  @override
  void showSendEmailToReportArtistsDialog(BuildContext context,
          List<dynamic> reportList, List<int> selectedIndices) =>
      _showSendEmailToReportArtistsDialog(context, reportList, selectedIndices);

  @override
  List<dynamic> get usersList => users;

  @override
  Future<void> loadUsers() => _loadUsers();

  @override
  void showAddUserDialog() => _showAddUserDialog();

  @override
  void showEditUserDialog(Map<String, dynamic> user) =>
      _showEditUserDialog(user);

  @override
  void updateUserActive(Map<String, dynamic> user, bool isActive) =>
      _updateUserActive(user, isActive);

  @override
  void showErrorSnackBar(String message) => _showErrorSnackBar(message);

  /// Releases list: unassigned first, then by title or date.
  List<dynamic> get _sortedAdminReleases {
    final list = List<Map<String, dynamic>>.from(
        adminReleases.map((e) => e as Map<String, dynamic>));
    list.sort((a, b) {
      final aIds = a['artist_ids'] as List<dynamic>? ?? [];
      final bIds = b['artist_ids'] as List<dynamic>? ?? [];
      final aNoArtist = aIds.isEmpty;
      final bNoArtist = bIds.isEmpty;
      if (aNoArtist != bNoArtist) return aNoArtist ? -1 : 1; // unassigned first
      final cmp = _releasesSortBy == 1
          ? _compareReleaseDate(a, b)
          : _compareString(
              (a['title'] as String?) ?? '', (b['title'] as String?) ?? '');
      return _releasesSortAsc ? cmp : -cmp;
    });
    return list;
  }

  int _compareReleaseDate(Map<String, dynamic> a, Map<String, dynamic> b) {
    final sa = a['created_at'] as String? ?? '';
    final sb = b['created_at'] as String? ?? '';
    if (sa.isEmpty && sb.isEmpty) return 0;
    if (sa.isEmpty) return 1;
    if (sb.isEmpty) return -1;
    try {
      return DateTime.parse(sa).compareTo(DateTime.parse(sb));
    } catch (_) {
      return sa.compareTo(sb);
    }
  }

  int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  /// Catalog tracks filtered by releases search query (catalog #, release/track title, artists, ISRC, UPC, mix).
  List<dynamic> get _filteredCatalogTracks {
    if (_releasesSearchQuery.isEmpty) return catalogTracks;
    final q = _releasesSearchQuery;
    return catalogTracks.where((e) {
      final t = e as Map<String, dynamic>;
      final catalogNumber =
          (t['catalog_number'] as String? ?? '').toLowerCase();
      final releaseTitle = (t['release_title'] as String? ?? '').toLowerCase();
      final trackTitle = (t['track_title'] as String? ?? '').toLowerCase();
      final originalArtists =
          (t['original_artists'] as String? ?? '').toLowerCase();
      final isrc = (t['isrc'] as String? ?? '').toLowerCase();
      final upc = (t['upc'] as String? ?? '').toLowerCase();
      final mixTitle = (t['mix_title'] as String? ?? '').toLowerCase();
      return catalogNumber.contains(q) ||
          releaseTitle.contains(q) ||
          trackTitle.contains(q) ||
          originalArtists.contains(q) ||
          isrc.contains(q) ||
          upc.contains(q) ||
          mixTitle.contains(q);
    }).toList();
  }

  /// Catalog tracks filtered and sorted for DataTable.
  List<dynamic> get _sortedCatalogTracks {
    var list = List<Map<String, dynamic>>.from(
        _filteredCatalogTracks.map((e) => e as Map<String, dynamic>));
    final col = _catalogSortColumnIndex;
    if (col == null) return list;
    list.sort((a, b) {
      final av = _catalogCellValue(a, col);
      final bv = _catalogCellValue(b, col);
      int cmp;
      if (col == 2) {
        // Release Date - try parse
        cmp = _compareOptionalDate(av, bv);
      } else {
        cmp = _compareString(av, bv);
      }
      return _catalogSortAsc ? cmp : -cmp;
    });
    return list;
  }

  String _catalogCellValue(Map<String, dynamic> t, int col) {
    switch (col) {
      case 0:
        return (t['catalog_number'] as String?) ?? '';
      case 1:
        return (t['release_title'] as String?) ?? '';
      case 2:
        return (t['release_date'] as String?) ?? '';
      case 3:
        return (t['upc'] as String?) ?? '';
      case 4:
        return (t['isrc'] as String?) ?? '';
      case 5:
        return (t['original_artists'] as String?) ?? '';
      case 6:
        return (t['track_title'] as String?) ?? '';
      case 7:
        return (t['mix_title'] as String?) ?? '';
      case 8:
        return (t['duration'] as String?) ?? '';
      default:
        return '';
    }
  }

  int _compareOptionalDate(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 0;
    if (a.isEmpty) return 1;
    if (b.isEmpty) return -1;
    try {
      return DateTime.parse(a).compareTo(DateTime.parse(b));
    } catch (_) {
      return a.compareTo(b);
    }
  }

  DataColumn _dataColumn(String label, int columnIndex) {
    return DataColumn(
      label: Text(label),
      onSort: (int columnIndex, bool ascending) {
        setState(() {
          _catalogSortColumnIndex = columnIndex;
          _catalogSortAsc = ascending;
        });
      },
    );
  }

  /// Campaigns list sorted for display.
  List<dynamic> get _sortedCampaigns {
    final list = List<Map<String, dynamic>>.from(
        campaigns.map((e) => e as Map<String, dynamic>));
    list.sort((a, b) {
      int cmp;
      switch (_campaignsSortBy) {
        case 1:
          cmp = _compareString((a['scheduled_at'] as String?) ?? '',
              (b['scheduled_at'] as String?) ?? '');
          break;
        case 2:
          cmp = _compareString(
              (a['sent_at'] as String?) ?? '', (b['sent_at'] as String?) ?? '');
          break;
        case 3:
          cmp = _compareString(
              (a['status'] as String?) ?? '', (b['status'] as String?) ?? '');
          break;
        default:
          cmp = _compareString(
              (a['name'] as String?) ?? '', (b['name'] as String?) ?? '');
      }
      return _campaignsSortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/zalmanim_logo.png',
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 16),
            Tooltip(
              message: 'Demos in review and awaiting treatment',
              child: SelectableText(
                _loadedDemos
                    ? '$_demosInReviewCount in review - $_demosPendingCount pending'
                    : '- in review - - pending',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: AppVersionBadge(
                tooltipPrefix: 'LM app version',
                textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          if (_artistsCount != null || _releasesCount != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'Active artists and total releases',
                child: SelectableText(
                  '${_artistsCount ?? '—'} artists · ${_releasesCount ?? '—'} releases',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
          if (_loadedPendingReleases)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message: 'Releases waiting in Pending Release',
                child: SelectableText(
                  '${pendingReleases.length} pending release${pendingReleases.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: _lastGitUpdate != null
                      ? 'Last system update (from server): $_lastGitUpdate'
                      : 'Last system update (set GIT_LAST_UPDATE on server)',
                  child: SelectableText(
                    'Updated: ${_lastGitUpdate ?? '—'}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                if (_lastGitUpdate != null)
                  IconButton(
                    icon: const Icon(ZalmanimIcons.copy, size: 18),
                    tooltip: 'Copy last update time',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: _lastGitUpdate!)),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),
          ApiConnectionIndicator(
            apiClient: widget.apiClient,
            onConnectionRestored: load,
          ),
          IconButton(
            icon: const Icon(ZalmanimIcons.account),
            tooltip: 'User details',
            onPressed: _openUserSettings,
          ),
          IconButton(
            icon: const Icon(ZalmanimIcons.logout),
            tooltip: 'Log out',
            onPressed: _confirmLogout,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
                icon: ZalmanimIcons.alienIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                text: 'Artists'),
            Tab(
                icon: ZalmanimIcons.jellyfishIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                text: 'Demos'),
            Tab(
                child: InboxTabLabel(
              iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
              unreadCount: _unreadInboxCount,
            )),
            Tab(
                icon: ZalmanimIcons.squidIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                text: 'Releases'),
            Tab(
                icon: ZalmanimIcons.alienIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                text: 'CAMPAIGNS'),
            Tab(
                icon: ZalmanimIcons.squidIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                text: 'Audience'),
            Tab(
                icon: ZalmanimIcons.alienIcon(
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                text: 'Reports'),
            Tab(
                icon: Icon(ZalmanimIcons.settings,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                text: 'Settings'),
          ],
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackdrop()),
          TabBarView(
            controller: _tabController,
            children: [
              ArtistsTab(delegate: this),
              DemosTab(delegate: this),
              InboxTab(delegate: this),
              ReleasesSectionTab(delegate: this),
              CampaignsSectionTab(delegate: this),
              AudienceTab(delegate: this),
              ReportsTab(delegate: this),
              SettingsTab(delegate: this),
            ],
          ),
          if (loading)
            Positioned.fill(
              child: Container(
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
          if (error != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Material(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(ZalmanimIcons.copy),
                        tooltip: 'Copy error',
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: error!)),
                      ),
                      IconButton(
                        icon: const Icon(ZalmanimIcons.close),
                        onPressed: clearError,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Used by campaign dialogs (connections/hubConnectors not yet loaded from API).
  List<dynamic> get connections => connectionsList;
  List<dynamic> get hubConnectors => hubConnectorsList;

  Widget _sortableHeader(BuildContext context, String label, int columnIndex) {
    final isActive = _artistsSortColumn == columnIndex;
    return InkWell(
      onTap: () => setState(() {
        if (_artistsSortColumn == columnIndex) {
          _artistsSortAsc = !_artistsSortAsc;
        } else {
          _artistsSortColumn = columnIndex;
          _artistsSortAsc = true;
        }
      }),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            if (isActive)
              Icon(
                  _artistsSortAsc
                      ? ZalmanimIcons.arrowDropUp
                      : ZalmanimIcons.arrowDropDown,
                  size: 20),
          ],
        ),
      ),
    );
  }

  /// Format last release for display: "Title" or "Title (date)" or "-".
  String _artistLastRelease(Map<String, dynamic> artist) {
    final lr = artist['last_release'];
    if (lr == null || lr is! Map<String, dynamic>) return '-';
    final title = lr['title'] as String?;
    if (title == null || title.isEmpty) return '-';
    final created = lr['created_at'] as String?;
    if (created != null && created.isNotEmpty) {
      try {
        final dt = DateTime.parse(created);
        return '$title (${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')})';
      } catch (_) {}
    }
    return title;
  }

  Widget _demoInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          SelectableText(value.isEmpty ? '-' : value),
        ],
      ),
    );
  }

  /// Formats a demo submission date (ISO string or null) for display. Returns null if missing/invalid.
  static String? _formatDemoDate(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    try {
      final dt = DateTime.parse(s);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return s;
    }
  }

  static String? _formatLastGitUpdate(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return raw;
    }
  }

  /// Collects SoundCloud URLs from demo submission links, fields, and message text.
  static List<String> _getSoundCloudUrls(Map<String, dynamic> submission) {
    final urls = <String>{};
    bool isSoundCloudUrl(String s) {
      final lower = s.toLowerCase().trim();
      return (lower.contains('soundcloud.com') ||
              lower.contains('on.soundcloud.com') ||
              lower.contains('soundcloud.app.goo.gl')) &&
          (lower.startsWith('http://') || lower.startsWith('https://'));
    }

    void addIfSoundCloud(String s) {
      final t = s.trim();
      if (t.isEmpty) return;
      if (isSoundCloudUrl(t)) urls.add(t);
    }

    for (final link in (submission['links'] as List<dynamic>? ?? const [])) {
      addIfSoundCloud(link.toString());
    }
    final fields = submission['fields'];
    if (fields is Map<String, dynamic>) {
      for (final entry in fields.entries) {
        final val = entry.value;
        if (val is! String) continue;
        addIfSoundCloud(val);
      }
    }
    // Extract URLs from message (e.g. pasted SoundCloud link)
    final message = (submission['message'] ?? '').toString();
    if (message.isNotEmpty) {
      final uriPattern = RegExp(
        r'https?://[^\s<>"{}|\\^`\[\]]+',
        caseSensitive: false,
      );
      for (final match in uriPattern.allMatches(message)) {
        addIfSoundCloud(match.group(0)!);
      }
    }
    return urls.toList();
  }

  Future<void> _updateDemoStatus(
      Map<String, dynamic> submission, String status) async {
    if (status == 'rejected') {
      await _showRejectDemoDialog(submission);
      return;
    }
    final id = submission['id'] as int?;
    if (id == null) return;
    try {
      final updated = await widget.apiClient.updateDemoSubmission(
        token: widget.token,
        id: id,
        body: {'status': status},
      );
      await _loadDemoSubmissions(withOverlay: false);
      if (!mounted) return;
      String message;
      if (status == 'rejected') {
        message = updated['rejection_email_sent_at'] != null
            ? 'Demo rejected. A rejection email was sent to the artist.'
            : 'Demo rejected.';
      } else {
        message = 'Demo updated to $status.';
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> _showRejectDemoDialog(Map<String, dynamic> submission) async {
    final id = submission['id'] as int?;
    if (id == null) return;
    final artistName = (submission['artist_name'] ?? '').toString().trim();
    final subjectController = TextEditingController(
      text: (submission['rejection_subject'] ??
              'Thank you for your demo submission, ${artistName.isEmpty ? 'there' : artistName}')
          .toString(),
    );
    final bodyController = TextEditingController(
      text: (submission['rejection_body'] ??
              'Hi ${artistName.isEmpty ? 'there' : artistName},\n\n'
                  'Thank you for sending us your music. We received it with respect and appreciate you thinking of us.\n\n'
                  'After careful consideration, we feel it does not quite fit the musical direction of our labels at this time. '
                  'We would be happy to receive more demos from you in the future in the hope they may align with our line.\n\n'
                  'Best regards,\nZalmanim')
          .toString(),
    );
    bool sendEmail = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Reject demo'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: subjectController,
                    decoration:
                        const InputDecoration(labelText: 'Rejection subject'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Rejection email body',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: sendEmail,
                    onChanged: (value) =>
                        setStateDialog(() => sendEmail = value),
                    title: const Text('Send rejection email now'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      subjectController.dispose();
      bodyController.dispose();
      return;
    }
    try {
      await widget.apiClient.updateDemoSubmission(
        token: widget.token,
        id: id,
        body: {
          'status': 'rejected',
          'rejection_subject': subjectController.text.trim(),
          'rejection_body': bodyController.text,
          'send_rejection_email': sendEmail,
        },
      );
      await _loadDemoSubmissions(withOverlay: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sendEmail ? 'Demo rejected and email sent.' : 'Demo rejected.',
          ),
        ),
      );
    } catch (e) {
      _setError(e);
    } finally {
      subjectController.dispose();
      bodyController.dispose();
    }
  }

  Future<void> _showApproveDemoDialog(Map<String, dynamic> submission) async {
    final id = submission['id'] as int?;
    if (id == null) return;
    final artistName = (submission['artist_name'] ?? '').toString();
    final subjectController = TextEditingController(
      text: (submission['approval_subject'] ??
              'Your demo was approved, $artistName')
          .toString(),
    );
    final bodyController = TextEditingController(
      text: (submission['approval_body'] ??
              'Hi $artistName,\n\nThanks for sending your demo.\n\nWe reviewed it and would like to move forward with you. Please reply to this email so we can continue the next steps.\n\nBest regards')
          .toString(),
    );
    bool sendEmail = true;
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Approve demo'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: subjectController,
                    decoration:
                        const InputDecoration(labelText: 'Approval subject'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: bodyController,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Approval email body',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The submitter is added to Artists (new row or linked by email).',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    value: sendEmail,
                    onChanged: (value) =>
                        setStateDialog(() => sendEmail = value),
                    title: const Text('Send approval email now'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Approve'),
            ),
          ],
        ),
      ),
    );
    if (approved != true) {
      subjectController.dispose();
      bodyController.dispose();
      return;
    }
    try {
      await widget.apiClient.approveDemoSubmission(
        token: widget.token,
        id: id,
        approvalSubject: subjectController.text.trim(),
        approvalBody: bodyController.text,
        sendEmail: sendEmail,
      );
      await _loadDemoSubmissions(withOverlay: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(sendEmail
                ? 'Demo approved and email sent.'
                : 'Demo approved.')),
      );
    } catch (e) {
      _setError(e);
    } finally {
      subjectController.dispose();
      bodyController.dispose();
    }
  }

  Future<void> _showDemoDetailsDialog(Map<String, dynamic> submission) async {
    final id = submission['id'] as int?;
    if (id == null) return;
    final notesController = TextEditingController(
        text: (submission['admin_notes'] ?? '').toString());
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Demo #$id'),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _demoInfoRow(
                    'Artist', (submission['artist_name'] ?? '').toString()),
                _demoInfoRow('Email', (submission['email'] ?? '').toString()),
                _demoInfoRow(
                    'Contact', (submission['contact_name'] ?? '').toString()),
                _demoInfoRow('Phone', (submission['phone'] ?? '').toString()),
                _demoInfoRow('Genre', (submission['genre'] ?? '').toString()),
                _demoInfoRow('City', (submission['city'] ?? '').toString()),
                _demoInfoRow('Status', (submission['status'] ?? '').toString()),
                _demoInfoRow(
                  'Artist in system',
                  submission['artist_id'] != null
                      ? 'Existing artist (ID: ${submission['artist_id']})'
                      : 'New artist (not in system)',
                ),
                _demoInfoRow(
                    'Message', (submission['message'] ?? '').toString()),
                _demoInfoRow(
                  'Email consent',
                  submission['consent_to_emails'] == true
                      ? 'Yes${_formatDemoDate(submission['consent_at']) != null ? ' (${_formatDemoDate(submission['consent_at'])})' : ''}'
                      : 'No',
                ),
                _demoInfoRow('Source', (submission['source'] ?? '').toString()),
                if ((submission['source_site_url'] ?? '').toString().isNotEmpty)
                  _demoInfoRow('Source URL',
                      (submission['source_site_url'] ?? '').toString()),
                if (_formatDemoDate(submission['created_at']) != null)
                  _demoInfoRow('Submitted at',
                      _formatDemoDate(submission['created_at'])!),
                if (_formatDemoDate(submission['updated_at']) != null)
                  _demoInfoRow('Last updated',
                      _formatDemoDate(submission['updated_at'])!),
                if (_formatDemoDate(submission['approval_email_sent_at']) !=
                    null)
                  _demoInfoRow('Approval email sent',
                      _formatDemoDate(submission['approval_email_sent_at'])!),
                if (_formatDemoDate(submission['rejection_email_sent_at']) !=
                    null)
                  _demoInfoRow('Rejection email sent',
                      _formatDemoDate(submission['rejection_email_sent_at'])!),
                if (submission['has_demo_file'] == true) ...[
                  const SizedBox(height: 12),
                  const Text('Demo MP3',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  _DemoDownloadMp3Link(
                    demoId: id,
                    apiClient: widget.apiClient,
                    token: widget.token,
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Links',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ...(((submission['links'] as List<dynamic>? ??
                        const <dynamic>[]))
                    .map((link) => SelectableText(link.toString()))),
                if (_getSoundCloudUrls(submission).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('SoundCloud',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ..._getSoundCloudUrls(submission).map(
                    (url) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(url,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 4),
                          _SoundCloudEmbedWidget(soundCloudUrl: url),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('Extra fields',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                SelectableText(const JsonEncoder.withIndent('  ').convert(
                  submission['fields'] is Map<String, dynamic>
                      ? submission['fields']
                      : const <String, dynamic>{},
                )),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Admin notes',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save notes'),
          ),
        ],
      ),
    );
    if (result != true) {
      notesController.dispose();
      return;
    }
    try {
      await widget.apiClient.updateDemoSubmission(
        token: widget.token,
        id: id,
        body: {'admin_notes': notesController.text},
      );
      await _loadDemoSubmissions(withOverlay: false);
    } catch (e) {
      _setError(e);
    } finally {
      notesController.dispose();
    }
  }

  Future<void> _deleteDemoSubmission(Map<String, dynamic> submission) async {
    final id = submission['id'] as int?;
    if (id == null) return;
    final artistName = (submission['artist_name'] ?? '').toString();
    try {
      await widget.apiClient.deleteDemoSubmission(token: widget.token, id: id);
      await _loadDemoSubmissions(withOverlay: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Demo #$id${artistName.isNotEmpty ? ' ($artistName)' : ''} deleted.')),
      );
    } catch (e) {
      _setError(e);
    }
  }

  // ignore: unused_element - kept for potential reuse; tabs use ArtistsTab widget
  Widget _buildArtistsTab() {
    final query = _artistSearchQuery;
    final filtered = query.isEmpty
        ? artists
        : artists.where((a) {
            final artist = a as Map<String, dynamic>;
            final extra = artist['extra'] as Map<String, dynamic>? ?? {};
            final brand = (extra['artist_brand']?.toString().trim() ??
                    artist['name']?.toString() ??
                    '')
                .toLowerCase();
            final fullName =
                (extra['full_name']?.toString().trim() ?? '').toLowerCase();
            final email = (artist['email']?.toString() ?? '').toLowerCase();
            final brandsList = extra['artist_brands'];
            final brands = (brandsList is List
                    ? brandsList
                        .map((e) => (e?.toString().trim() ?? '').toLowerCase())
                        .where((s) => s.isNotEmpty)
                        .join(' ')
                    : '')
                .toLowerCase();
            return brand.contains(query) ||
                fullName.contains(query) ||
                email.contains(query) ||
                brands.contains(query);
          }).toList();

    final sortedArtists = List<dynamic>.from(filtered);
    sortedArtists.sort((a, b) {
      final ar = a as Map<String, dynamic>;
      final br = b as Map<String, dynamic>;
      final extraA = ar['extra'] as Map<String, dynamic>? ?? {};
      final extraB = br['extra'] as Map<String, dynamic>? ?? {};
      String va;
      String vb;
      switch (_artistsSortColumn) {
        case 0:
          va = (extraA['artist_brand']?.toString().trim() ??
                  ar['name']?.toString() ??
                  '')
              .toLowerCase();
          vb = (extraB['artist_brand']?.toString().trim() ??
                  br['name']?.toString() ??
                  '')
              .toLowerCase();
          break;
        case 1:
          va = (extraA['full_name']?.toString().trim() ?? '').toLowerCase();
          vb = (extraB['full_name']?.toString().trim() ?? '').toLowerCase();
          break;
        case 2:
          va = (ar['email']?.toString() ?? '').toLowerCase();
          vb = (br['email']?.toString() ?? '').toLowerCase();
          break;
        case 3:
          va = _artistLastRelease(ar).toLowerCase();
          vb = _artistLastRelease(br).toLowerCase();
          break;
        default:
          va = '';
          vb = '';
      }
      final cmp = _compareString(va, vb);
      return _artistsSortAsc ? cmp : -cmp;
    });

    const sideMargin = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 0.9;
        final height = constraints.maxHeight * 0.9;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        sideMargin, 12, sideMargin, 8),
                    child: TextField(
                      controller: _artistSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search artists (brand, name, email)...',
                        prefixIcon: const Icon(ZalmanimIcons.search),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        sideMargin, 8, sideMargin, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Artists',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => _showAddArtistDialog(),
                          icon: const Icon(ZalmanimIcons.add),
                          label: const Text('Add artist'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: artists.isEmpty
                              ? null
                              : () => _showMergeArtistsDialog(),
                          icon: const Icon(ZalmanimIcons.merge),
                          label: const Text('Merge artists'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: sideMargin),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Table(
                            columnWidths: const {
                              0: FixedColumnWidth(160),
                              1: FixedColumnWidth(160),
                              2: FixedColumnWidth(220),
                              3: FixedColumnWidth(180),
                              4: FixedColumnWidth(140),
                            },
                            defaultColumnWidth: const IntrinsicColumnWidth(),
                            children: [
                              TableRow(
                                decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest),
                                children: [
                                  _sortableHeader(context, 'Brand', 0),
                                  _sortableHeader(context, 'Full name', 1),
                                  _sortableHeader(context, 'Email', 2),
                                  _sortableHeader(context, 'Last Release', 3),
                                  const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 5),
                                      child: Text('',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold))),
                                ],
                              ),
                              ...sortedArtists.map<TableRow>((a) {
                                final artist = a as Map<String, dynamic>;
                                final id = artist['id'] as int?;
                                final extra =
                                    artist['extra'] as Map<String, dynamic>? ??
                                        {};
                                final brand =
                                    extra['artist_brand']?.toString().trim() ??
                                        artist['name']?.toString() ??
                                        '';
                                final fullName =
                                    extra['full_name']?.toString().trim() ?? '';
                                final email = artist['email']?.toString() ?? '';
                                final isActive =
                                    artist['is_active'] as bool? ?? true;
                                final displayName = brand.isEmpty
                                    ? (fullName.isEmpty ? 'Unknown' : fullName)
                                    : brand;
                                return TableRow(
                                  decoration: isActive
                                      ? null
                                      : BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.5)),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 9),
                                      child: Row(
                                        children: [
                                          if (!isActive)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  right: 6),
                                              child: Chip(
                                                label: const Text('Inactive',
                                                    style: TextStyle(
                                                        fontSize: 11)),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                          Expanded(
                                            child: ClipRect(
                                              child: SelectableText(
                                                brand.isEmpty ? '-' : brand,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 9),
                                      child: ClipRect(
                                        child: SelectableText(
                                          fullName.isEmpty ? '-' : fullName,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 9),
                                      child: ClipRect(
                                        child: SelectableText(
                                          email,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 9),
                                      child: ClipRect(
                                        child: SelectableText(
                                          _artistLastRelease(artist),
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 2, vertical: 5),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                                ZalmanimIcons.releases,
                                                color: Colors.blue,
                                                size: 22),
                                            tooltip: 'View releases',
                                            onPressed: id != null
                                                ? () => _showArtistReleases(
                                                    id, displayName)
                                                : null,
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(ZalmanimIcons.edit,
                                                color: Colors.orange, size: 22),
                                            tooltip: 'Edit',
                                            onPressed: id != null
                                                ? () => _showEditArtistDialog(
                                                      id,
                                                      initialArtist: Map<String,
                                                              dynamic>.from(
                                                          artist as Map),
                                                    )
                                                : null,
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                                ZalmanimIcons.delete,
                                                color: Colors.red,
                                                size: 22),
                                            tooltip: 'Remove',
                                            onPressed: id != null
                                                ? () => _removeArtist(
                                                    id, displayName)
                                                : null,
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static const List<Map<String, String>> _artistFormFields = [
    {'key': 'name', 'label': 'Name (display)'},
    {'key': 'email', 'label': 'Email'},
    {'key': 'artist_brand', 'label': 'Artist brand (primary)'},
    {
      'key': 'artist_brands',
      'label': 'Brands (comma-separated, all names that match this artist)'
    },
    {'key': 'full_name', 'label': 'Full name'},
    {'key': 'website', 'label': 'Website'},
    {'key': 'soundcloud', 'label': 'SoundCloud'},
    {'key': 'facebook', 'label': 'Facebook'},
    {'key': 'twitter_1', 'label': 'Twitter 1'},
    {'key': 'twitter_2', 'label': 'Twitter 2'},
    {'key': 'youtube', 'label': 'YouTube'},
    {'key': 'tiktok', 'label': 'TikTok'},
    {'key': 'instagram', 'label': 'Instagram'},
    {'key': 'spotify', 'label': 'Spotify'},
    {'key': 'other_1', 'label': 'Other 1'},
    {'key': 'other_2', 'label': 'Other 2'},
    {'key': 'other_3', 'label': 'Other 3'},
    {'key': 'comments', 'label': 'Comments'},
    {'key': 'apple_music', 'label': 'Apple Music'},
    {'key': 'address', 'label': 'Address'},
    {'key': 'source_row', 'label': 'Source row'},
    {'key': 'notes', 'label': 'Notes'},
  ];

  Future<void> _showAddArtistDialog() async {
    final controllers = <String, TextEditingController>{};
    for (final f in _artistFormFields) {
      controllers[f['key']!] = TextEditingController();
    }
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _buildArtistFormDialog(
        ctx,
        title: 'Add artist',
        controllers: controllers,
        isCreate: true,
      ),
    );
    for (final c in controllers.values) {
      c.dispose();
    }
    if (result == null) return;
    final name = (result['name'] as String?)?.trim() ?? '';
    final email = (result['email'] as String?)?.trim() ?? '';
    if (name.isEmpty || email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and email are required')),
        );
      }
      return;
    }
    try {
      await widget.apiClient.createArtist(token: widget.token, body: result);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Artist added')));
      _load();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showEditArtistDialog(
    int id, {
    Map<String, dynamic>? initialArtist,
  }) async {
    try {
      final artist = initialArtist ??
          artists
              .cast<Map?>()
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .firstWhere(
                (item) => _coerceArtistId(item['id']) == id,
                orElse: () => <String, dynamic>{},
              );
      final artistData = artist.isNotEmpty
          ? artist
          : await widget.apiClient.fetchArtist(widget.token, id);
      if (!mounted) return;
      final extra = artistData['extra'] as Map<String, dynamic>? ?? {};
      final controllers = <String, TextEditingController>{};
      for (final f in _artistFormFields) {
        final key = f['key']!;
        String value = '';
        if (key == 'name' || key == 'email' || key == 'notes') {
          value = artistData[key]?.toString() ?? '';
        } else if (key == 'artist_brands') {
          final list = extra['artist_brands'];
          value = list is List
              ? (list
                  .map((e) => e?.toString().trim())
                  .where((s) => s != null && s.isNotEmpty)
                  .join(', '))
              : (extra['artist_brand']?.toString().trim() ?? '');
        } else {
          value = extra[key]?.toString() ?? '';
        }
        controllers[key] = TextEditingController(text: value);
      }
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => _buildArtistFormDialog(
          ctx,
          title: 'Edit artist',
          controllers: controllers,
          isCreate: false,
          initialIsActive: artistData['is_active'] as bool? ?? true,
        ),
      );
      for (final c in controllers.values) {
        c.dispose();
      }
      if (result == null) return;
      final name = (result['name'] as String?)?.trim() ?? '';
      final email = (result['email'] as String?)?.trim() ?? '';
      if (name.isEmpty || email.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Name and email are required')),
          );
        }
        return;
      }
      await widget.apiClient
          .updateArtist(token: widget.token, id: id, body: result);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Artist updated')));
      _load();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showSetArtistPasswordDialog(
      int artistId, String artistName) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set artist portal password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Artist: $artistName',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              const Text(
                'Sets the password for artists.zalmanim.com. Artist signs in with their artist email and this password.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  border: OutlineInputBorder(),
                  hintText: 'Min 6 characters',
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final p = passwordController.text;
              final c = confirmController.text;
              if (p.length < 6) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Password must be at least 6 characters')));
                return;
              }
              if (p != c) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Passwords do not match')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Set password'),
          ),
        ],
      ),
    );
    final password = passwordController.text;
    passwordController.dispose();
    confirmController.dispose();
    if (result != true) return;
    try {
      await widget.apiClient.setArtistPassword(
        token: widget.token,
        artistId: artistId,
        password: password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Portal password set. Artist can sign in at artists.zalmanim.com.')));
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _sendArtistPortalInvite(
      int artistId, String artistName, String artistEmail) async {
    if (artistEmail.trim().isEmpty) {
      _showErrorSnackBar(
          'Artist email is required before sending portal access.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send artist portal access'),
        content: Text(
          'Send a portal access email to $artistName?\n\n'
          'The email will include the portal link, username ($artistEmail), a temporary password, and a short explanation of the portal.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send email')),
        ],
      ),
    );
    if (confirmed != true) return;
    final emailConfigured =
        await widget.apiClient.isEmailConfigured(widget.token);
    if (!mounted) return;
    if (!emailConfigured) {
      await _showEmailNotConfiguredDialog(context);
      return;
    }
    final allowSend = await _confirmSendToPreviouslyMailedAddress(
      email: artistEmail,
      actionLabel: 'portal access email',
    );
    if (!allowSend || !mounted) return;
    try {
      final result = await widget.apiClient.sendArtistPortalInvite(
        token: widget.token,
        artistId: artistId,
      );
      if (!mounted) return;
      final username = (result['username'] ?? artistEmail).toString();
      final portalUrl =
          (result['portal_url'] ?? 'https://artists.zalmanim.com').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Portal access sent to $username via $portalUrl.')),
      );
    } catch (e) {
      final msg = e.toString();
      final isNotConfigured = msg.contains('not configured') ||
          msg.contains('Email is not configured');
      final isNetworkFailure = msg.contains('Failed to fetch') ||
          msg.contains('ClientException') ||
          msg.contains('TimeoutException');
      if (isNotConfigured) {
        _showErrorSnackBar(
            '$msg\n\nGo to Settings → Mail to configure SMTP.');
      } else if (isNetworkFailure) {
        _showErrorSnackBar(
            '$msg\n\nNetwork or timeout. The server may be busy sending the email. Try again; if it persists, check the API is reachable.');
      } else {
        _showErrorSnackBar(msg);
      }
    }
  }

  Future<void> _showGrooverInviteDialog() async {
    final emailController = TextEditingController();
    final artistNameController = TextEditingController();
    final fullNameController = TextEditingController();
    final notesController = TextEditingController(
      text: 'Source: Groover',
    );
    bool sending = false;
    String? errorText;

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setStateDialog) => AlertDialog(
            title: const Text('Send Groover invite'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Enter the artist details from Groover. We will create the artist if needed and send a registration email with a portal onboarding form.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: artistNameController,
                      decoration: const InputDecoration(
                        labelText: 'Artist / stage name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'Internal notes',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You can edit the email wording in Settings → Email templates → Groover invite.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      SelectableText(errorText!,
                          style: const TextStyle(color: Colors.red)),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (emailController.text.trim().isEmpty) {
                          setStateDialog(
                              () => errorText = 'Email is required.');
                          return;
                        }
                        final emailConfigured = await widget.apiClient
                            .isEmailConfigured(widget.token);
                        if (!mounted || !ctx.mounted) return;
                        if (!emailConfigured) {
                          Navigator.of(ctx).pop();
                          await _showEmailNotConfiguredDialog(context);
                          return;
                        }
                        final allowSend =
                            await _confirmSendToPreviouslyMailedAddress(
                          email: emailController.text.trim(),
                          actionLabel: 'Groover invite',
                        );
                        if (!allowSend || !mounted || !ctx.mounted) return;
                        setStateDialog(() {
                          sending = true;
                          errorText = null;
                        });
                        try {
                          final result =
                              await widget.apiClient.sendGrooverInvite(
                            token: widget.token,
                            email: emailController.text.trim(),
                            artistName: artistNameController.text.trim().isEmpty
                                ? null
                                : artistNameController.text.trim(),
                            fullName: fullNameController.text.trim().isEmpty
                                ? null
                                : fullNameController.text.trim(),
                            notes: notesController.text.trim().isEmpty
                                ? null
                                : notesController.text.trim(),
                          );
                          if (!mounted || !ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          final createdArtist =
                              result['created_artist'] == true;
                          final registrationUrl =
                              (result['registration_url'] ?? '').toString();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${createdArtist ? 'Artist created and' : ''} Groover invite sent.${registrationUrl.isNotEmpty ? ' Registration link generated.' : ''}',
                              ),
                            ),
                          );
                          await loadArtists();
                        } catch (e) {
                          setStateDialog(() {
                            sending = false;
                            errorText =
                                e.toString().replaceFirst('Exception: ', '');
                          });
                        }
                      },
                child: Text(sending ? 'Sending...' : 'Send invite'),
              ),
            ],
          ),
        ),
      );
    } finally {
      emailController.dispose();
      artistNameController.dispose();
      fullNameController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _sendArtistPortalInviteToAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send portal invite to all artists'),
        content: const SelectableText(
          'Send a portal access email to every active artist that has an email address?\n\n'
          'Each will receive the portal link, their username, and a new temporary password. '
          'You can edit the email text in Settings → Email templates → Portal invite.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send to all')),
        ],
      ),
    );
    if (confirmed != true) return;
    final emailConfigured =
        await widget.apiClient.isEmailConfigured(widget.token);
    if (!mounted) return;
    if (!emailConfigured) {
      await _showEmailNotConfiguredDialog(context);
      return;
    }
    try {
      final result = await widget.apiClient
          .sendArtistPortalInviteToAll(token: widget.token);
      if (!mounted) return;
      final sent = result['sent'] as int? ?? 0;
      final failed = result['failed'] as int? ?? 0;
      final errorsRaw = result['errors'];
      final errors =
          errorsRaw is List ? List<dynamic>.from(errorsRaw) : <dynamic>[];
      if (failed > 0 && errors.isNotEmpty) {
        final errorText = errors
            .map((e) =>
                '${(e is Map ? e['email'] : '')}: ${(e is Map ? e['detail'] : '')}')
            .join('\n');
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Portal invites: $sent sent, $failed failed'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(errorText),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: errorText));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Errors copied to clipboard')));
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy errors'),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Portal invite sent to $sent artist(s).${failed > 0 ? ' $failed failed.' : ''}')),
        );
      }
      loadArtists();
    } catch (e) {
      final msg = e.toString();
      final isNotConfigured = msg.contains('not configured') ||
          msg.contains('Email is not configured');
      if (isNotConfigured) {
        _showErrorSnackBar(
            '$msg\n\nGo to Settings → Mail to configure SMTP.');
      } else {
        _showErrorSnackBar(msg);
      }
    }
  }

  Future<void> _sendArtistUpdateProfileInvite(
      int artistId, String artistName, String artistEmail) async {
    if (artistEmail.trim().isEmpty) {
      _showErrorSnackBar('Artist email is required.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Invite to update profile'),
        content: Text(
          'Send an email to $artistName inviting them to update their artist page and see their releases?\n\n'
          'The email will include the portal link. If they don\'t have a password yet, a temporary one will be set and sent.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Send email')),
        ],
      ),
    );
    if (confirmed != true) return;
    final emailConfigured =
        await widget.apiClient.isEmailConfigured(widget.token);
    if (!mounted) return;
    if (!emailConfigured) {
      await _showEmailNotConfiguredDialog(context);
      return;
    }
    final allowSend = await _confirmSendToPreviouslyMailedAddress(
      email: artistEmail,
      actionLabel: 'update profile invite',
    );
    if (!allowSend || !mounted) return;
    try {
      final result = await widget.apiClient.sendArtistUpdateProfileInvite(
        token: widget.token,
        artistId: artistId,
      );
      if (!mounted) return;
      final username = (result['username'] ?? artistEmail).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update profile invite sent to $username')),
      );
    } catch (e) {
      final msg = e.toString();
      final isNotConfigured = msg.contains('not configured') ||
          msg.contains('Email is not configured');
      final isNetworkFailure = msg.contains('Failed to fetch') ||
          msg.contains('ClientException') ||
          msg.contains('TimeoutException');
      if (isNotConfigured) {
        _showErrorSnackBar(
            '$msg\n\nGo to Settings → Mail to configure SMTP.');
      } else if (isNetworkFailure) {
        _showErrorSnackBar(
            '$msg\n\nNetwork or timeout. Try again; if it persists, check the API is reachable.');
      } else {
        _showErrorSnackBar(msg);
      }
    }
  }

  /// Shows a dialog when email is not configured; "Open Settings" switches to the Settings tab.
  Future<void> _showEmailNotConfiguredDialog(BuildContext context) async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Email not set up'),
        content: const SelectableText(
          'To send invite emails, configure SMTP in Settings → Mail.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings')),
        ],
      ),
    );
    if (openSettings == true && mounted) {
      _tabController.animateTo(6); // Settings tab
    }
  }

  Future<bool> _confirmSendToPreviouslyMailedAddress({
    required String email,
    required String actionLabel,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) return true;
    try {
      final history = await widget.apiClient.fetchEmailRecipientHistory(
        token: widget.token,
        email: normalizedEmail,
      );
      if (history['has_sent_before'] != true) return true;
      if (!mounted) return false;

      final sendCount = history['send_count'] as int? ?? 0;
      final lastSubject = (history['last_subject'] as String?)?.trim() ?? '';
      final lastSentAtRaw = history['last_sent_at'] as String?;
      var lastSentText = 'unknown time';
      if (lastSentAtRaw != null && lastSentAtRaw.isNotEmpty) {
        try {
          final dt = DateTime.parse(lastSentAtRaw).toLocal();
          lastSentText =
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } catch (_) {}
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Email already sent to this address'),
          content: SelectableText(
            'The system already sent $sendCount email(s) to $normalizedEmail.\n\n'
            'Last sent: $lastSentText'
            '${lastSubject.isNotEmpty ? '\nSubject: $lastSubject' : ''}\n\n'
            'Send another $actionLabel anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Send anyway'),
            ),
          ],
        ),
      );
      return confirm == true;
    } catch (_) {
      return true;
    }
  }

  Widget _buildArtistFormDialog(
    BuildContext ctx, {
    required String title,
    required Map<String, TextEditingController> controllers,
    required bool isCreate,
    bool initialIsActive = true,
  }) {
    final isActiveState = [initialIsActive];
    return StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final f in _artistFormFields) ...[
                    TextField(
                      controller: controllers[f['key']!],
                      decoration: InputDecoration(
                        labelText: f['label'],
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: f['key'] == 'email'
                          ? TextInputType.emailAddress
                          : null,
                      maxLines: (f['key'] == 'comments' ||
                              f['key'] == 'notes' ||
                              f['key'] == 'address')
                          ? 2
                          : 1,
                    ),
                    const SizedBox(height: 8),
                  ],
                  CheckboxListTile(
                    title: const Text('Active (artist can receive emails)'),
                    value: isActiveState[0],
                    onChanged: (v) {
                      setDialogState(() => isActiveState[0] = v ?? true);
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final body = <String, dynamic>{};
                for (final f in _artistFormFields) {
                  final key = f['key']!;
                  final v = controllers[key]?.text.trim() ?? '';
                  if (key == 'artist_brands') {
                    final list = v
                        .split(',')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    if (list.isNotEmpty) body[key] = list;
                    continue;
                  }
                  if (v.isEmpty) continue;
                  if (key == 'name' || key == 'email' || key == 'notes') {
                    body[key] = v;
                  } else {
                    body[key] = v;
                  }
                }
                body['is_active'] = isActiveState[0];
                Navigator.pop(ctx, body);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeArtist(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove artist?'),
        content: Text(
            'This will remove "$name". Artists linked to a user cannot be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.apiClient.deleteArtist(token: widget.token, id: id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Artist removed')));
      _load();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showMergeArtistsDialog() async {
    if (artists.isEmpty) return;
    int? targetId;
    final sourceIds = <int>{};

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            String artistDisplay(Map<String, dynamic> a) {
              final id = a['id'] as int?;
              final extra = a['extra'] as Map<String, dynamic>? ?? {};
              final brand = extra['artist_brand']?.toString().trim() ??
                  a['name']?.toString() ??
                  '';
              final list = extra['artist_brands'];
              final brandsStr = list is List
                  ? list
                      .map((e) => e?.toString().trim())
                      .where((s) => s != null && s.isNotEmpty)
                      .join(', ')
                  : '';
              if (brand.isNotEmpty) {
                return brandsStr.isNotEmpty && brandsStr != brand
                    ? '$brand ($brandsStr)'
                    : brand;
              }
              return brandsStr.isNotEmpty ? brandsStr : 'Artist ${id ?? '?'}';
            }

            return AlertDialog(
              title: const Text('Merge artists'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                        'Target artist (kept; all brands will be merged here):',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      initialValue: targetId,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(), isDense: true),
                      hint: const Text('Select target'),
                      items: [
                        for (final a in artists)
                          () {
                            final artist = a as Map<String, dynamic>;
                            final id = artist['id'] as int?;
                            if (id == null) {
                              return null as DropdownMenuItem<int>?;
                            }
                            return DropdownMenuItem<int>(
                                value: id, child: Text(artistDisplay(artist)));
                          }(),
                      ].whereType<DropdownMenuItem<int>>().toList(),
                      onChanged: (v) {
                        setDialogState(() {
                          targetId = v;
                          if (v != null) sourceIds.remove(v);
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                        'Source artists (merged into target, then deactivated):',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: artists.length,
                        itemBuilder: (_, i) {
                          final a = artists[i] as Map<String, dynamic>;
                          final id = a['id'] as int?;
                          if (id == null) return const SizedBox.shrink();
                          final isTarget = id == targetId;
                          return CheckboxListTile(
                            value: sourceIds.contains(id),
                            onChanged: isTarget
                                ? null
                                : (v) {
                                    setDialogState(() {
                                      if (v == true) {
                                        sourceIds.add(id);
                                      } else {
                                        sourceIds.remove(id);
                                      }
                                    });
                                  },
                            title: Text(artistDisplay(a)),
                            secondary: isTarget
                                ? const Chip(label: Text('Target'))
                                : null,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                FilledButton(
                  onPressed: targetId == null || sourceIds.isEmpty
                      ? null
                      : () => Navigator.pop(ctx,
                          {'target': targetId!, 'sources': sourceIds.toList()}),
                  child: const Text('Merge'),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || !mounted) return;
    final target = result['target'] as int?;
    final sources =
        (result['sources'] as List<dynamic>?)?.map((e) => e as int).toList() ??
            [];
    if (target == null || sources.isEmpty) return;
    try {
      setState(() => loading = true);
      await widget.apiClient.mergeArtists(
        token: widget.token,
        targetArtistId: target,
        sourceArtistIds: sources,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText(
              'Merged ${sources.length} artist(s) into target. Source artists deactivated.'),
          action: SnackBarAction(
              label: 'Copy',
              onPressed: () => Clipboard.setData(
                  ClipboardData(text: 'Merged ${sources.length} artist(s).'))),
        ),
      );
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _showArtistReleases(int artistId, String artistName) async {
    try {
      final releases =
          await widget.apiClient.fetchArtistReleases(widget.token, artistId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Releases: $artistName'),
          content: SizedBox(
            width: 400,
            child: releases.isEmpty
                ? const Text('No releases for this artist.')
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: releases.length,
                    itemBuilder: (_, i) {
                      final r = releases[i] as Map<String, dynamic>;
                      return ListTile(
                        leading: const Icon(ZalmanimIcons.music, size: 20),
                        title: SelectableText((r['title'] as String?) ?? ''),
                        subtitle:
                            SelectableText('Status: ${r['status'] ?? ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(ZalmanimIcons.personAdd, size: 22),
                              tooltip: 'Set artists',
                              onPressed: () {
                                Navigator.pop(ctx);
                                _showSetArtistsDialog(r);
                              },
                            ),
                            IconButton(
                              icon: const Icon(ZalmanimIcons.campaigns,
                                  color: Colors.blue, size: 22),
                              tooltip: 'Create campaign',
                              onPressed: () {
                                Navigator.pop(ctx);
                                _prepareCampaignFromRelease(
                                    artistId, artistName, r);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showArtistDetailsDialog(int artistId) async {
    Map<String, dynamic>? artistMap;
    try {
      artistMap = await widget.apiClient.fetchArtist(widget.token, artistId);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.toString());
      return;
    }
    if (!mounted) return;
    final extra = artistMap['extra'] as Map<String, dynamic>? ?? {};
    final displayName =
        (extra['artist_brand'] ?? artistMap['name'] ?? 'Artist').toString();

    await showDialog<void>(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          title: Text('Artist: $displayName', overflow: TextOverflow.ellipsis),
          content: SizedBox(
            width: 420,
            height: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Info'),
                    Tab(text: 'Logs'),
                  ],
                ),
                SizedBox(
                  height: 280,
                  child: TabBarView(
                    children: [
                      _ArtistInfoTab(
                        artistMap: artistMap!,
                        onEdit: () {
                          Navigator.pop(ctx);
                          _showEditArtistDialog(artistId,
                              initialArtist: artistMap);
                        },
                      ),
                      _ArtistLogsTab(
                        apiClient: widget.apiClient,
                        token: widget.token,
                        artistId: artistId,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      ),
    );
  }

  /// Show dialog to set one or more artists for a release (e.g. when sync did not match).
  Future<void> _showSetArtistsDialog(Map<String, dynamic> release) async {
    final releaseId = release['id'] as int?;
    final title = (release['title'] as String?) ?? 'Release';
    final currentIds = (release['artist_ids'] as List<dynamic>?)
            ?.map((e) => e as int)
            .toList() ??
        [];
    if (releaseId == null) return;

    try {
      if (_allArtistsForSelection.isEmpty) {
        if (mounted) setState(() => loading = true);
        await _ensureAllArtistsForSelectionLoaded();
      }
    } catch (e) {
      if (mounted) setState(() => loading = false);
      _showErrorSnackBar(e.toString());
      return;
    }
    if (mounted) setState(() => loading = false);

    final selectableArtists = artistsListForReleases;
    Set<int> selectedIds = Set<int>.from(currentIds);

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Set artists: $title'),
              content: SizedBox(
                width: 360,
                child: selectableArtists.isEmpty
                    ? const Text('No artists in the system.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: selectableArtists.length,
                        itemBuilder: (_, i) {
                          final a =
                              selectableArtists[i] as Map<String, dynamic>;
                          final id = a['id'] as int?;
                          if (id == null) return const SizedBox.shrink();
                          final name = (a['name'] as String?) ?? 'Artist $id';
                          final extra =
                              a['extra'] as Map<String, dynamic>? ?? {};
                          final brand =
                              extra['artist_brand']?.toString() ?? name;
                          return CheckboxListTile(
                            value: selectedIds.contains(id),
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) {
                                  selectedIds.add(id);
                                } else {
                                  selectedIds.remove(id);
                                }
                              });
                            },
                            title: Text(brand),
                            subtitle: extra['full_name']?.toString() != null &&
                                    extra['full_name'] != brand
                                ? Text(extra['full_name'] as String)
                                : null,
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel')),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true || !mounted) return;
    try {
      await widget.apiClient.updateReleaseArtists(
        token: widget.token,
        releaseId: releaseId,
        artistIds: selectedIds.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Artists updated')));
      _load();
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  /// Builds campaign brief text: artist details + release details + English prompt for social campaign.
  String _buildCampaignBrief(Map<String, dynamic>? artist, String artistName,
      Map<String, dynamic> release) {
    final buffer = StringBuffer();
    buffer.writeln('--- Artist ---');
    if (artist != null) {
      final extra = artist['extra'] as Map<String, dynamic>? ?? {};
      buffer.writeln('Name (display): ${artist['name'] ?? artistName}');
      buffer.writeln('Email: ${artist['email'] ?? ''}');
      buffer.writeln('Artist brand: ${extra['artist_brand'] ?? ''}');
      buffer.writeln('Full name: ${extra['full_name'] ?? ''}');
      buffer.writeln('Website: ${extra['website'] ?? ''}');
      buffer.writeln('Instagram: ${extra['instagram'] ?? ''}');
      buffer.writeln('Facebook: ${extra['facebook'] ?? ''}');
      buffer.writeln('Spotify: ${extra['spotify'] ?? ''}');
      buffer.writeln('SoundCloud: ${extra['soundcloud'] ?? ''}');
      buffer.writeln('YouTube: ${extra['youtube'] ?? ''}');
      buffer.writeln('TikTok: ${extra['tiktok'] ?? ''}');
    } else {
      buffer.writeln('Name: $artistName');
    }
    buffer.writeln('');
    buffer.writeln('--- Release ---');
    buffer.writeln('Title: ${release['title'] ?? ''}');
    buffer.writeln('Status: ${release['status'] ?? ''}');
    if (release['id'] != null) {
      buffer.writeln('Release ID: ${release['id']}');
    }
    if (release['created_at'] != null) {
      buffer.writeln('Created: ${release['created_at']}');
    }
    buffer.writeln('');
    buffer.writeln(
        'Prepare for me texts and images for a social media campaign.');
    return buffer.toString();
  }

  Future<void> _prepareCampaignFromRelease(
      int artistId, String artistName, Map<String, dynamic> release) async {
    Map<String, dynamic>? artist;
    for (final a in artists) {
      if (a is Map<String, dynamic> && a['id'] == artistId) {
        artist = a;
        break;
      }
    }
    final releaseTitle = (release['title'] as String?) ?? 'Release';
    final briefText = _buildCampaignBrief(artist, artistName, release);
    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Campaign brief: $releaseTitle'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Copy this text to use with an AI or tool to generate social posts and images.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 320,
                child: SingleChildScrollView(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: SelectableText(
                      briefText,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: briefText));
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            icon: const Icon(ZalmanimIcons.copy, size: 18),
            label: const Text('Copy'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'create'),
            icon: const Icon(ZalmanimIcons.add),
            label: const Text('Create campaign'),
          ),
        ],
      ),
    );
    if (result == 'create' && mounted) {
      await _showCreateCampaignDialog(
        initialName: 'Campaign: $releaseTitle',
        initialTitle: releaseTitle,
        initialBody: briefText,
        initialArtistId: artistId,
      );
    }
  }

  // ignore: unused_element - kept for potential reuse; tabs use ReportsTab widget
  Widget _buildReportsTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Reports',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Export and view reports (artists, releases, campaigns). More report types can be added here.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.personOff),
              title: const Text('Artist reminders'),
              subtitle: const Text(
                  'Artists with no catalog release in the last X months. Run report, send reminder emails.'),
              onTap: () => _showArtistRemindersReport(context),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.reports),
              title: const Text('Artists'),
              subtitle:
                  const Text('Artist list and data for DB import (e.g. CSV).'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Reports: export options coming soon.')),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.releases),
              title: const Text('Releases'),
              subtitle: const Text('Releases and catalog summary.'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Reports: export options coming soon.')),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(ZalmanimIcons.campaigns),
              title: const Text('Campaigns'),
              subtitle: const Text('Campaign history and delivery status.'),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Reports: export options coming soon.')),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showArtistRemindersReport(BuildContext context) async {
    if (!context.mounted) return;
    final width = MediaQuery.of(context).size.width * 0.95;
    showDialog<void>(
      context: context,
      builder: (ctx) => _ArtistRemindersDialog(
        apiClient: widget.apiClient,
        token: widget.token,
        dialogWidth: width,
        onSendEmailToSelected: (reportList, selectedIndices) {
          Navigator.of(ctx).pop();
          _showSendEmailToReportArtistsDialog(
              context, reportList, selectedIndices);
        },
        showErrorSnackBar: _showErrorSnackBar,
      ),
    );
  }

  Future<void> _showSignedInArtistsReport(BuildContext context) async {
    if (!context.mounted) return;
    final width = MediaQuery.of(context).size.width * 0.95;
    showDialog<void>(
      context: context,
      builder: (_) => SignedInArtistsReportDialog(
        apiClient: widget.apiClient,
        token: widget.token,
        dialogWidth: width,
      ),
    );
  }

  Future<void> _showSendEmailToReportArtistsDialog(BuildContext context,
      List<dynamic> reportList, List<int> selectedIndices) async {
    final savedSubject = await getArtistReminderEmailSubject();
    final savedBody = await getArtistReminderEmailBody();
    final subjectController =
        TextEditingController(text: savedSubject ?? _defaultReminderSubject);
    final bodyController =
        TextEditingController(text: savedBody ?? _defaultReminderBody);
    final sent = <String>[];
    final failed = <String, String>{};

    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send personal email'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 680,
            child: _ReminderTemplateEditor(
              subjectController: subjectController,
              bodyController: bodyController,
              previewValues: _sampleReminderTemplateValues,
              helperText:
                  'Subject and body support dynamic artist fields. The body is sent as HTML, with a text fallback generated automatically.',
              footerText:
                  '${selectedIndices.length} artist(s) will receive this email.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(ZalmanimIcons.send, size: 18),
            label: Text('Send to ${selectedIndices.length} artist(s)'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    final subjectTemplate = subjectController.text.trim();
    final bodyTemplate = bodyController.text;
    subjectController.dispose();
    bodyController.dispose();

    if (subjectTemplate.isEmpty) {
      _showErrorSnackBar('Subject is required.');
      return;
    }

    VoidCallback? refreshProgress;
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setProgressState) {
          refreshProgress = () => setProgressState(() {});
          return AlertDialog(
            title: const Text('Sending emails...'),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sent: ${sent.length} - Failed: ${failed.length}'),
                  if (failed.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...failed.entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: SelectableText('${e.key}: ${e.value}',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.red)),
                        )),
                  ],
                ],
              ),
            ),
            actions: sent.length + failed.length >= selectedIndices.length
                ? [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Close'),
                    ),
                  ]
                : null,
          );
        },
      ),
    );

    for (final i in selectedIndices) {
      if (i < 0 || i >= reportList.length) continue;
      final a = reportList[i] as Map<String, dynamic>;
      final values = _buildReminderTemplateValues(a);
      final email = (a['email'] ?? '').toString().trim();
      final displayName =
          values['name']?.isNotEmpty == true ? values['name']! : email;
      if (email.isEmpty) {
        failed[displayName] = 'No email';
        refreshProgress?.call();
        continue;
      }
      final rendered = _renderReminderEmail(
        subjectTemplate: subjectTemplate,
        bodyTemplate: bodyTemplate,
        values: values,
      );
      final artistId = a['id'] is int ? a['id'] as int : null;
      try {
        await widget.apiClient.sendEmail(
          token: widget.token,
          toEmail: email,
          subject: rendered.subject,
          bodyText: rendered.bodyText,
          bodyHtml: rendered.bodyHtml,
          artistId: artistId,
        );
        if (!context.mounted) return;
        sent.add(email);
      } catch (e) {
        if (!context.mounted) return;
        failed[email] = e.toString();
      }
      refreshProgress?.call();
    }

    if (!context.mounted) return;
    Navigator.of(context).pop();
    final total = selectedIndices.length;
    if (failed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email sent to $total artist(s).')));
    } else {
      _showErrorSnackBar(
          'Sent: ${sent.length}, Failed: ${failed.length}. ${failed.entries.map((e) => '${e.key}: ${e.value}').join('; ')}');
    }
  }

  // ignore: unused_element - kept for potential reuse; tabs use ReleasesTab widget
  Widget _buildReleasesTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Catalog (Releases)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            'Catalog metadata from Proton export. Import CSV, then Sync to artists to create releases. Schema: Catalog Number, Release Title, Pre-Order/Release Date, UPC, ISRC, Artists, Track Title, Mix, Duration.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => _importCatalogCsv(),
                icon: const Icon(ZalmanimIcons.upload),
                label: const Text('Import CSV'),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty
                    ? null
                    : () => _syncReleasesFromCatalog(),
                icon: const Icon(ZalmanimIcons.sync),
                label: const Text('Sync to artists'),
                style: FilledButton.styleFrom(
                  backgroundColor: catalogTracks.isEmpty
                      ? null
                      : Theme.of(context).colorScheme.tertiary,
                ),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty
                    ? null
                    : () => _syncOriginalArtistsFromArtists(),
                icon: const Icon(ZalmanimIcons.sync),
                label: const Text('Original Artist <- Brand'),
              ),
              FilledButton.icon(
                onPressed: catalogTracks.isEmpty
                    ? null
                    : () => _createMissingOriginalArtists(),
                icon: const Icon(ZalmanimIcons.personAdd),
                label: const Text('Create missing artists'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (catalogTracks.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _releasesSearchController,
                    decoration: InputDecoration(
                      hintText:
                          'Search releases by catalog #, title, artist, ISRC, UPC, mix...',
                      prefixIcon: const Icon(ZalmanimIcons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                if (_releasesSearchQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text(
                      '${_filteredCatalogTracks.length} of ${catalogTracks.length}',
                      style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (catalogTracks.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text(
                      'No catalog tracks. Use Import CSV to load a Proton catalog export.')),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: DataTable(
                  sortColumnIndex: _catalogSortColumnIndex,
                  sortAscending: _catalogSortAsc,
                  columns: [
                    _dataColumn('Catalog #', 0),
                    _dataColumn('Release', 1),
                    _dataColumn('Release Date', 2),
                    _dataColumn('UPC', 3),
                    _dataColumn('ISRC', 4),
                    _dataColumn('Original Artists', 5),
                    _dataColumn('Track', 6),
                    _dataColumn('Mix', 7),
                    _dataColumn('Duration', 8),
                  ],
                  rows: _sortedCatalogTracks.map<DataRow>((e) {
                    final t = e as Map<String, dynamic>;
                    return DataRow(
                      cells: [
                        DataCell(SelectableText(
                            (t['catalog_number'] as String?) ?? '')),
                        DataCell(SelectableText(
                            (t['release_title'] as String?) ?? '')),
                        DataCell(SelectableText(
                            (t['release_date'] as String?) ?? '')),
                        DataCell(SelectableText((t['upc'] as String?) ?? '')),
                        DataCell(SelectableText((t['isrc'] as String?) ?? '')),
                        DataCell(SelectableText(
                            (t['original_artists'] as String?) ?? '')),
                        DataCell(SelectableText(
                            (t['track_title'] as String?) ?? '')),
                        DataCell(
                            SelectableText((t['mix_title'] as String?) ?? '')),
                        DataCell(
                            SelectableText((t['duration'] as String?) ?? '')),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Text('Releases (from API)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Text('Sort (after unassigned):',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _releasesSortBy,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Title')),
                  DropdownMenuItem(value: 1, child: Text('Date')),
                ],
                onChanged: (v) => setState(() => _releasesSortBy = v ?? 0),
              ),
              IconButton(
                icon: Icon(
                    _releasesSortAsc
                        ? ZalmanimIcons.arrowUp
                        : ZalmanimIcons.arrowDown,
                    size: 18),
                tooltip: _releasesSortAsc ? 'Ascending' : 'Descending',
                onPressed: () =>
                    setState(() => _releasesSortAsc = !_releasesSortAsc),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Releases without an artist are highlighted in orange. Use "Associate with artist" to link a release to an artist.',
            style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (adminReleases.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Text(
                  'No releases yet. Import catalog above and use Sync to artists to create releases.'),
            )
          else
            ..._sortedAdminReleases.map<Widget>((r) {
              final release = r as Map<String, dynamic>;
              final releaseTitle = (release['title'] as String?) ?? '';
              final artistIds = (release['artist_ids'] as List<dynamic>?) ?? [];
              final hasNoArtist = artistIds.isEmpty;
              final artistNames = artistIds.map((id) {
                for (final a in artists) {
                  if (a is Map<String, dynamic> && a['id'] == id) {
                    final extra = a['extra'] as Map<String, dynamic>? ?? {};
                    return (extra['artist_brand'] ?? a['name'] ?? 'Artist $id')
                        .toString();
                  }
                }
                return 'Artist $id';
              }).join(', ');
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color:
                    hasNoArtist ? Colors.orange.withValues(alpha: 0.12) : null,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: hasNoArtist
                      ? const BorderSide(color: Colors.orange, width: 2)
                      : BorderSide(color: Theme.of(context).dividerColor),
                ),
                child: ListTile(
                  title: SelectableText(releaseTitle),
                  subtitle: SelectableText(
                    hasNoArtist ? 'No artist assigned' : artistNames,
                  ),
                  trailing: OutlinedButton.icon(
                    icon: const Icon(ZalmanimIcons.personAdd, size: 18),
                    label: const Text('Associate with artist'),
                    onPressed: () => _showSetArtistsDialog(release),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _importCatalogCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.single;
      setState(() => loading = true);
      // Use bytes only: on web path is unavailable and accessing it throws (file_picker FAQ).
      if (f.bytes != null && f.bytes!.isNotEmpty) {
        await widget.apiClient.importCatalogCsv(
          token: widget.token,
          fileBytes: f.bytes!,
          filename: f.name,
        );
      } else {
        setState(() {
          loading = false;
          error = 'Could not read file. Ensure you pick a CSV file.';
        });
        return;
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catalog CSV imported successfully.')),
      );
    } catch (e) {
      final msg = e.toString();
      if (!mounted) return;
      final isNetworkFailure =
          msg.contains('Failed to fetch') || msg.contains('ClientException');
      final hint = isNetworkFailure
          ? 'Request failed (network/CORS). Ensure the API is running at ${widget.apiClient.baseUrl} (e.g. run the backend or: docker compose up -d).\n\n$msg'
          : msg;
      setState(() {
        loading = false;
        error = hint;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText(hint),
          action: SnackBarAction(
            label: 'Copy',
            onPressed: () => Clipboard.setData(ClipboardData(text: hint)),
          ),
        ),
      );
    }
  }

  Future<void> _syncReleasesFromCatalog() async {
    try {
      setState(() => loading = true);
      final result =
          await widget.apiClient.syncReleasesFromCatalog(widget.token);
      await _load();
      if (!mounted) return;
      final message = result['message'] as String? ?? 'Sync completed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText(message),
          action: SnackBarAction(
            label: 'Copy',
            onPressed: () => Clipboard.setData(ClipboardData(text: message)),
          ),
        ),
      );
    } catch (e) {
      final msg = e.toString();
      if (!mounted) return;
      setState(() => loading = false);
      _showErrorSnackBar(msg);
    }
  }

  Future<void> _syncOriginalArtistsFromArtists() async {
    try {
      setState(() => loading = true);
      final result =
          await widget.apiClient.syncOriginalArtistsFromArtists(widget.token);
      await _load();
      if (!mounted) return;
      final message = result['message'] as String? ?? 'Sync completed.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText(message),
          action: SnackBarAction(
            label: 'Copy',
            onPressed: () => Clipboard.setData(ClipboardData(text: message)),
          ),
        ),
      );
    } catch (e) {
      final msg = e.toString();
      if (!mounted) return;
      setState(() => loading = false);
      _showErrorSnackBar(msg);
    }
  }

  Future<void> _createMissingOriginalArtists() async {
    try {
      setState(() => loading = true);
      final result =
          await widget.apiClient.createMissingOriginalArtists(widget.token);
      await _load();
      if (!mounted) return;
      final message = result['message'] as String? ?? 'Done.';
      final created = result['created'] as int? ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText('$message (created: $created)'),
          action: SnackBarAction(
            label: 'Copy',
            onPressed: () => Clipboard.setData(ClipboardData(text: message)),
          ),
        ),
      );
    } catch (e) {
      final msg = e.toString();
      if (!mounted) return;
      setState(() => loading = false);
      _showErrorSnackBar(msg);
    }
  }

  // ignore: unused_element - kept for potential reuse; tabs use CampaignsTab widget
  Widget _buildCampaignsTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text(
            'Unified Campaigns',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Send one content to social, Mailchimp, and WordPress. Create draft, then schedule or send now.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () => _showCreateCampaignDialog(),
                icon: const Icon(ZalmanimIcons.add),
                label: const Text('Create campaign'),
              ),
              const SizedBox(width: 24),
              Text('Sort by:',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _campaignsSortBy,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Name')),
                  DropdownMenuItem(value: 1, child: Text('Scheduled date')),
                  DropdownMenuItem(value: 2, child: Text('Sent date')),
                  DropdownMenuItem(value: 3, child: Text('Status')),
                ],
                onChanged: (v) => setState(() => _campaignsSortBy = v ?? 0),
              ),
              IconButton(
                icon: Icon(
                    _campaignsSortAsc
                        ? ZalmanimIcons.arrowUp
                        : ZalmanimIcons.arrowDown,
                    size: 18),
                tooltip: _campaignsSortAsc ? 'Ascending' : 'Descending',
                onPressed: () =>
                    setState(() => _campaignsSortAsc = !_campaignsSortAsc),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (campaigns.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                  child: Text('No campaigns yet. Create one to get started.')),
            )
          else
            ..._sortedCampaigns.map((c) {
              final campaign = c as Map<String, dynamic>;
              final status = campaign['status'] as String? ?? 'draft';
              final name = campaign['name'] as String? ?? 'Unnamed';
              final scheduledAt = campaign['scheduled_at'] as String?;
              final sentAt = campaign['sent_at'] as String?;
              final id = campaign['id'] as int;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(name),
                  subtitle: Text(
                    'Status: $status'
                    '${scheduledAt != null ? ' ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¾ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¾ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¾ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· Scheduled: $scheduledAt' : ''}'
                    '${sentAt != null ? ' ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¾ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¾ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¾ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· Sent: $sentAt' : ''}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (status == 'draft' || status == 'scheduled') ...[
                        if (status == 'draft')
                          TextButton(
                            onPressed: () => _showScheduleCampaignDialog(id),
                            child: const Text('Schedule'),
                          ),
                        if (status == 'scheduled')
                          TextButton(
                            onPressed: () => _cancelCampaignSchedule(id),
                            child: const Text('Cancel schedule'),
                          ),
                        if (status == 'draft' || status == 'scheduled')
                          IconButton(
                            icon: const Icon(ZalmanimIcons.edit,
                                color: Colors.orange),
                            tooltip: 'Edit',
                            onPressed: () => _showEditCampaignDialog(campaign),
                          ),
                        if (status == 'draft' || status == 'failed')
                          IconButton(
                            icon: const Icon(ZalmanimIcons.delete,
                                color: Colors.red),
                            tooltip: 'Delete',
                            onPressed: () => _deleteCampaign(id, name),
                          ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showCreateCampaignDialog({
    String? initialName,
    String? initialTitle,
    String? initialBody,
    int? initialArtistId,
  }) async {
    final nameController = TextEditingController(text: initialName ?? '');
    final titleController = TextEditingController(text: initialTitle ?? '');
    final bodyController = TextEditingController(text: initialBody ?? '');
    final mediaUrlController = TextEditingController();
    final selectedSocialIds = <int>{};
    final preFilledArtistId = initialArtistId;
    int? selectedMailchimpConnectorId;
    String? selectedMailchimpListId;
    int? selectedWordPressConnectorId;
    List<dynamic> mailchimpLists = [];

    if (!mounted) return;
    final isSaving = ValueNotifier<bool>(false);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void loadMailchimpLists(int connectorId) {
            setDialogState(() {
              mailchimpLists = [];
              selectedMailchimpListId = null;
            });
          }

          return AlertDialog(
            title: const Text('Create campaign'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Campaign name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                          labelText: 'Title (subject / post title)'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bodyController,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Body text'),
                    ),
                    const SizedBox(height: 8),
                    const Text('Image (optional)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (result == null || result.files.isEmpty) return;
                            final f = result.files.single;
                            if (f.bytes == null || f.bytes!.isEmpty) return;
                            try {
                              final data =
                                  await widget.apiClient.uploadCampaignMedia(
                                token: widget.token,
                                fileBytes: f.bytes!,
                                filename:
                                    (f.name.isEmpty ? 'image.jpg' : f.name),
                              );
                              final url = data['url'] as String?;
                              if (url != null &&
                                  url.isNotEmpty &&
                                  ctx.mounted) {
                                mediaUrlController.text = url;
                                setDialogState(() {});
                              }
                            } catch (e) {
                              if (ctx.mounted) _showErrorSnackBar(e.toString());
                            }
                          },
                          icon: const Icon(ZalmanimIcons.addPhoto, size: 20),
                          label: const Text('Add image'),
                        ),
                        if (mediaUrlController.text.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                mediaUrlController.text.trim(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(ZalmanimIcons.brokenImage),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(ZalmanimIcons.clear),
                            tooltip: 'Remove image',
                            onPressed: () {
                              mediaUrlController.clear();
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: mediaUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Image URL (or paste link)',
                        hintText: 'https://...',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Text('Social connections',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ...connections
                        .where((c) => (c['status'] as String?) == 'connected')
                        .map((conn) {
                      final connMap = conn;
                      final connId = connMap['id'] as int;
                      final label =
                          '${connMap['provider']} | ${connMap['account_label']}';
                      return CheckboxListTile(
                        value: selectedSocialIds.contains(connId),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedSocialIds.add(connId);
                            } else {
                              selectedSocialIds.remove(connId);
                            }
                          });
                        },
                        title:
                            Text(label, style: const TextStyle(fontSize: 14)),
                      );
                    }),
                    const SizedBox(height: 8),
                    const Text('Mailchimp',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<int?>(
                      value: selectedMailchimpConnectorId,
                      isExpanded: true,
                      hint: const Text('Select Mailchimp connector'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('None')),
                        ...hubConnectors
                            .where((c) =>
                                (c['connector_type'] as String?) == 'mailchimp')
                            .map((conn) {
                          final id = conn['id'] as int;
                          return DropdownMenuItem(
                            value: id,
                            child: Text(conn['account_label'] as String? ??
                                'Connector $id'),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          selectedMailchimpConnectorId = v;
                          if (v != null) loadMailchimpLists(v);
                        });
                      },
                    ),
                    if (selectedMailchimpConnectorId != null &&
                        mailchimpLists.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      DropdownButton<String?>(
                        value: selectedMailchimpListId,
                        isExpanded: true,
                        hint: const Text('Select audience (list)'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('None')),
                          ...mailchimpLists.map((li) {
                            final listMap = li;
                            return DropdownMenuItem(
                              value: listMap['id'] as String?,
                              child: Text(
                                '${listMap['name']} (${listMap['member_count'] ?? 0} members)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => selectedMailchimpListId = v),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text('WordPress',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<int?>(
                      value: selectedWordPressConnectorId,
                      isExpanded: true,
                      hint: const Text('Select WordPress connector'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('None')),
                        ...hubConnectors
                            .where((c) =>
                                (c['connector_type'] as String?) ==
                                'wordpress_codex')
                            .map((conn) {
                          final id = conn['id'] as int;
                          return DropdownMenuItem(
                            value: id,
                            child: Text(conn['account_label'] as String? ??
                                'Connector $id'),
                          );
                        }),
                      ],
                      onChanged: (v) => setDialogState(
                          () => selectedWordPressConnectorId = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ValueListenableBuilder<bool>(
                valueListenable: isSaving,
                builder: (_, saving, __) => FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final title = titleController.text.trim();
                          final bodyText = bodyController.text.trim();
                          if (name.isEmpty || title.isEmpty) {
                            _showErrorSnackBar('Name and title are required.');
                            return;
                          }
                          final targets = <Map<String, dynamic>>[];
                          for (final id in selectedSocialIds) {
                            targets.add({
                              'channel_type': 'social',
                              'external_id': id.toString(),
                              'channel_payload': <String, dynamic>{},
                            });
                          }
                          if (selectedMailchimpConnectorId != null &&
                              selectedMailchimpListId != null) {
                            targets.add({
                              'channel_type': 'mailchimp',
                              'external_id':
                                  selectedMailchimpConnectorId.toString(),
                              'channel_payload': {
                                'list_id': selectedMailchimpListId
                              },
                            });
                          }
                          if (selectedWordPressConnectorId != null) {
                            targets.add({
                              'channel_type': 'wordpress',
                              'external_id':
                                  selectedWordPressConnectorId.toString(),
                              'channel_payload': <String, dynamic>{},
                            });
                          }
                          if (targets.isEmpty) {
                            _showErrorSnackBar(
                                'Select at least one target (social, Mailchimp, or WordPress).');
                            return;
                          }
                          isSaving.value = true;
                          setDialogState(() {});
                          try {
                            await widget.apiClient.createCampaign(
                              token: widget.token,
                              name: name,
                              title: title,
                              bodyText: bodyText,
                              mediaUrl: mediaUrlController.text.trim().isEmpty
                                  ? null
                                  : mediaUrlController.text.trim(),
                              artistId: preFilledArtistId,
                              targets: targets,
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx, true);
                          } catch (e) {
                            if (ctx.mounted) _showErrorSnackBar(e.toString());
                          } finally {
                            isSaving.value = false;
                            if (ctx.mounted) setDialogState(() {});
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Create draft'),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _showEditCampaignDialog(Map<String, dynamic> campaign) async {
    final id = campaign['id'] as int;
    final nameController =
        TextEditingController(text: campaign['name'] as String?);
    final titleController =
        TextEditingController(text: campaign['title'] as String?);
    final bodyController =
        TextEditingController(text: campaign['body_text'] as String?);
    final mediaUrlController =
        TextEditingController(text: campaign['media_url'] as String? ?? '');
    final targetsIn = campaign['targets'] as List<dynamic>? ?? [];
    final selectedSocialIds = <int>{};
    int? selectedMailchimpConnectorId;
    String? selectedMailchimpListId;
    int? selectedWordPressConnectorId;
    List<dynamic> mailchimpLists = [];

    for (final t in targetsIn) {
      final m = t as Map<String, dynamic>;
      final type = m['channel_type'] as String?;
      final extId = m['external_id'] as String?;
      if (type == 'social' && extId != null) {
        selectedSocialIds.add(int.tryParse(extId) ?? 0);
      } else if (type == 'mailchimp' && extId != null) {
        selectedMailchimpConnectorId = int.tryParse(extId);
        final payload = m['channel_payload'] as Map<String, dynamic>? ?? {};
        selectedMailchimpListId = payload['list_id'] as String?;
      } else if (type == 'wordpress' && extId != null) {
        selectedWordPressConnectorId = int.tryParse(extId);
      }
    }

    void loadMailchimpLists(int connectorId) {
      setState(() {
        mailchimpLists = [];
      });
    }

    if (selectedMailchimpConnectorId != null) {
      loadMailchimpLists(selectedMailchimpConnectorId);
    }

    if (!mounted) return;
    final isSavingEdit = ValueNotifier<bool>(false);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit campaign'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Campaign name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: bodyController,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Body text'),
                    ),
                    const SizedBox(height: 8),
                    const Text('Image (optional)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                              withData: true,
                            );
                            if (result == null || result.files.isEmpty) return;
                            final f = result.files.single;
                            if (f.bytes == null || f.bytes!.isEmpty) return;
                            try {
                              final data =
                                  await widget.apiClient.uploadCampaignMedia(
                                token: widget.token,
                                fileBytes: f.bytes!,
                                filename:
                                    (f.name.isEmpty ? 'image.jpg' : f.name),
                              );
                              final url = data['url'] as String?;
                              if (url != null &&
                                  url.isNotEmpty &&
                                  ctx.mounted) {
                                mediaUrlController.text = url;
                                setDialogState(() {});
                              }
                            } catch (e) {
                              if (ctx.mounted) _showErrorSnackBar(e.toString());
                            }
                          },
                          icon: const Icon(ZalmanimIcons.addPhoto, size: 20),
                          label: const Text('Add image'),
                        ),
                        if (mediaUrlController.text.trim().isNotEmpty) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 64,
                            height: 64,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                mediaUrlController.text.trim(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(ZalmanimIcons.brokenImage),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(ZalmanimIcons.clear),
                            tooltip: 'Remove image',
                            onPressed: () {
                              mediaUrlController.clear();
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: mediaUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Image URL (or paste link)',
                        hintText: 'https://...',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Text('Social connections',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ...connections
                        .where((c) => (c['status'] as String?) == 'connected')
                        .map((conn) {
                      final connMap = conn;
                      final connId = connMap['id'] as int;
                      final label =
                          '${connMap['provider']} | ${connMap['account_label']}';
                      return CheckboxListTile(
                        value: selectedSocialIds.contains(connId),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedSocialIds.add(connId);
                            } else {
                              selectedSocialIds.remove(connId);
                            }
                          });
                        },
                        title:
                            Text(label, style: const TextStyle(fontSize: 14)),
                      );
                    }),
                    const SizedBox(height: 8),
                    const Text('Mailchimp',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<int?>(
                      value: selectedMailchimpConnectorId,
                      isExpanded: true,
                      hint: const Text('Select Mailchimp connector'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('None')),
                        ...hubConnectors
                            .where((c) =>
                                (c['connector_type'] as String?) == 'mailchimp')
                            .map((conn) {
                          final id = conn['id'] as int;
                          return DropdownMenuItem(
                            value: id,
                            child: Text(conn['account_label'] as String? ??
                                'Connector $id'),
                          );
                        }),
                      ],
                      onChanged: (v) {
                        setDialogState(() {
                          selectedMailchimpConnectorId = v;
                          if (v != null) loadMailchimpLists(v);
                        });
                      },
                    ),
                    if (selectedMailchimpConnectorId != null &&
                        mailchimpLists.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      DropdownButton<String?>(
                        value: selectedMailchimpListId,
                        isExpanded: true,
                        hint: const Text('Select audience (list)'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('None')),
                          ...mailchimpLists.map((li) {
                            final listMap = li;
                            return DropdownMenuItem(
                              value: listMap['id'] as String?,
                              child: Text(
                                '${listMap['name']} (${listMap['member_count'] ?? 0} members)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                        ],
                        onChanged: (v) =>
                            setDialogState(() => selectedMailchimpListId = v),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text('WordPress',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<int?>(
                      value: selectedWordPressConnectorId,
                      isExpanded: true,
                      hint: const Text('Select WordPress connector'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('None')),
                        ...hubConnectors
                            .where((c) =>
                                (c['connector_type'] as String?) ==
                                'wordpress_codex')
                            .map((conn) {
                          final id = conn['id'] as int;
                          return DropdownMenuItem(
                            value: id,
                            child: Text(conn['account_label'] as String? ??
                                'Connector $id'),
                          );
                        }),
                      ],
                      onChanged: (v) => setDialogState(
                          () => selectedWordPressConnectorId = v),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ValueListenableBuilder<bool>(
                valueListenable: isSavingEdit,
                builder: (_, saving, __) => FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final title = titleController.text.trim();
                          final bodyText = bodyController.text.trim();
                          if (name.isEmpty || title.isEmpty) {
                            _showErrorSnackBar('Name and title are required.');
                            return;
                          }
                          final targets = <Map<String, dynamic>>[];
                          for (final id in selectedSocialIds) {
                            targets.add({
                              'channel_type': 'social',
                              'external_id': id.toString(),
                              'channel_payload': <String, dynamic>{},
                            });
                          }
                          if (selectedMailchimpConnectorId != null &&
                              selectedMailchimpListId != null) {
                            targets.add({
                              'channel_type': 'mailchimp',
                              'external_id':
                                  selectedMailchimpConnectorId.toString(),
                              'channel_payload': {
                                'list_id': selectedMailchimpListId
                              },
                            });
                          }
                          if (selectedWordPressConnectorId != null) {
                            targets.add({
                              'channel_type': 'wordpress',
                              'external_id':
                                  selectedWordPressConnectorId.toString(),
                              'channel_payload': <String, dynamic>{},
                            });
                          }
                          if (targets.isEmpty) {
                            _showErrorSnackBar('Select at least one target.');
                            return;
                          }
                          isSavingEdit.value = true;
                          setDialogState(() {});
                          try {
                            await widget.apiClient.updateCampaign(
                              token: widget.token,
                              id: id,
                              name: name,
                              title: title,
                              bodyText: bodyText,
                              mediaUrl: mediaUrlController.text.trim(),
                              targets: targets,
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx, true);
                          } catch (e) {
                            if (ctx.mounted) _showErrorSnackBar(e.toString());
                          } finally {
                            isSavingEdit.value = false;
                            if (ctx.mounted) setDialogState(() {});
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save'),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _showScheduleCampaignDialog(int campaignId) async {
    if (!mounted) return;
    // Result: null = cancel, true = send now, DateTime = schedule at (local time, convert to UTC for API)
    final result = await showDialog<Object>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Schedule campaign'),
        content: const Text(
          'Send now (worker will pick it up within about a minute) or choose a date and time to schedule.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send now'),
          ),
          FilledButton(
            onPressed: () async {
              final date = await showDatePicker(
                context: ctx,
                initialDate: DateTime.now().add(const Duration(days: 1)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date == null || !ctx.mounted) return;
              final time = await showTimePicker(
                context: ctx,
                initialTime: const TimeOfDay(hour: 10, minute: 0),
              );
              if (time == null || !ctx.mounted) return;
              final scheduledAt = DateTime(
                  date.year, date.month, date.day, time.hour, time.minute);
              Navigator.pop(ctx, scheduledAt);
            },
            child: const Text('Schedule for later'),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      setState(() => loading = true);
      if (result == true) {
        await widget.apiClient
            .scheduleCampaign(token: widget.token, id: campaignId);
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: SelectableText(
                  'Campaign scheduled to send now. Worker will process it shortly.')),
        );
      } else if (result is DateTime) {
        await widget.apiClient.scheduleCampaign(
          token: widget.token,
          id: campaignId,
          scheduledAt: result,
        );
        await _load();
        if (!mounted) return;
        final utcStr = result.toUtc().toIso8601String();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SelectableText('Campaign scheduled for $utcStr (UTC).'),
            action: SnackBarAction(
              label: 'Copy',
              onPressed: () => Clipboard.setData(ClipboardData(text: utcStr)),
            ),
          ),
        );
      }
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _cancelCampaignSchedule(int id) async {
    try {
      setState(() => loading = true);
      await widget.apiClient
          .cancelCampaignSchedule(token: widget.token, id: id);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                SelectableText('Schedule cancelled. Campaign is draft again.')),
      );
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _deleteCampaign(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete campaign'),
        content: Text('Delete campaign "$name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      setState(() => loading = true);
      await widget.apiClient.deleteCampaign(token: widget.token, id: id);
      await _load();
      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _showErrorSnackBar(e.toString());
    }
  }

  static const List<String> _userRoles = ['admin', 'manager', 'artist'];

  Future<void> _showAddUserDialog() async {
    final emailController = TextEditingController();
    final fullNameController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'manager';
    int? artistId;
    bool isActive = true;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add user'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (dialogError != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              dialogError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(ZalmanimIcons.copy),
                            tooltip: 'Copy error',
                            onPressed: () => Clipboard.setData(
                                ClipboardData(text: dialogError!)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email *'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      decoration:
                          const InputDecoration(labelText: 'Password *'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: _userRoles
                          .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => role = value ?? role),
                    ),
                    if (role == 'artist') ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int?>(
                        initialValue: artistId,
                        decoration: const InputDecoration(
                            labelText: 'Artist (optional)'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('— None —')),
                          ...artists.map((a) {
                            final map = a as Map<String, dynamic>;
                            return DropdownMenuItem<int?>(
                              value: map['id'] as int,
                              child: Text((map['name'] ??
                                      map['email'] ??
                                      '${map['id']}')
                                  .toString()),
                            );
                          }),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => artistId = value),
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: isActive,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      onChanged: (value) =>
                          setDialogState(() => isActive = value ?? true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final email = emailController.text.trim();
                  final password = passwordController.text.trim();
                  if (email.isEmpty) {
                    setDialogState(() => dialogError = 'Email is required.');
                    return;
                  }
                  if (password.isEmpty) {
                    setDialogState(() =>
                        dialogError = 'Password is required for new users.');
                    return;
                  }
                  try {
                    await widget.apiClient.createUser(
                      token: widget.token,
                      body: {
                        'email': email,
                        'full_name': fullNameController.text.trim().isEmpty
                            ? null
                            : fullNameController.text.trim(),
                        'password': password,
                        'role': role,
                        if (artistId != null) 'artist_id': artistId,
                        'is_active': isActive,
                      },
                    );
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop(true);
                  } catch (e) {
                    setDialogState(() => dialogError = e.toString());
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
    emailController.dispose();
    fullNameController.dispose();
    passwordController.dispose();
    if (saved == true) {
      await _loadUsers(withOverlay: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: SelectableText('User created.')),
        );
      }
    }
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final id = user['id'] as int?;
    if (id == null) return;
    final emailController =
        TextEditingController(text: (user['email'] ?? '').toString());
    final fullNameController =
        TextEditingController(text: (user['full_name'] ?? '').toString());
    final passwordController = TextEditingController();
    String role = (user['role'] ?? 'manager').toString();
    if (!_userRoles.contains(role)) role = 'manager';
    int? artistId = user['artist_id'] as int?;
    bool isActive = user['is_active'] as bool? ?? true;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Edit user'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (dialogError != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              dialogError!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(ZalmanimIcons.copy),
                            tooltip: 'Copy error',
                            onPressed: () => Clipboard.setData(
                                ClipboardData(text: dialogError!)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email *'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passwordController,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        hintText: 'Leave blank to keep current',
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: _userRoles
                          .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)))
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => role = value ?? role),
                    ),
                    if (role == 'artist') ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int?>(
                        initialValue: artistId,
                        decoration: const InputDecoration(
                            labelText: 'Artist (optional)'),
                        items: [
                          const DropdownMenuItem<int?>(
                              value: null, child: Text('— None —')),
                          ...artists.map((a) {
                            final map = a as Map<String, dynamic>;
                            return DropdownMenuItem<int?>(
                              value: map['id'] as int,
                              child: Text((map['name'] ??
                                      map['email'] ??
                                      '${map['id']}')
                                  .toString()),
                            );
                          }),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => artistId = value),
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: isActive,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      onChanged: (value) =>
                          setDialogState(() => isActive = value ?? true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final email = emailController.text.trim();
                  if (email.isEmpty) {
                    setDialogState(() => dialogError = 'Email is required.');
                    return;
                  }
                  final body = <String, dynamic>{
                    'email': email,
                    'full_name': fullNameController.text.trim().isEmpty
                        ? null
                        : fullNameController.text.trim(),
                    'role': role,
                    'is_active': isActive,
                  };
                  final pwd = passwordController.text.trim();
                  if (pwd.isNotEmpty) body['password'] = pwd;
                  body['artist_id'] = role == 'artist' ? artistId : null;
                  try {
                    await widget.apiClient
                        .updateUser(token: widget.token, id: id, body: body);
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop(true);
                  } catch (e) {
                    setDialogState(() => dialogError = e.toString());
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    emailController.dispose();
    fullNameController.dispose();
    passwordController.dispose();
    if (saved == true) {
      await _loadUsers(withOverlay: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: SelectableText('User updated.')),
        );
      }
    }
  }

  Future<void> _updateUserActive(
      Map<String, dynamic> user, bool isActive) async {
    final id = user['id'] as int?;
    if (id == null) return;
    try {
      setState(() => loading = true);
      await widget.apiClient.updateUser(
        token: widget.token,
        id: id,
        body: {'is_active': isActive},
      );
      await _loadUsers(withOverlay: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText(
              isActive ? 'User activated.' : 'User deactivated.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _importMailchimpAudienceCsv() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final fileBytes = file.bytes;
    if (fileBytes == null || fileBytes.isEmpty) {
      _showErrorSnackBar('Could not read the CSV file.');
      return;
    }

    if (!mounted) return;

    final listNameController = TextEditingController();
    bool createNewList = _selectedAudienceId == null;
    int? selectedListId = _selectedAudienceId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Import Mailchimp CSV'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'File: ${file.name}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: createNewList,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Create a new mailing list'),
                  subtitle: const Text(
                      'Turn off to import into the currently selected list.'),
                  onChanged: (value) =>
                      setDialogState(() => createNewList = value),
                ),
                if (createNewList) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: listNameController,
                    decoration: const InputDecoration(
                      labelText: 'New list name',
                      hintText: 'Example: Main newsletter',
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: selectedListId,
                    decoration:
                        const InputDecoration(labelText: 'Import into list'),
                    items: audiences.map((audience) {
                      final map = audience as Map<String, dynamic>;
                      return DropdownMenuItem<int>(
                        value: map['id'] as int,
                        child: Text((map['name'] ?? '').toString()),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedListId = value),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Import')),
          ],
        ),
      ),
    );
    final resolvedListName = listNameController.text.trim();
    listNameController.dispose();
    if (confirmed != true) return;
    if (!createNewList && selectedListId == null) {
      _showErrorSnackBar('Select a target mailing list.');
      return;
    }

    try {
      setState(() => loading = true);
      final response = await widget.apiClient.importMailchimpAudienceCsv(
        token: widget.token,
        fileBytes: fileBytes,
        filename: file.name,
        existingListId: createNewList ? null : selectedListId,
        listName: createNewList ? resolvedListName : null,
      );
      await _loadAudiences(reset: true, withOverlay: false);
      final importedListId = response['list_id'] as int?;
      if (importedListId != null) {
        await selectAudience(importedListId);
      }
      if (!mounted) return;
      final message =
          (response['message'] ?? 'Mailchimp CSV imported.').toString();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showCreateAudienceDialog(
      {Map<String, dynamic>? existingAudience}) async {
    final nameController = TextEditingController(
        text: (existingAudience?['name'] ?? '').toString());
    final descriptionController = TextEditingController(
        text: (existingAudience?['description'] ?? '').toString());
    final fromNameController = TextEditingController(
        text: (existingAudience?['from_name'] ?? '').toString());
    final replyToController = TextEditingController(
        text: (existingAudience?['reply_to_email'] ?? '').toString());
    final companyController = TextEditingController(
        text: (existingAudience?['company_name'] ?? '').toString());
    final addressController = TextEditingController(
        text: (existingAudience?['physical_address'] ?? '').toString());
    final languageController = TextEditingController(
        text: (existingAudience?['default_language'] ?? 'en').toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existingAudience == null
            ? 'Create mailing list'
            : 'Edit mailing list'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'List name')),
                const SizedBox(height: 8),
                TextField(
                    controller: descriptionController,
                    decoration:
                        const InputDecoration(labelText: 'Description')),
                const SizedBox(height: 8),
                TextField(
                    controller: fromNameController,
                    decoration: const InputDecoration(labelText: 'From name')),
                const SizedBox(height: 8),
                TextField(
                    controller: replyToController,
                    decoration:
                        const InputDecoration(labelText: 'Reply-to email')),
                const SizedBox(height: 8),
                TextField(
                    controller: companyController,
                    decoration:
                        const InputDecoration(labelText: 'Company name')),
                const SizedBox(height: 8),
                TextField(
                  controller: addressController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Physical mailing address',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: languageController,
                    decoration: const InputDecoration(
                        labelText: 'Default language (en/he)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;
    if (nameController.text.trim().isEmpty) {
      _showErrorSnackBar('List name is required.');
      return;
    }

    final body = <String, dynamic>{
      'name': nameController.text.trim(),
      'description': descriptionController.text.trim(),
      'from_name': fromNameController.text.trim().isEmpty
          ? null
          : fromNameController.text.trim(),
      'reply_to_email': replyToController.text.trim().isEmpty
          ? null
          : replyToController.text.trim(),
      'company_name': companyController.text.trim().isEmpty
          ? null
          : companyController.text.trim(),
      'physical_address': addressController.text.trim().isEmpty
          ? null
          : addressController.text.trim(),
      'default_language': languageController.text.trim().isEmpty
          ? 'en'
          : languageController.text.trim(),
    };

    try {
      setState(() => loading = true);
      if (existingAudience == null) {
        await widget.apiClient.createAudience(token: widget.token, body: body);
      } else {
        await widget.apiClient.updateAudience(
          token: widget.token,
          id: existingAudience['id'] as int,
          body: body,
        );
      }
      await _loadAudiences(reset: true, withOverlay: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(existingAudience == null
                ? 'Mailing list created.'
                : 'Mailing list updated.')),
      );
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _showAudienceSubscriberDialog(
      {Map<String, dynamic>? existingSubscriber}) async {
    final audienceId = _selectedAudienceId;
    if (audienceId == null) {
      _showErrorSnackBar('Select a mailing list first.');
      return;
    }
    final nameController = TextEditingController(
        text: (existingSubscriber?['full_name'] ?? '').toString());
    final emailController = TextEditingController(
        text: (existingSubscriber?['email'] ?? '').toString());
    final consentController = TextEditingController(
        text: (existingSubscriber?['consent_source'] ?? '').toString());
    final notesController = TextEditingController(
        text: (existingSubscriber?['notes'] ?? '').toString());
    String statusValue =
        (existingSubscriber?['status'] ?? 'subscribed').toString();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingSubscriber == null
              ? 'Add subscriber'
              : 'Edit subscriber'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameController,
                      decoration:
                          const InputDecoration(labelText: 'Full name')),
                  const SizedBox(height: 8),
                  TextField(
                      controller: emailController,
                      decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: statusValue,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: const [
                      DropdownMenuItem(
                          value: 'subscribed', child: Text('Subscribed')),
                      DropdownMenuItem(
                          value: 'unsubscribed', child: Text('Unsubscribed')),
                      DropdownMenuItem(
                          value: 'cleaned', child: Text('Cleaned')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() => statusValue = value);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                      controller: consentController,
                      decoration:
                          const InputDecoration(labelText: 'Consent source')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Notes', alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (emailController.text.trim().isEmpty) {
      _showErrorSnackBar('Subscriber email is required.');
      return;
    }

    final body = <String, dynamic>{
      'email': emailController.text.trim(),
      'full_name': nameController.text.trim().isEmpty
          ? null
          : nameController.text.trim(),
      'status': statusValue,
      'consent_source': consentController.text.trim().isEmpty
          ? null
          : consentController.text.trim(),
      'notes': notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
    };

    try {
      setState(() => loading = true);
      if (existingSubscriber == null) {
        await widget.apiClient.createAudienceSubscriber(
          token: widget.token,
          audienceId: audienceId,
          body: body,
        );
      } else {
        await widget.apiClient.updateAudienceSubscriber(
          token: widget.token,
          audienceId: audienceId,
          subscriberId: existingSubscriber['id'] as int,
          body: body,
        );
      }
      await selectAudience(audienceId);
      await _loadAudiences(reset: true, withOverlay: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(existingSubscriber == null
                ? 'Subscriber added.'
                : 'Subscriber updated.')),
      );
    } catch (e) {
      _showErrorSnackBar(e.toString());
    }
  }

  Future<void> _toggleAudienceSubscriberStatus(
      Map<String, dynamic> subscriber) async {
    final audienceId = _selectedAudienceId;
    if (audienceId == null) return;
    final currentStatus = (subscriber['status'] ?? 'subscribed').toString();
    final nextStatus =
        currentStatus == 'unsubscribed' ? 'subscribed' : 'unsubscribed';
    try {
      setState(() => loading = true);
      await widget.apiClient.updateAudienceSubscriber(
        token: widget.token,
        audienceId: audienceId,
        subscriberId: subscriber['id'] as int,
        body: {'status': nextStatus},
      );
      await selectAudience(audienceId);
      await _loadAudiences(reset: true, withOverlay: false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(nextStatus == 'subscribed'
                ? 'Subscriber resubscribed.'
                : 'Subscriber unsubscribed.')),
      );
    } catch (e) {
      _showErrorSnackBar(e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _promoteAudienceSubscriberToArtist(
      Map<String, dynamic> subscriber) async {
    final audienceId = _selectedAudienceId;
    if (audienceId == null) return;
    final subId = subscriber['id'] as int?;
    if (subId == null) return;
    try {
      setState(() => loading = true);
      final artist = await widget.apiClient.promoteAudienceSubscriberToArtist(
        token: widget.token,
        audienceId: audienceId,
        subscriberId: subId,
      );
      await loadArtists();
      if (!mounted) return;
      final name = (artist['name'] ?? artist['email'] ?? 'Artist').toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added to Artists: $name')),
      );
    } catch (e) {
      _setError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: SelectableText(message),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: 'Copy',
          onPressed: () => Clipboard.setData(ClipboardData(text: message)),
        ),
      ),
    );
  }

  Future<void> _load() async {
    await _reloadAllTabs();
  }
}

// --- Artist reminders report dialog (95% width, month selector, mail settings, test email) ---

class _ArtistRemindersDialog extends StatefulWidget {
  const _ArtistRemindersDialog({
    required this.apiClient,
    required this.token,
    required this.dialogWidth,
    required this.onSendEmailToSelected,
    required this.showErrorSnackBar,
  });

  final ApiClient apiClient;
  final String token;
  final double dialogWidth;
  final void Function(List<dynamic> reportList, List<int> selectedIndices)
      onSendEmailToSelected;
  final void Function(String message) showErrorSnackBar;

  @override
  State<_ArtistRemindersDialog> createState() => _ArtistRemindersDialogState();
}

class _ArtistRemindersDialogState extends State<_ArtistRemindersDialog> {
  bool _loading = true;
  String? _error;
  List<dynamic> _reportList = [];
  int _selectedMonths = 6;
  final Set<int> _selectedIndices = {};

  static const List<int> _monthsOptions = [3, 6, 9, 12];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.apiClient
          .fetchArtistsNoTracksHalfYear(widget.token, months: _selectedMonths);
      if (!mounted) return;
      setState(() {
        _reportList = list;
        _loading = false;
        _selectedIndices.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onRegenerate() {
    _loadReport();
  }

  Future<void> _showMailSettings() async {
    final savedSubject = await getArtistReminderEmailSubject();
    final savedBody = await getArtistReminderEmailBody();
    final subjectController =
        TextEditingController(text: savedSubject ?? _defaultReminderSubject);
    final bodyController =
        TextEditingController(text: savedBody ?? _defaultReminderBody);
    if (!mounted) return;
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mail settings - reminder emails'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 680,
            child: _ReminderTemplateEditor(
              subjectController: subjectController,
              bodyController: bodyController,
              previewValues: _sampleReminderTemplateValues,
              helperText:
                  'Default subject and body for artist reminder emails. The body editor supports HTML snippets and dynamic fields from the artist profile.',
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved == true) {
      await setArtistReminderEmailTemplate(
        subject: subjectController.text.trim(),
        body: bodyController.text,
      );
      subjectController.dispose();
      bodyController.dispose();
      if (!mounted) return;
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Mail settings saved.')));
    } else {
      subjectController.dispose();
      bodyController.dispose();
    }
  }

  Future<void> _showSendTestEmail() async {
    final savedSubject = await getArtistReminderEmailSubject();
    final savedBody = await getArtistReminderEmailBody();
    final rendered = _renderReminderEmail(
      subjectTemplate: savedSubject ?? _defaultReminderSubject,
      bodyTemplate: savedBody ?? _defaultReminderBody,
      values: _sampleReminderTemplateValues,
    );
    final toController = TextEditingController();
    if (!mounted) return;
    final toEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send test email'),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: toController,
            decoration: const InputDecoration(
              labelText: 'Send test email to',
              hintText: 'your@email.com',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton.icon(
            icon: const Icon(ZalmanimIcons.send, size: 18),
            label: const Text('Send'),
            onPressed: () {
              final email = toController.text.trim();
              if (email.isEmpty) return;
              Navigator.of(ctx).pop(email);
            },
          ),
        ],
      ),
    );
    toController.dispose();
    if (toEmail == null || toEmail.isEmpty) return;
    try {
      await widget.apiClient.sendEmail(
        token: widget.token,
        toEmail: toEmail,
        subject: rendered.subject,
        bodyText: rendered.bodyText,
        bodyHtml: rendered.bodyHtml,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test email sent to $toEmail.')));
    } catch (e) {
      widget.showErrorSnackBar(e.toString());
    }
  }

  String _reportToCsv() {
    final buffer = StringBuffer();
    buffer.writeln('name,email,artist_brand');
    for (final a in _reportList) {
      final map = a as Map<String, dynamic>;
      final extra = map['extra'] as Map<String, dynamic>? ?? {};
      final name = (map['name'] ?? '').toString().replaceAll('"', '""');
      final email = (map['email'] ?? '').toString().replaceAll('"', '""');
      final brand =
          (extra['artist_brand'] ?? '').toString().replaceAll('"', '""');
      buffer.writeln('"$name","$email","$brand"');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      final err = _error!;
      return AlertDialog(
        title: const Text('Report failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(err, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(ZalmanimIcons.copy),
              label: const Text('Copy error'),
              onPressed: () => Clipboard.setData(ClipboardData(text: err)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Artist reminders'),
      content: SizedBox(
        width: widget.dialogWidth,
        child: _loading
            ? const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Months without release:',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        value: _selectedMonths,
                        items: _monthsOptions
                            .map((m) =>
                                DropdownMenuItem(value: m, child: Text('$m')))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _selectedMonths = v);
                        },
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        icon: const Icon(ZalmanimIcons.refresh, size: 18),
                        label: const Text('Regenerate'),
                        onPressed: _loading ? null : _onRegenerate,
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        icon: const Icon(ZalmanimIcons.settings, size: 18),
                        label: const Text('Mail settings'),
                        onPressed: _showMailSettings,
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(ZalmanimIcons.campaignRequests,
                            size: 18),
                        label: const Text('Send test email'),
                        onPressed: _showSendTestEmail,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_reportList.length} artist(s) with no catalog track release in the last $_selectedMonths months. Select artists to send a personal email.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          for (int i = 0; i < _reportList.length; i++) {
                            _selectedIndices.add(i);
                          }
                        }),
                        child: const Text('Select all'),
                      ),
                      TextButton(
                        onPressed: () =>
                            setState(() => _selectedIndices.clear()),
                        child: const Text('Deselect all'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _reportList.length,
                      itemBuilder: (_, i) {
                        final a = _reportList[i] as Map<String, dynamic>;
                        final extra = a['extra'] as Map<String, dynamic>? ?? {};
                        final name = (extra['artist_brand'] ?? a['name'] ?? '')
                            .toString();
                        final email = (a['email'] ?? '').toString();
                        final lastReminderRaw = a['last_reminder_sent_at'];
                        String? lastReminderStr;
                        if (lastReminderRaw != null) {
                          try {
                            final dt =
                                DateTime.parse(lastReminderRaw.toString());
                            lastReminderStr =
                                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                          } catch (_) {
                            lastReminderStr = lastReminderRaw.toString();
                          }
                        }
                        return CheckboxListTile(
                          value: _selectedIndices.contains(i),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedIndices.add(i);
                            } else {
                              _selectedIndices.remove(i);
                            }
                          }),
                          title:
                              Text(name, style: const TextStyle(fontSize: 13)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SelectableText(email,
                                  style: const TextStyle(fontSize: 12)),
                              if (lastReminderStr != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Last reminder sent: $lastReminderStr',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'No reminder sent yet',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                  ),
                                ),
                            ],
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    icon: const Icon(ZalmanimIcons.copy),
                    label: const Text('Copy as CSV'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _reportToCsv()));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('CSV copied to clipboard.')));
                    },
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close')),
        FilledButton.icon(
          icon: const Icon(ZalmanimIcons.email, size: 18),
          label: Text(_selectedIndices.isEmpty
              ? 'Send email to selected'
              : 'Send email to ${_selectedIndices.length} artist(s)'),
          onPressed: _selectedIndices.isEmpty
              ? null
              : () => widget.onSendEmailToSelected(
                  _reportList, _selectedIndices.toList()..sort()),
        ),
      ],
    );
  }
}

