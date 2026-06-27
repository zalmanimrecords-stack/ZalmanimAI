import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Reusable HTML/text templates for native email campaigns (LabelOps audiences).
class CampaignEmailTemplatesTab extends StatefulWidget {
  const CampaignEmailTemplatesTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<CampaignEmailTemplatesTab> createState() =>
      _CampaignEmailTemplatesTabState();
}

class _CampaignEmailTemplatesTabState extends State<CampaignEmailTemplatesTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _templates = [];

  AdminDashboardDelegate get delegate => widget.delegate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await delegate.apiClient.listCampaignEmailTemplates(
        token: delegate.token,
      );
      if (!mounted) return;
      setState(() {
        _templates = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _showEditor({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final nameController =
        TextEditingController(text: existing?['name'] as String? ?? '');
    final descController = TextEditingController(
        text: existing?['description'] as String? ?? '');
    final subjectController =
        TextEditingController(text: existing?['subject'] as String? ?? '');
    final bodyController =
        TextEditingController(text: existing?['body_text'] as String? ?? '');
    final saving = ValueNotifier<bool>(false);

    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit template' : 'New campaign template'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Template name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subjectController,
                  decoration: const InputDecoration(labelText: 'Subject line'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Body',
                    helperText:
                        'Placeholders: {{first_name}}, {{full_name}}, {{email}}, {{unsubscribe_url}}',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: saving,
            builder: (_, busy, __) => FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final subject = subjectController.text.trim();
                      if (name.isEmpty || subject.isEmpty) return;
                      saving.value = true;
                      try {
                        if (isEdit) {
                          await delegate.apiClient.updateCampaignEmailTemplate(
                            token: delegate.token,
                            id: existing['id'] as int,
                            name: name,
                            subject: subject,
                            description: descController.text.trim(),
                            bodyText: bodyController.text,
                          );
                        } else {
                          await delegate.apiClient.createCampaignEmailTemplate(
                            token: delegate.token,
                            name: name,
                            subject: subject,
                            description: descController.text.trim(),
                            bodyText: bodyController.text,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: SelectableText(e.toString())),
                          );
                        }
                      } finally {
                        saving.value = false;
                      }
                    },
              child: busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEdit ? 'Save' : 'Create'),
            ),
          ),
        ],
      ),
    );
    nameController.dispose();
    descController.dispose();
    subjectController.dispose();
    bodyController.dispose();
    if (saved == true) await _load();
  }

  Future<void> _deleteTemplate(Map<String, dynamic> row) async {
    final id = row['id'] as int;
    final name = row['name'] as String? ?? 'template';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete template?'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await delegate.apiClient.deleteCampaignEmailTemplate(
        token: delegate.token,
        id: id,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SelectableText(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SelectableText(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Retry')),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Email templates',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Use when creating campaigns with the LabelOps email audience. '
                      'Unsubscribe and list footer are added automatically on send.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showEditor(),
                icon: const Icon(ZalmanimIcons.add),
                label: const Text('New template'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_templates.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No campaign templates yet.'),
              ),
            )
          else
            ..._templates.map((row) {
              return Card(
                child: ListTile(
                  title: Text(row['name'] as String? ?? ''),
                  subtitle: Text(
                    row['subject'] as String? ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(ZalmanimIcons.edit),
                        tooltip: 'Edit',
                        onPressed: () => _showEditor(existing: row),
                      ),
                      IconButton(
                        icon: const Icon(ZalmanimIcons.delete),
                        tooltip: 'Delete',
                        onPressed: () => _deleteTemplate(row),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
