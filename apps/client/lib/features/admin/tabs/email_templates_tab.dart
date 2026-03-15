import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Settings > Email templates: manage all outgoing email templates in one place.
/// Each template type is edited in its own sub-tab.
class EmailTemplatesTab extends StatefulWidget {
  const EmailTemplatesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<EmailTemplatesTab> createState() => _EmailTemplatesTabState();
}

class _EmailTemplatesTabState extends State<EmailTemplatesTab> {
  bool _loading = true;
  String? _error;
  bool _savingRejection = false;
  bool _savingApproval = false;
  bool _savingPortalInvite = false;
  String? _rejectionSaveError;
  String? _approvalSaveError;
  String? _portalInviteSaveError;

  final _rejectionSubjectController = TextEditingController();
  final _rejectionBodyController = TextEditingController();
  final _approvalSubjectController = TextEditingController();
  final _approvalBodyController = TextEditingController();
  final _portalInviteSubjectController = TextEditingController();
  final _portalInviteBodyController = TextEditingController();

  AdminDashboardDelegate get delegate => widget.delegate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rejectionSubjectController.dispose();
    _rejectionBodyController.dispose();
    _approvalSubjectController.dispose();
    _approvalBodyController.dispose();
    _portalInviteSubjectController.dispose();
    _portalInviteBodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _rejectionSaveError = null;
      _approvalSaveError = null;
    });
    try {
      final data = await delegate.apiClient.fetchSystemSettings(delegate.token);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _rejectionSubjectController.text =
            (data['demo_rejection_subject'] as String? ?? '').toString();
        _rejectionBodyController.text =
            (data['demo_rejection_body'] as String? ?? '').toString();
        _approvalSubjectController.text =
            (data['demo_approval_subject'] as String? ?? '').toString();
        _approvalBodyController.text =
            (data['demo_approval_body'] as String? ?? '').toString();
        _portalInviteSubjectController.text =
            (data['portal_invite_subject'] as String? ?? '').toString();
        _portalInviteBodyController.text =
            (data['portal_invite_body'] as String? ?? '').toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveRejection() async {
    setState(() {
      _savingRejection = true;
      _rejectionSaveError = null;
    });
    try {
      await delegate.apiClient.updateSystemSettingsMail(
        token: delegate.token,
        demoRejectionSubject: _rejectionSubjectController.text.trim(),
        demoRejectionBody: _rejectionBodyController.text,
      );
      if (!mounted) return;
      setState(() {
        _savingRejection = false;
        _rejectionSaveError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo rejection template saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingRejection = false;
        _rejectionSaveError = e.toString();
      });
    }
  }

  Future<void> _saveApproval() async {
    setState(() {
      _savingApproval = true;
      _approvalSaveError = null;
    });
    try {
      await delegate.apiClient.updateSystemSettingsMail(
        token: delegate.token,
        demoApprovalSubject: _approvalSubjectController.text.trim(),
        demoApprovalBody: _approvalBodyController.text,
      );
      if (!mounted) return;
      setState(() {
        _savingApproval = false;
        _approvalSaveError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo approval template saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingApproval = false;
        _approvalSaveError = e.toString();
      });
    }
  }

  Future<void> _savePortalInvite() async {
    setState(() {
      _savingPortalInvite = true;
      _portalInviteSaveError = null;
    });
    try {
      await delegate.apiClient.updateSystemSettingsMail(
        token: delegate.token,
        portalInviteSubject: _portalInviteSubjectController.text.trim(),
        portalInviteBody: _portalInviteBodyController.text,
      );
      if (!mounted) return;
      setState(() {
        _savingPortalInvite = false;
        _portalInviteSaveError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Portal invite template saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingPortalInvite = false;
        _portalInviteSaveError = e.toString();
      });
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
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
    return DefaultTabController(
      length: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: TabBar(
              tabs: [
                Tab(
                  icon: Icon(
                    ZalmanimIcons.email,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Artist reminder',
                ),
                Tab(
                  icon: Icon(
                    Icons.cancel_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Demo rejection',
                ),
                Tab(
                  icon: Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Demo approval',
                ),
                Tab(
                  icon: Icon(
                    ZalmanimIcons.campaignRequests,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  text: 'Portal invite',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ArtistReminderSubTab(
                  delegate: delegate,
                  sectionTitle: _sectionTitle,
                ),
                _DemoRejectionSubTab(
                  sectionTitle: _sectionTitle,
                  subjectController: _rejectionSubjectController,
                  bodyController: _rejectionBodyController,
                  saving: _savingRejection,
                  saveError: _rejectionSaveError,
                  onChanged: () => setState(() {}),
                  onSave: _saveRejection,
                ),
                _DemoApprovalSubTab(
                  sectionTitle: _sectionTitle,
                  subjectController: _approvalSubjectController,
                  bodyController: _approvalBodyController,
                  saving: _savingApproval,
                  saveError: _approvalSaveError,
                  onChanged: () => setState(() {}),
                  onSave: _saveApproval,
                ),
                _PortalInviteSubTab(
                  sectionTitle: _sectionTitle,
                  subjectController: _portalInviteSubjectController,
                  bodyController: _portalInviteBodyController,
                  saving: _savingPortalInvite,
                  saveError: _portalInviteSaveError,
                  onChanged: () => setState(() {}),
                  onSave: _savePortalInvite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Sub-tab: Artist reminder email template (opens dialog).
class _ArtistReminderSubTab extends StatelessWidget {
  const _ArtistReminderSubTab({
    required this.delegate,
    required this.sectionTitle,
  });

  final AdminDashboardDelegate delegate;
  final Widget Function(String) sectionTitle;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle('Artist reminder email'),
          const Text(
            'Default subject and body for reminder emails sent from '
            'Reports > Artist reminders. Supports placeholders like '
            '{name}, {email}, {artist_brand}.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () =>
                delegate.showArtistReminderMailSettingsDialog(context),
            icon: const Icon(ZalmanimIcons.edit, size: 18),
            label: const Text('Edit artist reminder template'),
          ),
        ],
      ),
    );
  }
}

/// Sub-tab: Demo rejection email template (subject + body + save).
class _DemoRejectionSubTab extends StatelessWidget {
  const _DemoRejectionSubTab({
    required this.sectionTitle,
    required this.subjectController,
    required this.bodyController,
    required this.saving,
    required this.saveError,
    required this.onChanged,
    required this.onSave,
  });

  final Widget Function(String) sectionTitle;
  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final bool saving;
  final String? saveError;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle('Demo rejection email'),
          const Text(
            'Sent when you reject a demo submission. Placeholders: '
            '{artist_name}, {artist_portal_url}, {zalmanim_website}.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subjectController,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Thank you for your demo submission',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bodyController,
            decoration: const InputDecoration(
              labelText: 'Body',
              hintText: 'Hi {artist_name}, ...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 8,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          if (saveError != null) ...[
            SelectableText(
              saveError!,
              style: const TextStyle(color: Colors.red),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: saveError!)),
            ),
          ],
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(ZalmanimIcons.save, size: 18),
            label: Text(
              saving ? 'Saving...' : 'Save demo rejection template',
            ),
          ),
        ],
      ),
    );
  }
}

/// Sub-tab: Demo approval email template (subject + body + save).
class _DemoApprovalSubTab extends StatelessWidget {
  const _DemoApprovalSubTab({
    required this.sectionTitle,
    required this.subjectController,
    required this.bodyController,
    required this.saving,
    required this.saveError,
    required this.onChanged,
    required this.onSave,
  });

  final Widget Function(String) sectionTitle;
  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final bool saving;
  final String? saveError;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle('Demo approval email (default)'),
          const Text(
            'Default subject and body when approving a demo. Used when '
            'the approval dialog does not override them. '
            'Placeholder: {artist_name}.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subjectController,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Your demo was approved, {artist_name}',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bodyController,
            decoration: const InputDecoration(
              labelText: 'Body',
              hintText: 'Hi {artist_name}, ...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 8,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          if (saveError != null) ...[
            SelectableText(
              saveError!,
              style: const TextStyle(color: Colors.red),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: saveError!)),
            ),
          ],
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(ZalmanimIcons.save, size: 18),
            label: Text(
              saving ? 'Saving...' : 'Save demo approval template',
            ),
          ),
        ],
      ),
    );
  }
}

