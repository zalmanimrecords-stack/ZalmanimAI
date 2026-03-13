import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Settings > Email templates: manage all outgoing email templates in one place.
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
  String? _rejectionSaveError;
  String? _approvalSaveError;

  final _rejectionSubjectController = TextEditingController();
  final _rejectionBodyController = TextEditingController();
  final _approvalSubjectController = TextEditingController();
  final _approvalBodyController = TextEditingController();

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
        _rejectionSubjectController.text = (data['demo_rejection_subject'] as String? ?? '').toString();
        _rejectionBodyController.text = (data['demo_rejection_body'] as String? ?? '').toString();
        _approvalSubjectController.text = (data['demo_approval_subject'] as String? ?? '').toString();
        _approvalBodyController.text = (data['demo_approval_body'] as String? ?? '').toString();
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo rejection template saved.')));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Demo approval template saved.')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingApproval = false;
        _approvalSaveError = e.toString();
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
                  onPressed: () => Clipboard.setData(ClipboardData(text: _error!)),
                ),
                FilledButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Artist reminder email'),
          const Text(
            'Default subject and body for reminder emails sent from Reports > Artist reminders. Supports placeholders like {name}, {email}, {artist_brand}.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => delegate.showArtistReminderMailSettingsDialog(context),
            icon: const Icon(ZalmanimIcons.edit, size: 18),
            label: const Text('Edit artist reminder template'),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Demo rejection email'),
          const Text(
            'Sent when you reject a demo submission. Placeholders: {artist_name}, {artist_portal_url}, {zalmanim_website}.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _rejectionSubjectController,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Thank you for your demo submission',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rejectionBodyController,
            decoration: const InputDecoration(
              labelText: 'Body',
              hintText: 'Hi {artist_name}, ...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 8,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (_rejectionSaveError != null) ...[
            SelectableText(_rejectionSaveError!, style: const TextStyle(color: Colors.red)),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () => Clipboard.setData(ClipboardData(text: _rejectionSaveError!)),
            ),
          ],
          FilledButton.icon(
            onPressed: _savingRejection ? null : _saveRejection,
            icon: _savingRejection
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(ZalmanimIcons.save, size: 18),
            label: Text(_savingRejection ? 'Saving...' : 'Save demo rejection template'),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Demo approval email (default)'),
          const Text(
            'Default subject and body when approving a demo. Used when the approval dialog does not override them. Placeholder: {artist_name}.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _approvalSubjectController,
            decoration: const InputDecoration(
              labelText: 'Subject',
              hintText: 'Your demo was approved, {artist_name}',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _approvalBodyController,
            decoration: const InputDecoration(
              labelText: 'Body',
              hintText: 'Hi {artist_name}, ...',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 8,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (_approvalSaveError != null) ...[
            SelectableText(_approvalSaveError!, style: const TextStyle(color: Colors.red)),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () => Clipboard.setData(ClipboardData(text: _approvalSaveError!)),
            ),
          ],
          FilledButton.icon(
            onPressed: _savingApproval ? null : _saveApproval,
            icon: _savingApproval
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(ZalmanimIcons.save, size: 18),
            label: Text(_savingApproval ? 'Saving...' : 'Save demo approval template'),
          ),
        ],
      ),
    );
  }
}
