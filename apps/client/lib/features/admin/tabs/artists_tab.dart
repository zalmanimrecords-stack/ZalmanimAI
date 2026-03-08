import 'package:flutter/material.dart';

import '../../../core/models/artist.dart';
import '../admin_dashboard_delegate.dart';

/// Artists tab: list, search, sort, add/edit/remove/merge, view releases.
class ArtistsTab extends StatelessWidget {
  const ArtistsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  static int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final query = delegate.artistSearchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? delegate.artistsList
        : delegate.artistsList.where((a) {
            final artist = Artist.fromJson(a as Map<String, dynamic>);
            final brand = artist.brand.toLowerCase();
            final fullName = artist.fullName.toLowerCase();
            final email = artist.email.toLowerCase();
            final brands = artist.artistBrands.join(' ').toLowerCase();
            return brand.contains(query) ||
                fullName.contains(query) ||
                email.contains(query) ||
                brands.contains(query);
          }).toList();

    final sorted = List<dynamic>.from(filtered);
    sorted.sort((a, b) {
      final ar = Artist.fromJson(a as Map<String, dynamic>);
      final br = Artist.fromJson(b as Map<String, dynamic>);
      String va;
      String vb;
      switch (delegate.artistsSortColumn) {
        case 0:
          va = ar.brand.toLowerCase();
          vb = br.brand.toLowerCase();
          break;
        case 1:
          va = ar.fullName.toLowerCase();
          vb = br.fullName.toLowerCase();
          break;
        case 2:
          va = ar.email.toLowerCase();
          vb = br.email.toLowerCase();
          break;
        case 3:
          va = ar.lastReleaseDisplay.toLowerCase();
          vb = br.lastReleaseDisplay.toLowerCase();
          break;
        default:
          va = '';
          vb = '';
      }
      final cmp = _compareString(va, vb);
      return delegate.artistsSortAsc ? cmp : -cmp;
    });

    const sideMargin = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth * 0.9;
        final height = constraints.maxHeight * 0.9;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: RefreshIndicator(
              onRefresh: delegate.load,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(sideMargin, 12, sideMargin, 8),
                    child: TextField(
                      controller: delegate.artistSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search artists (brand, name, email)...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(sideMargin, 8, sideMargin, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Artists',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: delegate.showAddArtistDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add artist'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: delegate.artistsList.isEmpty
                              ? null
                              : delegate.showMergeArtistsDialog,
                          icon: const Icon(Icons.merge_type),
                          label: const Text('Merge artists'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: sideMargin),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Table(
                            columnWidths: const {
                              0: FixedColumnWidth(160),
                              1: FixedColumnWidth(160),
                              2: FixedColumnWidth(220),
                              3: FixedColumnWidth(180),
                              4: FixedColumnWidth(140),
                            },
                            defaultColumnWidth: const IntrinsicColumnWidth(),
                            children: [
                              TableRow(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                ),
                                children: [
                                  _sortableHeader(context, 'Brand', 0),
                                  _sortableHeader(context, 'Full name', 1),
                                  _sortableHeader(context, 'Email', 2),
                                  _sortableHeader(
                                    context,
                                    'Last Release',
                                    3,
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 5,
                                    ),
                                    child: Text(
                                      '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              ...sorted.map<TableRow>((a) {
                                final artist = Artist.fromJson(
                                  a as Map<String, dynamic>,
                                );
                                return TableRow(
                                  decoration: artist.isActive
                                      ? null
                                      : BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.5),
                                        ),
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      child: Row(
                                        children: [
                                          if (!artist.isActive)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              child: Chip(
                                                label: const Text(
                                                  'Inactive',
                                                  style: TextStyle(fontSize: 11),
                                                ),
                                                padding: EdgeInsets.zero,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                          Expanded(
                                            child: ClipRect(
                                              child: SelectableText(
                                                artist.brand.isEmpty
                                                    ? '—'
                                                    : artist.brand,
                                                maxLines: 1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      child: ClipRect(
                                        child: SelectableText(
                                          artist.fullName.isEmpty
                                              ? '—'
                                              : artist.fullName,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      child: ClipRect(
                                        child: SelectableText(
                                          artist.email,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 9,
                                      ),
                                      child: ClipRect(
                                        child: SelectableText(
                                          artist.lastReleaseDisplay,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                        vertical: 5,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: const Icon(
                                              Icons.info_outline,
                                              color: Colors.grey,
                                              size: 22,
                                            ),
                                            tooltip: 'Details & logs',
                                            onPressed: () =>
                                                delegate.showArtistDetailsDialog(
                                              artist.id,
                                            ),
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.album,
                                              color: Colors.blue,
                                              size: 22,
                                            ),
                                            tooltip: 'View releases',
                                            onPressed: () =>
                                                delegate.showArtistReleases(
                                              artist.id,
                                              artist.displayName,
                                            ),
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit,
                                              color: Colors.orange,
                                              size: 22,
                                            ),
                                            tooltip: 'Edit',
                                            onPressed: () =>
                                                delegate.showEditArtistDialog(
                                              artist.id,
                                            ),
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                              size: 22,
                                            ),
                                            tooltip: 'Remove',
                                            onPressed: () =>
                                                delegate.removeArtist(
                                              artist.id,
                                              artist.displayName,
                                            ),
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sortableHeader(
    BuildContext context,
    String label,
    int columnIndex,
  ) {
    final isActive = delegate.artistsSortColumn == columnIndex;
    return InkWell(
      onTap: () => delegate.setArtistsSort(
        columnIndex,
        isActive ? !delegate.artistsSortAsc : true,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (isActive)
              Icon(
                delegate.artistsSortAsc
                    ? Icons.arrow_drop_up
                    : Icons.arrow_drop_down,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
