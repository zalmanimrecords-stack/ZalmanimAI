import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

class _EmailTemplateConfig {
  const _EmailTemplateConfig({
    required this.id,
    required this.title,
    required this.description,
    required this.subjectKey,
    required this.bodyKey,
    required this.subjectHint,
    required this.bodyHint,
    required this.previewValues,
  });

  final String id;
  final String title;
  final String description;
  final String subjectKey;
  final String bodyKey;
  final String subjectHint;
  final String bodyHint;
  final Map<String, String> previewValues;
}

const List<_EmailTemplateConfig> _templateConfigs = [
  _EmailTemplateConfig(
    id: 'demo_receipt',
    title: 'Demo receipt',
    description:
        'Sent automatically when a public demo is submitted. Placeholders: {recipient_name}, {artist_name}, {contact_name}, {email}, {phone}, {genre}, {city}, {links}, {message}, {source}, {submission_summary}.',
    subjectKey: 'demo_receipt_subject',
    bodyKey: 'demo_receipt_body',
    subjectHint: 'Demo received from {artist_name}',
    bodyHint: 'Hi {recipient_name},\n\nWe received your demo...',
    previewValues: {
      'recipient_name': 'Maya Cohen',
      'artist_name': 'Maya Waves',
      'contact_name': 'Maya Cohen',
      'email': 'maya@example.com',
      'phone': '+972-50-555-5555',
      'genre': 'Progressive House',
      'city': 'Tel Aviv',
      'links': 'https://soundcloud.com/maya-waves/demo',
      'message': 'Hope this fits the label direction.',
      'source': 'artist portal',
      'submission_summary':
          '- Artist name: Maya Waves\n- Contact name: Maya Cohen\n- Email: maya@example.com\n- Genre: Progressive House\n- City: Tel Aviv',
    },
  ),
  _EmailTemplateConfig(
    id: 'demo_rejection',
    title: 'Demo rejection',
    description:
        'Sent when a demo submission is rejected. Placeholders: {artist_name}, {artist_portal_url}, {zalmanim_website}.',
    subjectKey: 'demo_rejection_subject',
    bodyKey: 'demo_rejection_body',
    subjectHint: 'Thank you for your demo submission, {artist_name}',
    bodyHint: 'Hi {artist_name},\n\nThank you for sending us your music...',
    previewValues: {
      'artist_name': 'Maya Waves',
      'artist_portal_url': 'https://artists.zalmanim.com',
      'zalmanim_website': 'https://zalmanim.com',
    },
  ),
  _EmailTemplateConfig(
    id: 'demo_approval',
    title: 'Demo approval',
    description:
        'Default email used when approving a demo. Placeholder: {artist_name}.',
    subjectKey: 'demo_approval_subject',
    bodyKey: 'demo_approval_body',
    subjectHint: 'Your demo was approved, {artist_name}',
    bodyHint: 'Hi {artist_name},\n\nThanks for sending your demo...',
    previewValues: {
      'artist_name': 'Maya Waves',
    },
  ),
  _EmailTemplateConfig(
    id: 'portal_invite',
    title: 'Portal invite',
    description:
        'Sent when creating artist portal access. Placeholders: {display_name}, {portal_url}, {username}, {temporary_password}.',
    subjectKey: 'portal_invite_subject',
    bodyKey: 'portal_invite_body',
    subjectHint: 'Your Zalmanim Artists Portal access',
    bodyHint:
        'Hi {display_name},\n\nYour access to the Zalmanim Artists Portal is ready...',
    previewValues: {
      'display_name': 'Maya Cohen',
      'portal_url': 'https://artists.zalmanim.com',
      'username': 'maya@example.com',
      'temporary_password': 'TmpPass123!',
    },
  ),
  _EmailTemplateConfig(
    id: 'groover_invite',
    title: 'Groover invite',
    description:
        'Sent after a contact from Groover. Placeholders: {display_name}, {registration_url}, {portal_url}.',
    subjectKey: 'groover_invite_subject',
    bodyKey: 'groover_invite_body',
    subjectHint: 'Thanks for reaching out on Groover',
    bodyHint:
        'Hi {display_name},\n\nThanks for reaching out on Groover...\n\nPlease complete your registration here:\n{registration_url}',
    previewValues: {
      'display_name': 'Maya Cohen',
      'registration_url':
          'https://artists.zalmanim.com/#/artist-registration?token=abc123',
      'portal_url': 'https://artists.zalmanim.com',
    },
  ),
  _EmailTemplateConfig(
    id: 'update_profile_invite',
    title: 'Update profile invite',
    description:
        'Sent when asking an artist to update their page and review releases. Placeholders: {display_name}, {portal_url}, {username}, {temporary_password}, {password_line}.',
    subjectKey: 'update_profile_invite_subject',
    bodyKey: 'update_profile_invite_body',
    subjectHint: 'Update your artist page and see your releases',
    bodyHint:
        'Hi {display_name},\n\nWe\'d love you to update your artist page...\n\n{password_line}',
    previewValues: {
      'display_name': 'Maya Cohen',
      'portal_url': 'https://artists.zalmanim.com',
      'username': 'maya@example.com',
      'temporary_password': 'TmpPass123!',
      'password_line': 'Temporary password: TmpPass123!',
    },
  ),
  _EmailTemplateConfig(
    id: 'password_reset',
    title: 'Password reset',
    description:
        'Sent when an admin, manager, or artist requests a password reset. Placeholders: {reset_link}, {expiry_minutes}.',
    subjectKey: 'password_reset_subject',
    bodyKey: 'password_reset_body',
    subjectHint: 'Password reset',
    bodyHint:
        'Use this link to reset your password (valid for {expiry_minutes} minutes):\n\n{reset_link}',
    previewValues: {
      'reset_link': 'https://lm.zalmanim.com?reset_token=abc123',
      'expiry_minutes': '60',
    },
  ),
];

