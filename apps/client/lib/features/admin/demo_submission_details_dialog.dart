import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import 'demo_submission_dialogs.dart';
import 'demo_submission_helpers.dart';
import 'demo_submission_widgets.dart';

/// Shows the full demo submission details dialog (info, links, SoundCloud, notes).
Future<void> showDemoSubmissionDetailsDialog({
  required BuildContext context,
  required ApiClient apiClient,
  required String token,
  required Map<String, dynamic> submission,
  required Future<void> Function() onNotesSaved,
  required void Function(Object error) onError,
}) async {
  final id = coerceDemoSubmissionId(submission['id']);
  if (id == null) return;
  final notesController = TextEditingController(
    text: (submission['admin_notes'] ?? '').toString(),
  );
  final linkRows = submission['links'];
  final linkList = linkRows is List<dynamic>
      ? linkRows.map((e) => e.toString()).toList()
      : <String>[];
  final soundCloudUrls = soundCloudUrlsFromDemoSubmission(submission);
  final status = (submission['status'] ?? '').toString();
  final canResendApprovalEmail = status == 'approved';

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final maxH = MediaQuery.sizeOf(ctx).height * 0.88;
      return AlertDialog(
        title: Text('Demo #$id'),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 800, maxHeight: maxH),
          child: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  DemoSubmissionInfoRow(
                      'Artist', (submission['artist_name'] ?? '').toString()),
                  DemoSubmissionInfoRow(
                      'Email', (submission['email'] ?? '').toString()),
                  DemoSubmissionInfoRow('Contact',
                      (submission['contact_name'] ?? '').toString()),
                  DemoSubmissionInfoRow(
                      'Phone', (submission['phone'] ?? '').toString()),
                  DemoSubmissionInfoRow(
                      'Genre', (submission['genre'] ?? '').toString()),
                  DemoSubmissionInfoRow(
                      'City', (submission['city'] ?? '').toString()),
                  DemoSubmissionInfoRow(
                      'Status', (submission['status'] ?? '').toString()),
                  DemoSubmissionInfoRow(
                    'Artist in system',
                    submission['artist_id'] != null
                        ? 'Existing artist (ID: ${submission['artist_id']})'
                        : 'New artist (not in system)',
                  ),
                  DemoSubmissionInfoRow(
                      'Message', (submission['message'] ?? '').toString()),
                  DemoSubmissionInfoRow(
                    'Email consent',
                    submission['consent_to_emails'] == true
                        ? 'Yes${formatDemoSubmissionDate(submission['consent_at']) != null ? ' (${formatDemoSubmissionDate(submission['consent_at'])})' : ''}'
                        : 'No',
                  ),
                  DemoSubmissionInfoRow(
                      'Source', (submission['source'] ?? '').toString()),
                  if ((submission['source_site_url'] ?? '')
                      .toString()
                      .isNotEmpty)
                    DemoSubmissionInfoRow('Source URL',
                        (submission['source_site_url'] ?? '').toString()),
                  if (formatDemoSubmissionDate(submission['created_at']) != null)
                    DemoSubmissionInfoRow(
                      'Submitted at',
                      formatDemoSubmissionDate(submission['created_at'])!,
                    ),
                  if (formatDemoSubmissionDate(submission['updated_at']) != null)
                    DemoSubmissionInfoRow(
                      'Last updated',
                      formatDemoSubmissionDate(submission['updated_at'])!,
                    ),
                  if (formatDemoSubmissionDate(
                          submission['approval_email_sent_at']) !=
                      null)
                    DemoSubmissionInfoRow(
                      'Approval email sent',
                      formatDemoSubmissionDate(
                          submission['approval_email_sent_at'])!,
                    ),
                  if (formatDemoSubmissionDate(
                          submission['rejection_email_sent_at']) !=
                      null)
                    DemoSubmissionInfoRow(
                      'Rejection email sent',
                      formatDemoSubmissionDate(
                          submission['rejection_email_sent_at'])!,
                    ),
                  if (submission['has_demo_file'] == true) ...[
                    const SizedBox(height: 12),
                    const Text('Demo MP3',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DemoSubmissionMp3DownloadButton(
                      demoId: id,
                      apiClient: apiClient,
                      token: token,
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('Links',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...linkList.map(
                    (link) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: SelectableText(link),
                    ),
                  ),
                  if (soundCloudUrls.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text('SoundCloud',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    ...soundCloudUrls.map(
                      (url) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              url,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (kIsWeb)
                              TextButton.icon(
                                onPressed: () async {
                                  final uri = Uri.tryParse(url);
                                  if (uri != null && await canLaunchUrl(uri)) {
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  }
                                },
                                icon: const Icon(Icons.open_in_new, size: 16),
                                label: const Text('Open in browser'),
                              )
                            else
                              DemoSoundCloudEmbed(soundCloudUrl: url),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text('Extra fields',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  SelectableText(demoFieldsJsonPreview(submission)),
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
        ),
        actions: [
          if (canResendApprovalEmail)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop(false);
                await showResendDemoApprovalEmail(
                  context: context,
                  apiClient: apiClient,
                  token: token,
                  submissionId: id,
                  reloadDemos: onNotesSaved,
                  onError: onError,
                );
              },
              child: const Text('Resend approval email'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save notes'),
          ),
        ],
      );
    },
  );
  if (result != true) {
    notesController.dispose();
    return;
  }
  try {
    await apiClient.updateDemoSubmission(
      token: token,
      id: id,
      body: {'admin_notes': notesController.text},
    );
    await onNotesSaved();
  } catch (e) {
    onError(e);
  } finally {
    notesController.dispose();
  }
}
