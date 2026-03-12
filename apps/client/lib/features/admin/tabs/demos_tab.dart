import 'package:flutter/material.dart';

import '../admin_dashboard_delegate.dart';

class DemosTab extends StatelessWidget {
  const DemosTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  Color _statusColor(BuildContext context, String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'in_review':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final demos = delegate.demoSubmissionsList;
    return RefreshIndicator(
      onRefresh: delegate.loadDemoSubmissions,
      child: demos.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(child: Text('No demo submissions yet.')),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: demos.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = demos[index] as Map<String, dynamic>;
                final artistName = (item['artist_name'] ?? '').toString();
                final email = (item['email'] ?? '').toString();
                final genre = (item['genre'] ?? '').toString();
                final city = (item['city'] ?? '').toString();
                final status = (item['status'] ?? 'demo').toString();
                final sentAt = (item['approval_email_sent_at'] ?? '').toString();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                artistName.isEmpty ? email : artistName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Chip(
                              label: Text(status),
                              labelStyle: const TextStyle(color: Colors.white),
                              backgroundColor: _statusColor(context, status),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (email.isNotEmpty) Text(email),
                            if (genre.isNotEmpty) Text('Genre: $genre'),
                            if (city.isNotEmpty) Text('City: $city'),
                            if (sentAt.isNotEmpty) Text('Approval sent: $sentAt'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => delegate.showDemoDetailsDialog(item),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Details'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: status == 'approved'
                                  ? null
                                  : () => delegate.showApproveDemoDialog(item),
                              icon: const Icon(Icons.mark_email_read_outlined),
                              label: const Text('Approve'),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton<String>(
                              onSelected: (value) => delegate.updateDemoStatus(item, value),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'demo', child: Text('Mark as demo')),
                                PopupMenuItem(value: 'in_review', child: Text('Mark in review')),
                                PopupMenuItem(value: 'rejected', child: Text('Mark rejected')),
                              ],
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.more_horiz),
                                    SizedBox(width: 4),
                                    Text('Status'),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
