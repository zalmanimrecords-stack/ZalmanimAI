import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'session.dart';

import 'api_media_url.dart';

part 'api_client_ops.dart';


class ApiClient with ApiClientAuthOps, ApiClientAdminOps {
  ApiClient({required this.baseUrl});

  @override
  final String baseUrl;

  /// Resolves stored media URLs to the configured API origin (see [resolveApiMediaUrl]).
  String resolveMediaUrl(String? url) => resolveApiMediaUrl(baseUrl, url);

  /// Base URL origin for health checks (e.g. http://localhost:8000).
  String get healthUrl => '${Uri.parse(baseUrl).origin}/health';

  /// Returns true if the API server is reachable.
  Future<bool> checkConnection() async {
    try {
      final r = await http.get(Uri.parse(healthUrl)).timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw Exception('timeout'),
          );
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Fetches /health and returns the response body, or null on failure.
  /// Used to display last_git_update (last system update from Git) on the admin dashboard.
  Future<Map<String, dynamic>?> fetchHealth() async {
    try {
      final r = await http.get(Uri.parse(healthUrl)).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw Exception('timeout'),
          );
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<dynamic>> fetchUsers(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Users failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> fetchLoginStats(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/dashboard/login-stats'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Login stats failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Dashboard header counts: artists_count (active), releases_count.
  Future<Map<String, dynamic>> fetchAdminDashboardStats(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/dashboard/stats'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Dashboard stats failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createUser({
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/users'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Create user failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateUser({
    required String token,
    required int id,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/users/$id'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Update user failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> fetchArtists(
    String token, {
    bool includeInactive = false,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParameters = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (includeInactive) 'include_inactive': 'true',
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final uri = Uri.parse('$baseUrl/artists').replace(
      queryParameters: queryParameters,
    );
    final response = await http.get(
      uri,
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Artists failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> fetchArtist(String token, int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artists/$id'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createArtist({
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/artists'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Create artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateArtist({
    required String token,
    required int id,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/artists/$id'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Update artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> fetchArtistReleases(String token, int artistId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artists/$artistId/releases'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Artist releases failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchAdminReleases(
    String token, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/releases').replace(
        queryParameters: {'limit': '$limit', 'offset': '$offset'},
      ),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Releases failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> queueReleaseLinkScan({
    required String token,
    required List<int> releaseIds,
    List<String>? platforms,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/releases/link-scan'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'release_ids': releaseIds,
        if (platforms != null && platforms.isNotEmpty) 'platforms': platforms,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Queue scan failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> fetchReleaseLinkCandidates({
    required String token,
    required int releaseId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/releases/$releaseId/link-candidates'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Release candidates failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> approveReleaseLinkCandidate({
    required String token,
    required int releaseId,
    required int candidateId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/releases/$releaseId/link-candidates/$candidateId/approve'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Approve candidate failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> rejectReleaseLinkCandidate({
    required String token,
    required int releaseId,
    required int candidateId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/releases/$releaseId/link-candidates/$candidateId/reject'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Reject candidate failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateReleaseMinisite({
    required String token,
    required int releaseId,
    String? theme,
    bool? isPublic,
    String? description,
    String? downloadUrl,
    List<String>? galleryUrls,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/releases/$releaseId/minisite'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        if (theme != null) 'theme': theme,
        if (isPublic != null) 'is_public': isPublic,
        if (description != null) 'description': description,
        if (downloadUrl != null) 'download_url': downloadUrl,
        if (galleryUrls != null) 'gallery_urls': galleryUrls,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update minisite failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendReleaseMinisite({
    required String token,
    required int releaseId,
    String? message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/releases/$releaseId/minisite/send'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Send minisite failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Set one or more artists for a release (e.g. when sync did not match).
  Future<Map<String, dynamic>> updateReleaseArtists({
    required String token,
    required int releaseId,
    required List<int> artistIds,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/releases/$releaseId'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'artist_ids': artistIds}),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update release artists failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> syncReleasesFromCatalog(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/releases/sync-from-catalog'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Sync failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Sync catalog Original Artists to artist Brand: for each catalog release matched to an artist,
  /// set catalog_tracks.original_artists to that artist's brand (artist_brand or name).
  Future<Map<String, dynamic>> syncOriginalArtistsFromArtists(
      String token) async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl/admin/catalog-tracks/sync-original-artists-from-artists'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Sync failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Create artist records for catalog Original Artists that have no matching Brand.
  Future<Map<String, dynamic>> createMissingOriginalArtists(
      String token) async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl/admin/catalog-tracks/create-missing-original-artists'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Create missing artists failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Merge source artists into target: add their brands to target and deactivate sources.
  Future<Map<String, dynamic>> mergeArtists({
    required String token,
    required int targetArtistId,
    required List<int> sourceArtistIds,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/artists/merge'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'target_artist_id': targetArtistId,
        'source_artist_ids': sourceArtistIds,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Merge failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteArtist({required String token, required int id}) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/artists/$id'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
          'Delete artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
  }

  /// Set artist's portal password (artists table). Artist can then log in at artists.zalmanim.com.
  Future<void> setArtistPassword({
    required String token,
    required int artistId,
    required String password,
  }) async {
    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters');
    }
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/artists/$artistId/set-password'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Set password failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}');
    }
  }

  /// Sending the invite can take 20â€“30s (server sends email). Use a long timeout to avoid "Failed to fetch".
  static const Duration _portalInviteTimeout = Duration(seconds: 90);

  /// Returns true if the server can send email (SMTP or Gmail configured). Use before inviting artists.
  Future<bool> isEmailConfigured(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/email/rate-limit'),
        headers: _authHeaders(token),
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      return data?['configured'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchEmailRecipientHistory({
    required String token,
    required String email,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/email/history').replace(
        queryParameters: {'email': email},
      ),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Email history failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendArtistPortalInvite({
    required String token,
    required int artistId,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/admin/artists/$artistId/send-portal-invite'),
          headers: _authHeaders(token),
        )
        .timeout(_portalInviteTimeout);
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Send portal invite failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> sendGrooverInvite({
    required String token,
    required String email,
    String? artistName,
    String? fullName,
    String? notes,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/admin/artists/send-groover-invite'),
          headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            if (artistName != null) 'artist_name': artistName,
            if (fullName != null) 'full_name': fullName,
            if (notes != null) 'notes': notes,
          }),
        )
        .timeout(_portalInviteTimeout);
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Send Groover invite failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Send email inviting artist to update their portal page and see their releases.
  Future<Map<String, dynamic>> sendArtistUpdateProfileInvite({
    required String token,
    required int artistId,
  }) async {
    final response = await http
        .post(
          Uri.parse(
              '$baseUrl/admin/artists/$artistId/send-update-profile-invite'),
          headers: _authHeaders(token),
        )
        .timeout(_portalInviteTimeout);
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Send update profile invite failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> fetchCampaignRequests({
    required String token,
    String? statusFilter,
  }) async {
    final queryParams = <String, String>{};
    if (statusFilter != null && statusFilter.isNotEmpty) {
      queryParams['status_filter'] = statusFilter;
    }
    final uri = queryParams.isEmpty
        ? Uri.parse('$baseUrl/admin/campaign-requests')
        : Uri.parse('$baseUrl/admin/campaign-requests')
            .replace(queryParameters: queryParams);
    final response = await http.get(
      uri,
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Campaign requests failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateCampaignRequest({
    required String token,
    required int requestId,
    String? status,
    String? adminNotes,
  }) async {
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (adminNotes != null) body['admin_notes'] = adminNotes;
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/campaign-requests/$requestId'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Update campaign request failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// List pending-for-release items (tracks with full details submitted, waiting for treatment).
  Future<List<dynamic>> fetchPendingReleases({
    required String token,
    String? statusFilter,
    int limit = 100,
    int offset = 0,
  }) async {
    final queryParams = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };
    if (statusFilter != null && statusFilter.isNotEmpty) {
      queryParams['status_filter'] = statusFilter;
    }
    final uri = Uri.parse('$baseUrl/admin/pending-releases')
        .replace(queryParameters: queryParams);
    final response = await http.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Pending releases failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<List<dynamic>> fetchInboxThreads({
    required String token,
    int? artistId,
  }) async {
    final queryParams = <String, String>{};
    if (artistId != null) queryParams['artist_id'] = artistId.toString();
    final uri = Uri.parse('$baseUrl/admin/inbox')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
    final response = await http.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception('Inbox failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> fetchInboxThread({
    required String token,
    required int threadId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/inbox/threads/$threadId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Thread not found');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> replyToInboxThread({
    required String token,
    required int threadId,
    required String body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/inbox/threads/$threadId/reply'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'body': body.trim()}),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Reply failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteInboxThread({
    required String token,
    required int threadId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/inbox/threads/$threadId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Delete failed');
    }
  }

  Future<Map<String, dynamic>> fetchArtistDashboard(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/dashboard'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load artist dashboard');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Upload a release. Uses [fileBytes] + [filename] so it works on web
  /// (where file path is unavailable per file_picker FAQ).
  Future<void> uploadRelease({
    required String token,
    required String title,
    required List<int> fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
        'POST', Uri.parse('$baseUrl/artist/me/releases/upload'));
    request.headers.addAll(_authHeaders(token));
    request.fields['title'] = title;
    request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: filename));

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode})');
    }
  }

  /// Get current artist profile (artist role only).
  Future<Map<String, dynamic>> fetchArtistProfile(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Profile failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Update current artist profile (name, notes, extra fields).
  Future<Map<String, dynamic>> updateArtistProfile(
    String token, {
    String? name,
    String? notes,
    Map<String, dynamic>? extra,
    List<String>? artistBrands,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (notes != null) body['notes'] = notes;
    if (extra != null) body.addAll(extra);
    if (artistBrands != null) body['artist_brands'] = artistBrands;
    final response = await http.patch(
      Uri.parse('$baseUrl/artist/me'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Update profile failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// List demo submissions for the current artist.
  Future<List<dynamic>> fetchArtistDemos(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/demos'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Demos failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Submit a demo (message + optional file).
  Future<Map<String, dynamic>> submitArtistDemo(
    String token, {
    String message = '',
    List<int>? fileBytes,
    String filename = 'demo.mp3',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/artist/me/demos'),
    );
    request.headers.addAll(_authHeaders(token));
    request.fields['message'] = message;
    if (fileBytes != null && fileBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
      );
    }
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(body);
      throw Exception('Submit demo failed (${response.statusCode}): $detail');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// List current artist's media folder.
  Future<List<dynamic>> fetchArtistMedia(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/media'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Media list failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Upload a file to the artist's media folder.
  Future<Map<String, dynamic>> uploadArtistMedia(
    String token, {
    required List<int> fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/artist/me/media'),
    );
    request.headers.addAll(_authHeaders(token));
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(body);
      throw Exception('Upload media failed (${response.statusCode}): $detail');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Download a file from the artist's media folder. Returns response bytes.
  Future<List<int>> downloadArtistMedia(String token, int mediaId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/media/$mediaId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Download failed (${response.statusCode})');
    }
    return response.bodyBytes;
  }

  /// Delete a file from the artist's media folder.
  Future<void> deleteArtistMedia(String token, int mediaId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/artist/me/media/$mediaId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Delete media failed (${response.statusCode})');
    }
  }

  Future<List<dynamic>> fetchCatalogTracks(
    String token, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/catalog-tracks').replace(
        queryParameters: {'limit': '$limit', 'offset': '$offset'},
      ),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Catalog tracks failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> importCatalogCsv({
    required String token,
    File? file,
    List<int>? fileBytes,
    String filename = 'import.csv',
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/catalog-tracks/import'),
    );
    request.headers.addAll(_authHeaders(token));
    if (file != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
    } else if (fileBytes != null) {
      request.files.add(
          http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    } else {
      throw Exception('Provide either file or fileBytes');
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(body);
      throw Exception(
          'Import failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

}

Map<String, String> _authHeaders(String token) => {'Authorization': 'Bearer $token'};

String _detailFromErrorBody(String body) {
  if (body.isEmpty) return '';
  try {
    final map = jsonDecode(body) as Map<String, dynamic>;
    final d = map['detail'];
    if (d is String) return d;
    return body;
  } catch (_) {
    return body;
  }
}

