import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Tab showing artist messages to the label (inbox). Admin can open a thread and reply; reply is emailed to the artist.
class InboxTab extends StatelessWidget {
  const InboxTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    final items = delegate.inboxThreadsList;
    return RefreshIndicator(
      onRefresh: () => delegate.loadInbox(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Text(
                  'Inbox',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => delegate.loadInbox(),
                  icon: const Icon(ZalmanimIcons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'No messages yet. When artists send a message from their portal, they appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index] as Map<String, dynamic>;
                      final threadId = item['id'] as int? ?? 0;
                      final artistName = item['artist_name']?.toString() ?? '-';
                      final artistEmail = item['artist_email']?.toString() ?? '';
                      final preview = (item['last_message_preview'] ?? '').toString();
                      final lastAt = (item['last_message_at'] ?? item['updated_at'] ?? '').toString();
                      final hasReply = item['has_label_reply'] == true;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            hasReply ? Icons.mark_email_read : Icons.mail_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(artistName),
                          subtitle: Text(
                            preview.isEmpty ? 'No subject' : preview.length > 80 ? '${preview.substring(0, 80)}...' : preview,
                            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: hasReply
                              ? const Chip(label: Text('Replied'), padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0))
                              : null,
                          onTap: () => delegate.showInboxThreadDialog(threadId),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