/// Sub-tab: Portal invite email template (subject + body + save).
class _PortalInviteSubTab extends StatelessWidget {
  const _PortalInviteSubTab({
    required this.sectionTitle,
    required this.subjectController,
    required this.bodyController,
    required this.saving,
    required this.saveError,
    required this.onChanged,
    required this.onSave,
  });

  final Widget Function(String) sectionTitle;
  final TextEditingController subjectController;
  final TextEditingController bodyController;
  final bool saving;
  final String? saveError;
  final VoidCallback onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          sectionTitle('Portal invite email'),
          const Text(
            'Sent when you send an artist portal access (single or “Send portal invite to all”). '
            'Placeholders: {display_name}, {portal_url}, {username}, {temporary_password}.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: subjectController,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Your Zalmanim Artists Portal access',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: bodyController,
            decoration: const InputDecoration(
              labelText: 'Body',
              hintText: 'Hi {display_name}, ...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 8,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: 8),
          if (saveError != null) ...[
            SelectableText(
              saveError!,
              style: const TextStyle(color: Colors.red),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: saveError!)),
            ),
          ],
          FilledButton.icon(
            onPressed: saving ? null : onSave,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(ZalmanimIcons.save, size: 18),
            label: Text(
              saving ? 'Saving...' : 'Save portal invite template',
            ),
          ),
        ],
      ),
    );
  }
}
