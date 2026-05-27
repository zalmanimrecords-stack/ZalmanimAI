import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/session_storage.dart';
import '../../core/zalmanim_icons.dart';
import 'artist_reminder_email_template.dart';

/// Sends templated personal emails to artists selected from the reminders report.
Future<void> sendPersonalEmailToReportArtists({
  required BuildContext context,
  required ApiClient apiClient,
  required String token,
  required List<dynamic> reportList,
  required List<int> selectedIndices,
  required void Function(String message) showErrorSnackBar,
}) async {
  final savedSubject = await getArtistReminderEmailSubject();
  final savedBody = await getArtistReminderEmailBody();
  final subjectController =
      TextEditingController(text: savedSubject ?? defaultArtistReminderSubject);
  final bodyController =
      TextEditingController(text: savedBody ?? defaultArtistReminderBody);
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
          child: ArtistReminderTemplateEditor(
            subjectController: subjectController,
            bodyController: bodyController,
            previewValues: sampleArtistReminderTemplateValues,
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
    showErrorSnackBar('Subject is required.');
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
                        child: SelectableText(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.red,
                          ),
                        ),
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
    final values = buildArtistReminderTemplateValues(a);
    final email = (a['email'] ?? '').toString().trim();
    final displayName =
        values['name']?.isNotEmpty == true ? values['name']! : email;
    if (email.isEmpty) {
      failed[displayName] = 'No email';
      refreshProgress?.call();
      continue;
    }
    final rendered = renderArtistReminderEmail(
      subjectTemplate: subjectTemplate,
      bodyTemplate: bodyTemplate,
      values: values,
    );
    final artistId = a['id'] is int ? a['id'] as int : null;
    try {
      await apiClient.sendEmail(
        token: token,
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
      SnackBar(content: Text('Email sent to $total artist(s).')),
    );
  } else {
    showErrorSnackBar(
      'Sent: ${sent.length}, Failed: ${failed.length}. '
      '${failed.entries.map((e) => '${e.key}: ${e.value}').join('; ')}',
    );
  }
}

/// Artist reminders report dialog (month selector, mail settings, bulk send).
class ArtistRemindersDialog extends StatefulWidget {
  const ArtistRemindersDialog({
    super.key,
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
  State<ArtistRemindersDialog> createState() => _ArtistRemindersDialogState();
}

class _ArtistRemindersDialogState extends State<ArtistRemindersDialog> {
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
        TextEditingController(text: savedSubject ?? defaultArtistReminderSubject);
    final bodyController =
        TextEditingController(text: savedBody ?? defaultArtistReminderBody);
    if (!mounted) return;
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mail settings - reminder emails'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 680,
            child: ArtistReminderTemplateEditor(
              subjectController: subjectController,
              bodyController: bodyController,
              previewValues: sampleArtistReminderTemplateValues,
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
    final rendered = renderArtistReminderEmail(
      subjectTemplate: savedSubject ?? defaultArtistReminderSubject,
      bodyTemplate: savedBody ?? defaultArtistReminderBody,
      values: sampleArtistReminderTemplateValues,
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
