import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'session.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

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

  Future<AuthSession> login({required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw Exception('Login failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthSession(token: data['access_token'] as String, role: data['role'] as String);
  }


  Future<String> startGoogleLogin({required String redirectUri}) async {
    final uri = Uri.parse('$baseUrl/auth/google/start').replace(
      queryParameters: {'redirect_uri': redirectUri},
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Google login setup failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['auth_url'] as String;
  }

  Future<String> startGoogleMailConnect({
    required String token,
    required String redirectUri,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/google-mail/start').replace(
      queryParameters: {'redirect_uri': redirectUri},
    );
    final response = await http.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      throw Exception('Google mail connect failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['auth_url'] as String;
  }

  Future<List<dynamic>> fetchArtists(
    String token, {
    bool includeInactive = false,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParameters = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (includeInactive) 'include_inactive': 'true',
    };
    final uri = Uri.parse('$baseUrl/artists').replace(
      queryParameters: queryParameters,
    );
    final response = await http.get(
      uri,
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Artists failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> fetchArtist(String token, int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artists/$id'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
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
      throw Exception('Create artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateArtist({
    required String token,
    required int id,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/artists/$id'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Update artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
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
  Future<Map<String, dynamic>> syncOriginalArtistsFromArtists(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/catalog-tracks/sync-original-artists-from-artists'),
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
  Future<Map<String, dynamic>> createMissingOriginalArtists(String token) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/catalog-tracks/create-missing-original-artists'),
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
      throw Exception('Delete artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
  }

  Future<Map<String, dynamic>> fetchArtistDashboard(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/dashboard'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) throw Exception('Failed to load artist dashboard');
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
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/artist/me/releases/upload'));
    request.headers.addAll(_authHeaders(token));
    request.fields['title'] = title;
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));

    final response = await request.send();
    if (response.statusCode != 200) {
      throw Exception('Upload failed (${response.statusCode})');
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
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    } else {
      throw Exception('Provide either file or fileBytes');
    }

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(body);
      throw Exception('Import failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Extracts user-facing message from API error body (e.g. {"detail": "..."}).
  static String _detailFromErrorBody(String body) {
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

  // Campaigns (unified: social + Mailchimp + WordPress)
  Future<List<dynamic>> fetchCampaigns(
    String token, {
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final queryParameters = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final uri = Uri.parse('$baseUrl/admin/campaigns').replace(
      queryParameters: queryParameters,
    );
    final response = await http.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      throw Exception(
        'Campaigns failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> fetchSystemSettings(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/settings'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Settings failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Send a single email (admin). Used e.g. for personal outreach to artists.
  /// When [artistId] is set and send succeeds, the server logs a reminder_email activity for that artist.
  Future<Map<String, dynamic>> sendEmail({
    required String token,
    required String toEmail,
    required String subject,
    required String bodyText,
    String? bodyHtml,
    int? artistId,
  }) async {
    final body = <String, dynamic>{
      'to_email': toEmail,
      'subject': subject,
      'body_text': bodyText,
    };
    if (bodyHtml != null) body['body_html'] = bodyHtml;
    if (artistId != null) body['artist_id'] = artistId;
    final response = await http.post(
      Uri.parse('$baseUrl/admin/email/send'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 429) {
      final m = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(m?['detail'] ?? 'Rate limit exceeded. Try again later.');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Send email failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Report: artists who have not had any track (catalog release_date) in the last N months.
  Future<List<dynamic>> fetchArtistsNoTracksHalfYear(String token, {int months = 6}) async {
    final uri = Uri.parse('$baseUrl/admin/reports/artists-no-tracks-half-year').replace(
      queryParameters: {'months': '$months'},
    );
    final response = await http.get(
      uri,
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Report failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Fetch activity log for an artist (reminder emails, etc.) for the Logs tab.
  Future<List<dynamic>> fetchArtistActivity(String token, int artistId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/artists/$artistId/activity'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Activity failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Update mail server settings. Returns updated system settings.
  Future<Map<String, dynamic>> updateSystemSettingsMail({
    required String token,
    String? smtpHost,
    int? smtpPort,
    String? smtpFromEmail,
    bool? smtpUseTls,
    bool? smtpUseSsl,
    String? smtpUser,
    String? smtpPassword,
    int? emailsPerHour,
  }) async {
    final body = <String, dynamic>{};
    if (smtpHost != null) body['smtp_host'] = smtpHost;
    if (smtpPort != null) body['smtp_port'] = smtpPort;
    if (smtpFromEmail != null) body['smtp_from_email'] = smtpFromEmail;
    if (smtpUseTls != null) body['smtp_use_tls'] = smtpUseTls;
    if (smtpUseSsl != null) body['smtp_use_ssl'] = smtpUseSsl;
    if (smtpUser != null) body['smtp_user'] = smtpUser;
    if (smtpPassword != null) body['smtp_password'] = smtpPassword;
    if (emailsPerHour != null) body['emails_per_hour'] = emailsPerHour;

    final response = await http.patch(
      Uri.parse('$baseUrl/admin/settings/mail'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update settings failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }


  Future<Map<String, dynamic>> testSystemSettingsMail({
    required String token,
    String? smtpHost,
    int? smtpPort,
    String? smtpFromEmail,
    bool? smtpUseTls,
    bool? smtpUseSsl,
    String? smtpUser,
    String? smtpPassword,
    int? emailsPerHour,
    String? testEmail,
  }) async {
    final body = <String, dynamic>{};
    if (smtpHost != null) body['smtp_host'] = smtpHost;
    if (smtpPort != null) body['smtp_port'] = smtpPort;
    if (smtpFromEmail != null) body['smtp_from_email'] = smtpFromEmail;
    if (smtpUseTls != null) body['smtp_use_tls'] = smtpUseTls;
    if (smtpUseSsl != null) body['smtp_use_ssl'] = smtpUseSsl;
    if (smtpUser != null) body['smtp_user'] = smtpUser;
    if (smtpPassword != null) body['smtp_password'] = smtpPassword;
    if (emailsPerHour != null) body['emails_per_hour'] = emailsPerHour;
    if (testEmail != null && testEmail.isNotEmpty) body['test_email'] = testEmail;

    final response = await http.post(
      Uri.parse('$baseUrl/admin/settings/mail/test'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Mail test failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchCampaign(String token, int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/campaigns/$id'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Campaign failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Upload an image for campaign media. Returns { "url": "..." }.
  Future<Map<String, dynamic>> uploadCampaignMedia({
    required String token,
    required List<int> fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/campaigns/upload-media'),
    );
    request.headers.addAll(_authHeaders(token));
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      fileBytes,
      filename: filename,
    ));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception(
        'Upload failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createCampaign({
    required String token,
    required String name,
    required String title,
    String bodyText = '',
    String? bodyHtml,
    String? mediaUrl,
    int? artistId,
    required List<Map<String, dynamic>> targets,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'title': title,
      'body_text': bodyText,
      'targets': targets,
    };
    if (bodyHtml != null) body['body_html'] = bodyHtml;
    if (mediaUrl != null && mediaUrl.isNotEmpty) body['media_url'] = mediaUrl;
    if (artistId != null) body['artist_id'] = artistId;
    final response = await http.post(
      Uri.parse('$baseUrl/admin/campaigns'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Create campaign failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateCampaign({
    required String token,
    required int id,
    String? name,
    String? title,
    String? bodyText,
    String? bodyHtml,
    String? mediaUrl,
    int? artistId,
    List<Map<String, dynamic>>? targets,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (title != null) body['title'] = title;
    if (bodyText != null) body['body_text'] = bodyText;
    if (bodyHtml != null) body['body_html'] = bodyHtml;
    if (mediaUrl != null) body['media_url'] = mediaUrl;
    if (artistId != null) body['artist_id'] = artistId;
    if (targets != null) body['targets'] = targets;
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/campaigns/$id'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update campaign failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deleteCampaign({required String token, required int id}) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/campaigns/$id'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Delete campaign failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
  }

  Future<Map<String, dynamic>> scheduleCampaign({
    required String token,
    required int id,
    DateTime? scheduledAt,
  }) async {
    final body = <String, dynamic>{};
    if (scheduledAt != null) body['scheduled_at'] = scheduledAt.toUtc().toIso8601String();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/campaigns/$id/schedule'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Schedule campaign failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelCampaignSchedule({required String token, required int id}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/campaigns/$id/cancel'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Cancel schedule failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }


  Future<List<dynamic>> fetchAudiences(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/audiences'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Audiences failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createAudience({
    required String token,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/audiences'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Create audience failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateAudience({
    required String token,
    required int id,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/audiences/$id'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update audience failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> fetchAudienceSubscribers({
    required String token,
    required int audienceId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/audiences/$audienceId/subscribers'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Audience subscribers failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> createAudienceSubscriber({
    required String token,
    required int audienceId,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/audiences/$audienceId/subscribers'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Create subscriber failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateAudienceSubscriber({
    required String token,
    required int audienceId,
    required int subscriberId,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/audiences/$audienceId/subscribers/$subscriberId'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update subscriber failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
  Map<String, String> _authHeaders(String token) {
    return {'Authorization': 'Bearer $token'};
  }
}

