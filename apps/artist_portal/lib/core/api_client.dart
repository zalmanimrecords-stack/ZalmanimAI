import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'linktree_models.dart';
import 'session.dart';

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  Map<String, String> _authHeaders(String token) {
    return {'Authorization': 'Bearer $token'};
  }

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

  /// Artist portal login (artists table credentials at artists.zalmanim.com).
  /// Uses POST /public/artist-login, not the admin /auth/login.
  Future<AuthSession> login(
      {required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/public/artist-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'password': password}),
    );
    if (response.statusCode != 200) {
      final body = response.body;
      String detail = 'Login failed (${response.statusCode})';
      if (body.isNotEmpty) {
        try {
          final map = jsonDecode(body) as Map<String, dynamic>;
          if (map['detail'] is String) detail = map['detail'] as String;
        } catch (_) {}
        if (detail.length > 200) detail = '${detail.substring(0, 200)}...';
      }
      throw Exception(detail);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthSession(
      token: data['access_token'] as String,
      role: data['role'] as String,
      email: data['email'] as String?,
      fullName: data['full_name'] as String?,
    );
  }

  /// Change current artist's password (current + new).
  Future<void> changePassword(
    String token, {
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/artist/me/password'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'current_password': currentPassword,
        'new_password': newPassword,
      }),
    );
    if (response.statusCode != 200) {
      final body = response.body;
      String detail = 'Change password failed (${response.statusCode})';
      if (body.isNotEmpty) {
        try {
          final map = jsonDecode(body) as Map<String, dynamic>;
          if (map['detail'] is String) detail = map['detail'] as String;
        } catch (_) {}
      }
      throw Exception(detail);
    }
  }

  Future<void> requestPasswordReset({required String email}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );
    if (response.statusCode != 200) {
      throw Exception(
          response.body.isNotEmpty ? response.body : 'Request failed');
    }
  }

  Future<void> resetPassword(
      {required String token, required String newPassword}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'new_password': newPassword}),
    );
    if (response.statusCode != 200) {
      final body = response.body;
      String detail = body;
      try {
        final map = jsonDecode(body) as Map<String, dynamic>;
        if (map['detail'] is String) detail = map['detail'] as String;
      } catch (_) {}
      throw Exception(detail);
    }
  }

  Future<Map<String, dynamic>> fetchArtistDashboard(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/dashboard'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) throw Exception('Failed to load dashboard');
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

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

  Future<Map<String, dynamic>> updateArtistProfile(
    String token, {
    String? name,
    String? notes,
    Map<String, dynamic>? extra,
    List<String>? artistBrands,
    int? profileImageMediaId,
    int? logoMediaId,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (notes != null) body['notes'] = notes;
    if (extra != null) body.addAll(extra);
    if (artistBrands != null) body['artist_brands'] = artistBrands;
    if (profileImageMediaId != null) body['profile_image_media_id'] = profileImageMediaId;
    if (logoMediaId != null) body['logo_media_id'] = logoMediaId;
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

  /// Media list with quota (used_bytes, quota_bytes in MB).
  Future<Map<String, dynamic>> fetchArtistMediaWithQuota(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/media'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Media list failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createCampaignRequest(
    String token, {
    int? releaseId,
    String? message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/artist/me/campaign-requests'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        if (releaseId != null) 'release_id': releaseId,
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      }),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Campaign request failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> fetchCampaignRequests(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/campaign-requests'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Campaign requests failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Send a message to the label (creates a new thread).
  Future<Map<String, dynamic>> sendMessageToLabel(
      String token, String body) async {
    final response = await http.post(
      Uri.parse('$baseUrl/artist/me/inbox'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'body': body.trim()}),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Failed to send message');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// List current artist's inbox threads (messages to the label).
  Future<List<dynamic>> fetchMyInboxThreads(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/inbox'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Inbox failed (${response.statusCode})');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Get one inbox thread with messages.
  Future<Map<String, dynamic>> fetchInboxThread(
      String token, int threadId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/artist/me/inbox/threads/$threadId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Thread not found');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Public linktree data (no auth).
  Future<LinktreeOut> fetchPublicLinktree(int artistId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/public/linktree/$artistId'),
    );
    if (response.statusCode != 200) {
      String detail = response.reasonPhrase ?? 'Unknown error';
      if (response.body.isNotEmpty) {
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['detail'] != null) {
            detail = body['detail'].toString();
          }
        } catch (_) {}
      }
      throw Exception('Linktree failed (${response.statusCode}): $detail');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return LinktreeOut.fromJson(data);
  }

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

  Future<Map<String, dynamic>> submitArtistDemo(
    String token, {
    required String trackName,
    required String musicalStyle,
    String message = '',
    List<int>? fileBytes,
    String filename = 'demo.mp3',
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/artist/me/demos'));
    request.headers.addAll(_authHeaders(token));
    request.fields['track_name'] = trackName;
    request.fields['musical_style'] = musicalStyle;
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

  Future<List<dynamic>> fetchArtistMedia(String token) async {
    final data = await fetchArtistMediaWithQuota(token);
    final items = data['items'];
    return items is List ? items : [];
  }

  Future<Map<String, dynamic>> uploadArtistMedia(
    String token, {
    required List<int> fileBytes,
    required String filename,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/artist/me/media'));
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

  Future<void> deleteArtistMedia(String token, int mediaId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/artist/me/media/$mediaId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception('Delete media failed (${response.statusCode})');
    }
  }

  /// Public: validate pending-release form token and get prefilled names (no auth).
  Future<Map<String, dynamic>> fetchPendingReleaseFormInfo(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/public/pending-release-form').replace(
        queryParameters: {'token': token},
      ),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Invalid or expired link');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadPendingReleaseReferenceImage({
    required String token,
    required List<int> fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/public/pending-release-reference-image'),
    );
    request.fields['token'] = token;
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(body);
      throw Exception(detail.isNotEmpty ? detail : 'Image upload failed');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Public: validate demo confirmation token and get prefilled form data from demo submission (no auth).
  Future<Map<String, dynamic>> fetchDemoConfirmFormInfo(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/public/demo-confirm-form').replace(
        queryParameters: {'token': token},
      ),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Invalid or expired link');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Public: submit confirmed demo details; creates pending release and moves demo to PENDING RELEASE (no auth).
  Future<Map<String, dynamic>> submitDemoConfirm({
    required String token,
    required String artistName,
    required String artistEmail,
    required Map<String, dynamic> artistData,
    required String releaseTitle,
    required Map<String, dynamic> releaseData,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/public/demo-confirm-submit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'artist_name': artistName.trim(),
        'artist_email': artistEmail.trim().toLowerCase(),
        'artist_data': artistData,
        'release_title': releaseTitle.trim(),
        'release_data': releaseData,
      }),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Submission failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Public: submit artist + track details for pending release (no auth).
  Future<Map<String, dynamic>> submitPendingRelease({
    required String token,
    required String artistName,
    required String artistEmail,
    required Map<String, dynamic> artistData,
    required String releaseTitle,
    required Map<String, dynamic> releaseData,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/public/pending-release-submit'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'token': token,
        'artist_name': artistName.trim(),
        'artist_email': artistEmail.trim().toLowerCase(),
        'artist_data': artistData,
        'release_title': releaseTitle.trim(),
        'release_data': releaseData,
      }),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(detail.isNotEmpty ? detail : 'Submission failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitPublicDemo({
    required String artistName,
    required String email,
    required bool consentToEmails,
    String? contactName,
    String? phone,
    String? genre,
    String? city,
    String? message,
    List<String> links = const [],
    Map<String, dynamic> fields = const {},
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/public/demo-submissions'),
      headers: {
        'Content-Type': 'application/json',
        'x-demo-token': AppConfig.demoSubmissionToken,
      },
      body: jsonEncode({
        'artist_name': artistName.trim(),
        'email': email.trim().toLowerCase(),
        'contact_name': contactName?.trim(),
        'phone': phone?.trim(),
        'genre': genre?.trim(),
        'city': city?.trim(),
        'message': message?.trim(),
        'links': links
            .where((item) => item.trim().isNotEmpty)
            .map((item) => item.trim())
            .toList(),
        'fields': fields,
        'consent_to_emails': consentToEmails,
        'source': 'artists_portal_landing',
        'source_site_url': Uri.base.origin,
      }),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Demo submission failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Submit a public demo with optional SoundCloud (or other) link and/or MP3 file.
  /// At least one of [soundCloudOrTrackLink] or [fileBytes] must be provided.
  /// [fileBytes] must be an MP3 file (filename should end in .mp3).
  Future<Map<String, dynamic>> submitPublicDemoWithLinkOrFile({
    required String artistName,
    required String email,
    required bool consentToEmails,
    String? contactName,
    String? phone,
    String? genre,
    String? city,
    String? message,
    String? soundCloudOrTrackLink,
    List<int>? fileBytes,
    String fileFilename = 'demo.mp3',
  }) async {
    final links = <String>[];
    if (soundCloudOrTrackLink != null &&
        soundCloudOrTrackLink.trim().isNotEmpty) {
      links.add(soundCloudOrTrackLink.trim());
    }
    if (links.isEmpty && (fileBytes == null || fileBytes.isEmpty)) {
      throw Exception(
          'Please provide either a SoundCloud track link or an MP3 file.');
    }
    if (fileBytes != null &&
        fileBytes.isNotEmpty &&
        !fileFilename.toLowerCase().endsWith('.mp3')) {
      throw Exception('Only MP3 files are allowed.');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/public/demo-submissions/with-file'),
    );
    request.headers['x-demo-token'] = AppConfig.demoSubmissionToken;
    request.fields['artist_name'] = artistName.trim();
    request.fields['email'] = email.trim().toLowerCase();
    request.fields['consent_to_emails'] = consentToEmails.toString();
    request.fields['contact_name'] = contactName?.trim() ?? '';
    request.fields['phone'] = phone?.trim() ?? '';
    request.fields['genre'] = genre?.trim() ?? '';
    request.fields['city'] = city?.trim() ?? '';
    request.fields['message'] = message?.trim() ?? '';
    request.fields['links_json'] = jsonEncode(links);
    request.fields['source'] = 'artists_portal_landing';
    request.fields['source_site_url'] = Uri.base.origin;

    if (fileBytes != null && fileBytes.isNotEmpty) {
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileFilename,
      ));
    }

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Demo submission failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}