class EmailTemplatesTab extends StatefulWidget {
  const EmailTemplatesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<EmailTemplatesTab> createState() => _EmailTemplatesTabState();
}

class _EmailTemplatesTabState extends State<EmailTemplatesTab> {
  bool _loading = true;
  String? _error;
  final _emailFooterController = TextEditingController();
  bool _savingFooter = false;
  String? _footerSaveError;
  final Map<String, TextEditingController> _subjectControllers = {};
  final Map<String, TextEditingController> _bodyControllers = {};
  final Map<String, bool> _saving = {};
  final Map<String, String?> _saveErrors = {};

  AdminDashboardDelegate get delegate => widget.delegate;

  @override
  void initState() {
    super.initState();
    for (final template in _templateConfigs) {
      _subjectControllers[template.id] = TextEditingController();
      _bodyControllers[template.id] = TextEditingController();
      _saving[template.id] = false;
      _saveErrors[template.id] = null;
    }
    _load();
  }

  @override
  void dispose() {
    _emailFooterController.dispose();
    for (final controller in _subjectControllers.values) {
      controller.dispose();
    }
    for (final controller in _bodyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await delegate.apiClient.fetchSystemSettings(delegate.token);
      if (!mounted) return;
      _emailFooterController.text = (data['email_footer'] as String? ?? '').toString();
      for (final template in _templateConfigs) {
        _subjectControllers[template.id]!.text =
            (data[template.subjectKey] as String? ?? '').toString();
        _bodyControllers[template.id]!.text =
            (data[template.bodyKey] as String? ?? '').toString();
      }
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _saveTemplate(_EmailTemplateConfig template) async {
    setState(() {
      _saving[template.id] = true;
      _saveErrors[template.id] = null;
    });
    try {
      final subject = _subjectControllers[template.id]!.text.trim();
      final body = _bodyControllers[template.id]!.text;
      switch (template.id) {
        case 'demo_receipt':
          await delegate.apiClient.updateSystemSettingsMail(
            token: delegate.token,
            demoReceiptSubject: subject,
            demoReceiptBody: body,
          );
          break;
        case 'demo_rejection':
          await delegate.apiClient.updateSystemSettingsMail(
            token: delegate.token,
            demoRejectionSubject: subject,
            demoRejectionBody: body,
          );
          break;
        case 'demo_approval':
          await delegate.apiClient.updateSystemSettingsMail(
            token: delegate.token,
            demoApprovalSubject: subject,
            demoApprovalBody: body,
          );
          break;
        case 'portal_invite':
          await delegate.apiClient.updateSystemSettingsMail(
            token: delegate.token,
            portalInviteSubject: subject,
            portalInviteBody: body,
          );
          break;
        case 'groover_invite':
          await delegate.apiClient.updateSystemSettingsMail(
            token: delegate.token,
            grooverInviteSubject: subject,
            grooverInviteBody: body,
          );
          break;
        case 'update_profile_invite':
          await delegate.apiClient.updateSystemSettingsMail(
            token: delegate.token,
            updateProfileInviteSubject: subject,
            updateProfileInviteBody: body,
          );
          break;
        case 'password_reset':
          await delegate.apiClient.updateSystemSettingsMail(
            token: delegate.token,
            passwordResetSubject: subject,
            passwordResetBody: body,
          );
          break;
      }
      if (!mounted) return;
      setState(() => _saving[template.id] = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${template.title} template saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving[template.id] = false;
        _saveErrors[template.id] = e.toString();
      });
    }
  }

  Future<void> _saveEmailFooter() async {
    setState(() {
      _savingFooter = true;
      _footerSaveError = null;
    });
    try {
      await delegate.apiClient.updateSystemSettingsMail(
        token: delegate.token,
        emailFooter: _emailFooterController.text,
      );
      if (!mounted) return;
      setState(() => _savingFooter = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Global email footer saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingFooter = false;
        _footerSaveError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Copy error',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: _error!)),
                ),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Preview and edit all automatic LM emails in one place. The global footer at the bottom is appended to every outgoing message.',
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        for (final template in _templateConfigs) ...[
          _EmailTemplateCard(
            config: template,
            subjectController: _subjectControllers[template.id]!,
            bodyController: _bodyControllers[template.id]!,
            saving: _saving[template.id] ?? false,
            saveError: _saveErrors[template.id],
            onChanged: () => setState(() {}),
            onSave: () => _saveTemplate(template),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.45),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Global email footer',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This text is appended automatically to every outgoing email from the system.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailFooterController,
                  decoration: const InputDecoration(
                    labelText: 'Email footer',
                    hintText: 'Appended automatically to every outgoing email.',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 5,
                  minLines: 3,
                  textInputAction: TextInputAction.newline,
                ),
                if (_footerSaveError != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    _footerSaveError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy error',
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _footerSaveError!),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _savingFooter ? null : _saveEmailFooter,
                  icon: _savingFooter
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(ZalmanimIcons.save, size: 18),
                  label: Text(_savingFooter ? 'Saving...' : 'Save footer'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmailTemplateCard extends StatefulWidget {
  const _EmailTemplateCard({
    required this.config,
    required this.subjectController,
    required this.bodyController,
    required this.saving,
    required this.saveError,
    required this.onChanged,
    required this.onSave,
  });

  final _EmailTemplateConfig config;
  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final bool saving;
  final String? saveError;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  State<_EmailTemplateCard> createState() => _EmailTemplateCardState();
}

class _EmailTemplateCardState extends State<_EmailTemplateCard> {
  bool _expanded = false;
  bool _previewMode = true;

  @override
  Widget build(BuildContext context) {
    final renderedSubject = _renderTemplate(
      widget.subjectController.text.trim().isEmpty
          ? widget.config.subjectHint
          : widget.subjectController.text,
      widget.config.previewValues,
    );
    final renderedBody = _renderTemplate(
      widget.bodyController.text.trim().isEmpty
          ? widget.config.bodyHint
          : widget.bodyController.text,
      widget.config.previewValues,
    );

    return Card(
      child: ExpansionTile(
        initiallyExpanded: _expanded,
        onExpansionChanged: (value) => setState(() => _expanded = value),
        leading: const Icon(ZalmanimIcons.email),
        title: Text(widget.config.title),
        subtitle: Text(
          renderedSubject.isEmpty ? widget.config.subjectHint : renderedSubject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.config.description,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Preview'),
                selected: _previewMode,
                onSelected: (_) => setState(() => _previewMode = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Edit'),
                selected: !_previewMode,
                onSelected: (_) => setState(() => _previewMode = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_previewMode)
            _TemplatePreview(
              subject: renderedSubject,
              body: renderedBody,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: widget.subjectController,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    hintText: widget.config.subjectHint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) {
                    widget.onChanged();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                _PlaceholderWrap(
                    placeholders: widget.config.previewValues.keys.toList()),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.bodyController,
                  decoration: InputDecoration(
                    labelText: 'Body',
                    hintText: widget.config.bodyHint,
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 12,
                  minLines: 8,
                  onChanged: (_) {
                    widget.onChanged();
                    setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                if (widget.saveError != null) ...[
                  SelectableText(
                    widget.saveError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'Copy error',
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: widget.saveError!)),
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: widget.saving ? null : widget.onSave,
                    icon: widget.saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(ZalmanimIcons.save, size: 18),
                    label: Text(widget.saving ? 'Saving...' : 'Save template'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TemplatePreview extends StatelessWidget {
  const _TemplatePreview({
    required this.subject,
    required this.body,
  });

  final String subject;
  final String body;

  @override
  Widget build(BuildContext context) {
    final htmlPreview =
        '<p>${body.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('\n\n', '</p><p>').replaceAll('\n', '<br>')}</p>';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Subject', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(subject.isEmpty ? '(empty subject)' : subject),
          const SizedBox(height: 12),
          Text('Text preview', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(body.isEmpty ? '(empty body)' : body),
          const SizedBox(height: 12),
          Text('HTML source preview',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          SelectableText(
            htmlPreview,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderWrap extends StatelessWidget {
  const _PlaceholderWrap({required this.placeholders});

  final List<String> placeholders;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final placeholder in placeholders)
          Chip(
            label: Text('{$placeholder}'),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

String _renderTemplate(String template, Map<String, String> values) {
  var output = template;
  values.forEach((key, value) {
    output = output.replaceAll('{$key}', value);
  });
  return output;
}
