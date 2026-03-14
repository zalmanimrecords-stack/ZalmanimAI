import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../admin_dashboard_delegate.dart';

/// Settings > DB: list tables and view table content (read-only).
class DbTab extends StatefulWidget {
  const DbTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<DbTab> createState() => _DbTabState();
}

class _DbTabState extends State<DbTab> {
  List<dynamic> _tables = [];
  String? _selectedTable;
  Map<String, dynamic>? _tableData;
  bool _loadingTables = true;
  bool _loadingContent = false;
  String? _error;
  static const int _pageSize = 100;

  AdminDashboardDelegate get delegate => widget.delegate;

  @override
  void initState() {
    super.initState();
    _loadTables();
  }

  Future<void> _loadTables() async {
    setState(() {
      _loadingTables = true;
      _error = null;
      _selectedTable = null;
      _tableData = null;
    });
    try {
      final list = await delegate.apiClient.fetchDbTables(delegate.token);
      if (!mounted) return;
      setState(() {
        _tables = list;
        _loadingTables = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingTables = false;
      });
    }
  }

  Future<void> _loadTableContent(String tableName, {int offset = 0}) async {
    setState(() {
      _selectedTable = tableName;
      _loadingContent = true;
      _error = null;
    });
    try {
      final data = await delegate.apiClient.fetchDbTableContent(
        delegate.token,
        tableName,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _tableData = data;
        _loadingContent = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingContent = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingTables) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tables.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(_error!, style: const TextStyle(color: Colors.red)),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () => Clipboard.setData(ClipboardData(text: _error!)),
            ),
            FilledButton(onPressed: _loadTables, child: const Text('Retry')),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 220,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        'Tables',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: 'Refresh',
                        onPressed: _loadingTables ? null : _loadTables,
                      ),
                    ],
                  ),
                ),
                ..._tables.map<Widget>((t) {
                  final name = (t is Map ? t['name'] : t).toString();
                  final selected = _selectedTable == name;
                  return ListTile(
                    title: Text(
                      name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : null,
                      ),
                    ),
                    selected: selected,
                    onTap: () => _loadTableContent(name),
                  );
                }),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _buildContentPanel(),
        ),
      ],
    );
  }

  Widget _buildContentPanel() {
    if (_selectedTable == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.table_chart_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Select a table to view its content',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    if (_loadingContent) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tableData == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SelectableText(_error!, style: const TextStyle(color: Colors.red)),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy error',
              onPressed: () => Clipboard.setData(ClipboardData(text: _error!)),
            ),
            FilledButton(
              onPressed: () => _loadTableContent(_selectedTable!),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    final data = _tableData!;
    final rows = data['rows'] as List<dynamic>? ?? [];
    final totalCount = data['total_count'] as int? ?? 0;
    final limit = data['limit'] as int? ?? _pageSize;
    final offset = data['offset'] as int? ?? 0;
    if (rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Table "$_selectedTable" is empty.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    final columnNames = _columnNames(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                _selectedTable!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(width: 16),
              Text(
                '${offset + 1}–${offset + rows.length} of $totalCount',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const Spacer(),
              if (offset > 0)
                TextButton.icon(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  label: const Text('Previous'),
                  onPressed: () => _loadTableContent(_selectedTable!, offset: offset - limit),
                ),
              if (offset + rows.length < totalCount)
                TextButton.icon(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  label: const Text('Next'),
                  onPressed: () => _loadTableContent(_selectedTable!, offset: offset + limit),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                columns: columnNames
                    .map((c) => DataColumn(
                          label: Tooltip(
                            message: c,
                            child: Text(c, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ))
                    .toList(),
                rows: rows.map<DataRow>((r) {
                  final map = r as Map<String, dynamic>;
                  return DataRow(
                    cells: columnNames
                        .map((col) => DataCell(
                              SelectableText(
                                _cellText(map[col]),
                                maxLines: 2,
                              ),
                            ))
                        .toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<String> _columnNames(List<dynamic> rows) {
    if (rows.isEmpty) return [];
    final first = rows.first as Map<String, dynamic>;
    return first.keys.toList();
  }

  String _cellText(dynamic value) {
    if (value == null) return '';
    final s = value.toString();
    if (s.length > 80) return '${s.substring(0, 80)}…';
    return s;
  }
}
