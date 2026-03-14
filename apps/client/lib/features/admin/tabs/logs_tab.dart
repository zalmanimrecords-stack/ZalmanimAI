import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Settings > Logs: system and mail logs. Technical and error logs.
class LogsTab extends StatefulWidget {
  const LogsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  List<dynamic> _logs = [];
  bool _loading = true;
  String? _error;
  /// When true, show only entries with level == 'error' (LB and artist portal errors).
  bool _errorsOnly = false;

  AdminDashboardDelegate get delegate => widget.delegate;

  List<dynamic> get _filteredLogs {
    if (!_errorsOnly) return _logs;
    return _logs.where((e) => (e as Map<String, dynamic>)['level'] == 'error').toList();
  }

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
      final list = await delegate.apiClient.fetchSystemLogs(delegate.token);
      if (!mounted) return;
      setState(() {
        _logs = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Color _levelColor(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Colors.red.shade700;
      case 'warning':
        return Colors.orange.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  String _formatTime(dynamic createdAt) {
    if (createdAt == null) return '';
    final s = createdAt.toString();
    if (s.length > 19) return s.substring(0, 19).replaceFirst('T', ' ');
    return s;
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
    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ZalmanimIcons.settings, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No system or mail logs yet.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Errors from the API (LB), artist portal, and mail will appear here.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final displayed = _filteredLogs;
    if (displayed.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No error entries.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              'Turn off "Errors only" to see all logs.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilterChip(
              label: const Text('Errors only'),
              selected: _errorsOnly,
              onSelected: (v) => setState(() => _errorsOnly = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: displayed.length,
              itemBuilder: (context, i) {
                final log = displayed[i] as Map<String, dynamic>;
                final level = (log['level'] ?? 'info').toString();
                final category = (log['category'] ?? '').toString();
                final message = (log['message'] ?? '').toString();
                final details = log['details']?.toString();
                final createdAt = _formatTime(log['created_at']);
                final fullText = [
                  '[$level] [$category] $createdAt',
                  message,
                  if (details != null && details.isNotEmpty) details,
                ].join('\n');
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _levelColor(level).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                level.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _levelColor(level),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              category,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              createdAt,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(ZalmanimIcons.copy, size: 18),
                              tooltip: 'Copy',
                              onPressed: () => Clipboard.setData(ClipboardData(text: fullText)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          message,
                          style: const TextStyle(fontSize: 14),
                        ),
                        if (details != null && details.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          SelectableText(
                            details,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          ),
                        ],
                      ],
                    ),
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
