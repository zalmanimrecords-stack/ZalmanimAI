import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';

/// Reject demo with optional rejection email.
Future<void> showRejectDemoDialog({
  required BuildContext context,
  required ApiClient apiClient,
  required String token,
  required Map<String, dynamic> submission,
  required Future<void> Function() reloadDemos,
  required void Function(Object error) onError,
}) async {
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
            'Hi ${artistName.isEmpty ? 'there' : artistName},\n\nThank you for sending us your music.')
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
                  onChanged: (value) => setStateDialog(() => sendEmail = value),
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
    await apiClient.updateDemoSubmission(
      token: token,
      id: id,
      body: {
        'status': 'rejected',
        'rejection_subject': subjectController.text.trim(),
        'rejection_body': bodyController.text,
        'send_rejection_email': sendEmail,
      },
    );
    await reloadDemos();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sendEmail ? 'Demo rejected and email sent.' : 'Demo rejected.',
        ),
      ),
    );
  } catch (e) {
    onError(e);
  } finally {
    subjectController.dispose();
    bodyController.dispose();
  }
}

/// Approve demo; surfaces [email_warning] when approval succeeded but email did not send.
Future<void> showApproveDemoDialog({
  required BuildContext context,
  required ApiClient apiClient,
  required String token,
  required Map<String, dynamic> submission,
  required Future<void> Function() reloadDemos,
  required void Function(Object error) onError,
}) async {
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
                  onChanged: (value) => setStateDialog(() => sendEmail = value),
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
    final result = await apiClient.approveDemoSubmission(
      token: token,
      id: id,
      approvalSubject: subjectController.text.trim(),
      approvalBody: bodyController.text,
      sendEmail: sendEmail,
    );
    await reloadDemos();
    if (!context.mounted) return;
    final emailWarning = (result['email_warning'] ?? '').toString().trim();
    if (emailWarning.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SelectableText(
            'Demo approved, but the approval email could not be sent: $emailWarning',
          ),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 12),
          action: SnackBarAction(
            label: 'Copy',
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: emailWarning)),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sendEmail
              ? 'Demo approved and email sent.'
              : 'Demo approved.'),
        ),
      );
    }
  } catch (e) {
    onError(e);
  } finally {
    subjectController.dispose();
    bodyController.dispose();
  }
}

/// Resend approval email for an already-approved demo (also used from details dialog).
Future<void> showResendDemoApprovalEmail({
  required BuildContext context,
  required ApiClient apiClient,
  required String token,
  required int submissionId,
  required Future<void> Function() reloadDemos,
  required void Function(Object error) onError,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Resend approval email'),
      content: const Text(
        'Send the approval email again with a fresh demo-confirm link?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Resend'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  try {
    await apiClient.resendDemoApprovalEmail(token: token, id: submissionId);
    await reloadDemos();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Approval email resent.')),
    );
  } catch (e) {
    onError(e);
  }
}
