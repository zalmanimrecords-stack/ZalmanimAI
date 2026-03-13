import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

class AudienceTab extends StatelessWidget {
  const AudienceTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  Widget build(BuildContext context) {
    final audiences = delegate.audiencesList.cast<Map<String, dynamic>>();
    final subscribers = delegate.audienceSubscribersList.cast<Map<String, dynamic>>();
    final selectedAudienceId = delegate.selectedAudienceId;
    Map<String, dynamic>? selectedAudience;
    for (final audience in audiences) {
      if (audience['id'] == selectedAudienceId) {
        selectedAudience = audience;
        break;
      }
    }

    return RefreshIndicator(
      onRefresh: delegate.loadAudiences,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Audience',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Manage mailing lists, consent metadata, and unsubscribe-ready subscribers before importing from Mailchimp.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: delegate.showCreateAudienceDialog,
                icon: const Icon(ZalmanimIcons.add),
                label: const Text('New list'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (audiences.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No mailing lists yet. Create the first list to start building the email system.'),
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: audiences.map((audience) {
                final isSelected = audience['id'] == selectedAudienceId;
                final subscribedCount = audience['subscribed_count'] ?? 0;
                final unsubscribedCount = audience['unsubscribed_count'] ?? 0;
                return SizedBox(
                  width: 280,
                  child: Card(
                    color: isSelected ? Theme.of(context).colorScheme.primaryContainer : null,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => delegate.selectAudience(audience['id'] as int),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    (audience['name'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Edit list',
                                  onPressed: () => delegate.showEditAudienceDialog(audience),
                                  icon: const Icon(ZalmanimIcons.edit, size: 18),
                                ),
                              ],
                            ),
                            if (((audience['description'] ?? '').toString()).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  audience['description'].toString(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text('Subscribed: $subscribedCount', style: const TextStyle(fontSize: 12)),
                            Text('Unsubscribed: $unsubscribedCount', style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            selectedAudience == null
                                ? 'Select a mailing list'
                                : 'Subscribers in ${(selectedAudience['name'] ?? '').toString()}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (selectedAudienceId != null)
                          FilledButton.icon(
                            onPressed: delegate.showAddAudienceSubscriberDialog,
                            icon: const Icon(ZalmanimIcons.personAdd),
                            label: const Text('Add subscriber'),
                          ),
                      ],
                    ),
                    if (selectedAudience != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Company: ${((selectedAudience['company_name'] ?? '').toString()).isEmpty ? '-' : selectedAudience['company_name']}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        'Reply-to: ${((selectedAudience['reply_to_email'] ?? '').toString()).isEmpty ? '-' : selectedAudience['reply_to_email']}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      Text(
                        'Address: ${((selectedAudience['physical_address'] ?? '').toString()).isEmpty ? '-' : selectedAudience['physical_address']}',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (selectedAudienceId == null)
                      const Text('Choose a list above to see its subscribers.')
                    else if (subscribers.isEmpty)
                      const Text('This list has no subscribers yet.')
                    else
                      ...subscribers.map((subscriber) {
                        final status = (subscriber['status'] ?? '').toString();
                        final unsubscribeUrl = (subscriber['unsubscribe_url'] ?? '').toString();
                        final identity = ((subscriber['full_name'] ?? subscriber['email'] ?? '?').toString()).trim();
                        final avatarLetter = identity.isEmpty ? '?' : identity[0].toUpperCase();
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(child: Text(avatarLetter)),
                          title: Text(
                            ((subscriber['full_name'] ?? '').toString()).isEmpty
                                ? subscriber['email'].toString()
                                : subscriber['full_name'].toString(),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(subscriber['email'].toString()),
                              Text(
                                'Status: $status | Consent: ${((subscriber['consent_source'] ?? '').toString()).isEmpty ? '-' : subscriber['consent_source']}',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Copy unsubscribe link',
                                onPressed: unsubscribeUrl.isEmpty
                                    ? null
                                    : () {
                                        Clipboard.setData(ClipboardData(text: unsubscribeUrl));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Unsubscribe link copied.')),
                                        );
                                      },
                                icon: const Icon(ZalmanimIcons.link, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Edit subscriber',
                                onPressed: () => delegate.showEditAudienceSubscriberDialog(subscriber),
                                icon: const Icon(ZalmanimIcons.edit, size: 18),
                              ),
                              TextButton(
                                onPressed: () => delegate.toggleAudienceSubscriberStatus(subscriber),
                                child: Text(status == 'unsubscribed' ? 'Resubscribe' : 'Unsubscribe'),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


