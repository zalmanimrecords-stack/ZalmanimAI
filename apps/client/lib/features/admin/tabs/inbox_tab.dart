import 'package:flutter/material.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

class InboxTabLabel extends StatelessWidget {
  const InboxTabLabel({
    super.key,
    required this.iconColor,
    required this.unreadCount,
  });

  final Color iconColor;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ZalmanimIcons.email, size: 20, color: iconColor),
        const SizedBox(width: 8),
        const Text('Inbox'),
        if (unreadCount > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.shade700,
              borderRadius: BorderRadius.circular(999),
            ),
            constraints: const BoxConstraints(minWidth: 22),
            child: Text(
              '$unreadCount',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

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
                      final preview = (item['last_message_preview'] ?? '').toString();
                      final hasReply = item['has_label_reply'] == true;
                      final unreadCount = item['unread_count'] is num
                          ? (item['unread_count'] as num).toInt()
                          : 0;
                      final hasUnread = unreadCount > 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            hasUnread
                                ? Icons.mark_email_unread
                                : hasReply
                                    ? Icons.mark_email_read
                                    : Icons.mail_outline,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          title: Text(
                            artistName,
                            style: TextStyle(
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            preview.isEmpty ? 'No subject' : preview.length > 80 ? '${preview.substring(0, 80)}...' : preview,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[700],
                              fontWeight:
                                  hasUnread ? FontWeight.w600 : FontWeight.w400,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasUnread)
                                Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade700,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '$unreadCount',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              if (hasReply)
                                const Chip(
                                  label: Text('Replied'),
                                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                                ),
                              TextButton.icon(
                                onPressed: threadId <= 0
                                    ? null
                                    : () => delegate.deleteInboxThread(threadId, artistName),
                                icon: const Icon(Icons.delete_outline, size: 18),
                                label: const Text('Delete'),
                              ),
                            ],
                          ),
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
