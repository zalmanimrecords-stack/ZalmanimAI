part of 'api_client.dart';

mixin ApiClientAuthOps {
  String get baseUrl;
  Future<AuthSession> login(
      {required String email, required String password}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode != 200) {
      throw Exception('Login failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthSession(
      token: data['access_token'] as String,
      role: data['role'] as String,
      email: data['email'] as String?,
      fullName: data['full_name'] as String?,
    );
  }

  Future<String> startSocialLogin({
    required String provider,
    required String redirectUri,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/$provider/start').replace(
      queryParameters: {'redirect_uri': redirectUri},
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception(
          '$provider login setup failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['auth_url'] as String;
  }

  Future<String> startGoogleLogin({required String redirectUri}) {
    return startSocialLogin(provider: 'google', redirectUri: redirectUri);
  }

  Future<String> startFacebookLogin({required String redirectUri}) {
    return startSocialLogin(provider: 'facebook', redirectUri: redirectUri);
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

  Future<String> startGoogleMailConnect({
    required String token,
    required String redirectUri,
  }) async {
    final uri = Uri.parse('$baseUrl/admin/google-mail/start').replace(
      queryParameters: {'redirect_uri': redirectUri},
    );
    final response = await http.get(uri, headers: _authHeaders(token));
    if (response.statusCode != 200) {
      throw Exception(
          'Google mail connect failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['auth_url'] as String;
  }
}

mixin ApiClientAdminOps {
  String get baseUrl;
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

  Future<List<dynamic>> fetchDemoSubmissions(
    String token, {
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    final queryParameters = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final response = await http.get(
      Uri.parse('$baseUrl/admin/demo-submissions').replace(
        queryParameters: queryParameters,
      ),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Demo submissions failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateDemoSubmission({
    required String token,
    required int id,
    required Map<String, dynamic> body,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/demo-submissions/$id'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Update demo failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> approveDemoSubmission({
    required String token,
    required int id,
    required String approvalSubject,
    required String approvalBody,
    bool createArtist = true,
    bool sendEmail = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/demo-submissions/$id/approve'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'approval_subject': approvalSubject,
        'approval_body': approvalBody,
        'create_artist': createArtist,
        'send_email': sendEmail,
      }),
    );
    if (response.statusCode == 429) {
      final m = jsonDecode(response.body) as Map<String, dynamic>?;
      throw Exception(m?['detail'] ?? 'Rate limit exceeded. Try again later.');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Approve demo failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Delete a demo submission. Requires admin. Throws on failure.
  Future<void> deleteDemoSubmission(
      {required String token, required int id}) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/demo-submissions/$id'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 204) {
      throw Exception(
        'Delete demo failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
  }

  /// URL for streaming/downloading the demo MP3 file (admin). Use with Authorization header.
  String demoSubmissionDownloadUrl(int id) =>
      '$baseUrl/admin/demo-submissions/$id/download';

  /// Download demo MP3 file as bytes (admin). Use for "Download MP3" link.
  Future<List<int>> downloadDemoSubmissionFile(
      {required String token, required int id}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/demo-submissions/$id/download'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Download failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return response.bodyBytes;
  }

  /// Fetches binary content from an absolute URL (e.g. resolved public media URL).
  /// Used for "Download" on pending-release images and similar assets.
  Future<List<int>> fetchUrlBytes(String absoluteUrl) async {
    final response = await http.get(Uri.parse(absoluteUrl));
    if (response.statusCode != 200) {
      throw Exception(
        'Download failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return response.bodyBytes;
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
  Future<List<dynamic>> fetchArtistsNoTracksHalfYear(String token,
      {int months = 6}) async {
    final uri =
        Uri.parse('$baseUrl/admin/reports/artists-no-tracks-half-year').replace(
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

  Future<Map<String, dynamic>> sendPendingReleaseReminder({
    required String token,
    required int pendingReleaseId,
  }) async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl/admin/pending-releases/$pendingReleaseId/send-reminder'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception('Send reminder failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchPendingReleaseDetail({
    required String token,
    required int pendingReleaseId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/pending-releases/$pendingReleaseId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Fetch pending release failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> addPendingReleaseComment({
    required String token,
    required int pendingReleaseId,
    required String body,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/pending-releases/$pendingReleaseId/comments'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'body': body}),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Add pending release comment failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> uploadPendingReleaseImage({
    required String token,
    required int pendingReleaseId,
    required List<int> fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/pending-releases/$pendingReleaseId/images'),
    );
    request.headers.addAll(_authHeaders(token));
    request.files.add(
      http.MultipartFile.fromBytes('file', fileBytes, filename: filename),
    );
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(body);
      throw Exception(
          'Upload pending release image failed (${response.statusCode}): $detail');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> deletePendingReleaseImageOption({
    required String token,
    required int pendingReleaseId,
    required String imageId,
  }) async {
    final encoded = Uri.encodeComponent(imageId);
    final response = await http.delete(
      Uri.parse(
          '$baseUrl/admin/pending-releases/$pendingReleaseId/images/$encoded'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Delete pending release image failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Removes a server-stored image by public URL (label option or cover reference file).
  Future<Map<String, dynamic>> removePendingReleaseStoredImage({
    required String token,
    required int pendingReleaseId,
    required String imageUrl,
  }) async {
    final response = await http.post(
      Uri.parse(
          '$baseUrl/admin/pending-releases/$pendingReleaseId/remove-stored-image'),
      headers: {..._authHeaders(token), 'Content-Type': 'application/json'},
      body: jsonEncode({'url': imageUrl}),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Remove image failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> normalizePendingReleaseImageToJpg3000({
    required String token,
    required int pendingReleaseId,
    required String imageId,
  }) async {
    final encoded = Uri.encodeComponent(imageId);
    final response = await http.post(
      Uri.parse(
          '$baseUrl/admin/pending-releases/$pendingReleaseId/images/$encoded/normalize-jpg'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Normalize image failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> archivePendingRelease({
    required String token,
    required int pendingReleaseId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/pending-releases/$pendingReleaseId/archive'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Archive pending release failed (${response.statusCode}): $detail');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> deletePendingRelease({
    required String token,
    required int pendingReleaseId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/pending-releases/$pendingReleaseId'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
          'Delete pending release failed (${response.statusCode}): $detail');
    }
  }

  /// Report: artists who have already signed in to the artist portal.
  Future<List<dynamic>> fetchArtistsSignedIn(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/reports/artists-signed-in'),
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

  /// Fetch system and mail logs for Settings > Logs. [limit] default 200, max 500.
  Future<List<dynamic>> fetchSystemLogs(String token, {int limit = 200}) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/logs')
          .replace(queryParameters: {'limit': limit.toString()}),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Logs failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// List database table names for Settings > DB.
  Future<List<dynamic>> fetchDbTables(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/db/tables'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'DB tables failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  /// Fetch rows from a table. [limit] 1–500, default 100. [offset] for pagination.
  Future<Map<String, dynamic>> fetchDbTableContent(
    String token,
    String tableName, {
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/db/tables/$tableName').replace(
        queryParameters: {
          'limit': limit.toString(),
          'offset': offset.toString()
        },
      ),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'DB table failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Update mail server settings and email templates. Returns updated system settings.
  Future<Map<String, dynamic>> updateSystemSettingsMail({
    required String token,
    String? smtpHost,
    int? smtpPort,
    String? smtpFromEmail,
    bool? smtpUseTls,
    bool? smtpUseSsl,
    String? smtpUser,
    String? smtpPassword,
    String? smtpBackupHost,
    int? smtpBackupPort,
    String? smtpBackupFromEmail,
    bool? smtpBackupUseTls,
    bool? smtpBackupUseSsl,
    String? smtpBackupUser,
    String? smtpBackupPassword,
    int? emailsPerHour,
    String? emailFooter,
    String? demoRejectionSubject,
    String? demoRejectionBody,
    String? demoApprovalSubject,
    String? demoApprovalBody,
    String? demoReceiptSubject,
    String? demoReceiptBody,
    String? portalInviteSubject,
    String? portalInviteBody,
    String? grooverInviteSubject,
    String? grooverInviteBody,
    String? updateProfileInviteSubject,
    String? updateProfileInviteBody,
    String? passwordResetSubject,
    String? passwordResetBody,
  }) async {
    final body = <String, dynamic>{};
    if (smtpHost != null) body['smtp_host'] = smtpHost;
    if (smtpPort != null) body['smtp_port'] = smtpPort;
    if (smtpFromEmail != null) body['smtp_from_email'] = smtpFromEmail;
    if (smtpUseTls != null) body['smtp_use_tls'] = smtpUseTls;
    if (smtpUseSsl != null) body['smtp_use_ssl'] = smtpUseSsl;
    if (smtpUser != null) body['smtp_user'] = smtpUser;
    if (smtpPassword != null) body['smtp_password'] = smtpPassword;
    if (smtpBackupHost != null) body['smtp_backup_host'] = smtpBackupHost;
    if (smtpBackupPort != null) body['smtp_backup_port'] = smtpBackupPort;
    if (smtpBackupFromEmail != null) {
      body['smtp_backup_from_email'] = smtpBackupFromEmail;
    }
    if (smtpBackupUseTls != null) body['smtp_backup_use_tls'] = smtpBackupUseTls;
    if (smtpBackupUseSsl != null) body['smtp_backup_use_ssl'] = smtpBackupUseSsl;
    if (smtpBackupUser != null) body['smtp_backup_user'] = smtpBackupUser;
    if (smtpBackupPassword != null) {
      body['smtp_backup_password'] = smtpBackupPassword;
    }
    if (emailsPerHour != null) body['emails_per_hour'] = emailsPerHour;
    if (emailFooter != null) body['email_footer'] = emailFooter;
    if (demoRejectionSubject != null) {
      body['demo_rejection_subject'] = demoRejectionSubject;
    }
    if (demoRejectionBody != null) {
      body['demo_rejection_body'] = demoRejectionBody;
    }
    if (demoApprovalSubject != null) {
      body['demo_approval_subject'] = demoApprovalSubject;
    }
    if (demoApprovalBody != null) {
      body['demo_approval_body'] = demoApprovalBody;
    }
    if (demoReceiptSubject != null) {
      body['demo_receipt_subject'] = demoReceiptSubject;
    }
    if (demoReceiptBody != null) {
      body['demo_receipt_body'] = demoReceiptBody;
    }
    if (portalInviteSubject != null) {
      body['portal_invite_subject'] = portalInviteSubject;
    }
    if (portalInviteBody != null) {
      body['portal_invite_body'] = portalInviteBody;
    }
    if (grooverInviteSubject != null) {
      body['groover_invite_subject'] = grooverInviteSubject;
    }
    if (grooverInviteBody != null) {
      body['groover_invite_body'] = grooverInviteBody;
    }
    if (updateProfileInviteSubject != null) {
      body['update_profile_invite_subject'] = updateProfileInviteSubject;
    }
    if (updateProfileInviteBody != null) {
      body['update_profile_invite_body'] = updateProfileInviteBody;
    }
    if (passwordResetSubject != null) {
      body['password_reset_subject'] = passwordResetSubject;
    }
    if (passwordResetBody != null) {
      body['password_reset_body'] = passwordResetBody;
    }

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

  /// Send portal access email to all active artists that have an email. Returns sent count, failed count, and errors.
  Future<Map<String, dynamic>> sendArtistPortalInviteToAll(
      {required String token}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/admin/artists/send-portal-invite-all'),
          headers: _authHeaders(token),
        )
        .timeout(ApiClient._portalInviteTimeout * 10);
    if (response.statusCode != 200) {
      final detail = _detailFromErrorBody(response.body);
      throw Exception(
        'Send portal invite to all failed (${response.statusCode}): ${detail.isNotEmpty ? detail : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> testSystemSettingsMail({
    required String token,
    String smtpTestTarget = 'primary',
    String? smtpHost,
    int? smtpPort,
    String? smtpFromEmail,
    bool? smtpUseTls,
    bool? smtpUseSsl,
    String? smtpUser,
    String? smtpPassword,
    String? smtpBackupHost,
    int? smtpBackupPort,
    String? smtpBackupFromEmail,
    bool? smtpBackupUseTls,
    bool? smtpBackupUseSsl,
    String? smtpBackupUser,
    String? smtpBackupPassword,
    int? emailsPerHour,
    String? testEmail,
  }) async {
    final body = <String, dynamic>{'smtp_test_target': smtpTestTarget};
    if (smtpHost != null) body['smtp_host'] = smtpHost;
    if (smtpPort != null) body['smtp_port'] = smtpPort;
    if (smtpFromEmail != null) body['smtp_from_email'] = smtpFromEmail;
    if (smtpUseTls != null) body['smtp_use_tls'] = smtpUseTls;
    if (smtpUseSsl != null) body['smtp_use_ssl'] = smtpUseSsl;
    if (smtpUser != null) body['smtp_user'] = smtpUser;
    if (smtpPassword != null) body['smtp_password'] = smtpPassword;
    if (smtpBackupHost != null) body['smtp_backup_host'] = smtpBackupHost;
    if (smtpBackupPort != null) body['smtp_backup_port'] = smtpBackupPort;
    if (smtpBackupFromEmail != null) {
      body['smtp_backup_from_email'] = smtpBackupFromEmail;
    }
    if (smtpBackupUseTls != null) body['smtp_backup_use_tls'] = smtpBackupUseTls;
    if (smtpBackupUseSsl != null) body['smtp_backup_use_ssl'] = smtpBackupUseSsl;
    if (smtpBackupUser != null) body['smtp_backup_user'] = smtpBackupUser;
    if (smtpBackupPassword != null) {
      body['smtp_backup_password'] = smtpBackupPassword;
    }
    if (emailsPerHour != null) body['emails_per_hour'] = emailsPerHour;
    if (testEmail != null && testEmail.isNotEmpty) {
      body['test_email'] = testEmail;
    }

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
    if (scheduledAt != null) {
      body['scheduled_at'] = scheduledAt.toUtc().toIso8601String();
    }
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

  Future<Map<String, dynamic>> cancelCampaignSchedule(
      {required String token, required int id}) async {
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
      Uri.parse(
          '$baseUrl/admin/audiences/$audienceId/subscribers/$subscriberId'),
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

  /// Creates an [Artist] from this mailing subscriber or returns the existing one by email.
  Future<Map<String, dynamic>> promoteAudienceSubscriberToArtist({
    required String token,
    required int audienceId,
    required int subscriberId,
  }) async {
    final response = await http.post(
      Uri.parse(
        '$baseUrl/admin/audiences/$audienceId/subscribers/$subscriberId/promote-to-artist',
      ),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Promote subscriber to artist failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> importMailchimpAudienceCsv({
    required String token,
    required List<int> fileBytes,
    required String filename,
    int? existingListId,
    String? listName,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/audiences/import/mailchimp'),
    );
    request.headers.addAll(_authHeaders(token));
    if (existingListId != null) {
      request.fields['existing_list_id'] = '$existingListId';
    }
    if (listName != null && listName.isNotEmpty) {
      request.fields['list_name'] = listName;
    }
    request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw Exception(
        'Mailchimp import failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Download full DB backup as JSON. Returns (bytes, suggested filename).
  Future<({List<int> bytes, String filename})> downloadBackup(
      String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/backup'),
      headers: _authHeaders(token),
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Backup failed (${response.statusCode}): ${response.body.isNotEmpty ? response.body : response.reasonPhrase}',
      );
    }
    String filename = 'labelops-backup.json';
    final disposition = response.headers['content-disposition'];
    if (disposition != null) {
      const prefix = 'filename="';
      final i = disposition.indexOf(prefix);
      if (i != -1) {
        final end = disposition.indexOf('"', i + prefix.length);
        if (end != -1) {
          filename = disposition.substring(i + prefix.length, end);
        }
      }
    }
    return (bytes: response.bodyBytes, filename: filename);
  }

  /// Restore DB from a backup JSON file (replaces all data).
  Future<Map<String, dynamic>> restoreBackup({
    required String token,
    required List<int> fileBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/admin/restore'),
    );
    request.headers.addAll(_authHeaders(token));
    request.files.add(
        http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      final body = response.body;
      throw Exception(
        'Restore failed (${response.statusCode}): ${body.isNotEmpty ? body : response.reasonPhrase}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}








