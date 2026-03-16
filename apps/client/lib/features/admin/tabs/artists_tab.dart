import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/artist.dart';
import '../../../core/zalmanim_icons.dart';
import '../admin_dashboard_delegate.dart';

/// Artists tab: list, search, sort, add/edit/remove/merge, view releases.
class ArtistsTab extends StatefulWidget {
  const ArtistsTab({super.key, required this.delegate});

  final AdminDashboardDelegate delegate;

  @override
  State<ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends State<ArtistsTab> {
  final _verticalController = ScrollController();
  final _horizontalController = ScrollController();

  static const double _rowHeight = 56;
  static const double _headerHeight = 48;
  static const double _minTableWidth = 1280;

  AdminDashboardDelegate get delegate => widget.delegate;

  static int _compareString(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  @override
  void initState() {
    super.initState();
    _verticalController.addListener(_handleScroll);
    delegate.artistSearchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    delegate.artistSearchController.removeListener(_onSearchChanged);
    _verticalController.removeListener(_handleScroll);
    _verticalController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _handleScroll() {
    if (!_verticalController.hasClients) return;
    final position = _verticalController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      delegate.loadMoreArtists();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Server-side search is used when the user types; artistsList is already filtered by the API.
    final listToShow = delegate.artistsList;

    final sorted = List<dynamic>.from(listToShow);
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
        case 4:
          va = ar.lastProfileUpdatedDisplay.toLowerCase();
          vb = br.lastProfileUpdatedDisplay.toLowerCase();
          break;
        case 5:
          va = ar.lastEmailSentDisplay.toLowerCase();
          vb = br.lastEmailSentDisplay.toLowerCase();
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
        final width = constraints.maxWidth * 0.95;
        final height = constraints.maxHeight * 0.9;
        final tableWidth = math.max(width - (sideMargin * 2), _minTableWidth);
        final brandWidth = tableWidth * 0.14;
        final nameWidth = tableWidth * 0.14;
        final emailWidth = tableWidth * 0.20;
        final releaseWidth = tableWidth * 0.18;
        final profileUpdatedWidth = tableWidth * 0.10;
        final lastEmailWidth = tableWidth * 0.10;
        final actionsWidth = tableWidth * 0.14;

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: RefreshIndicator(
              onRefresh: delegate.loadArtists,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(sideMargin, 12, sideMargin, 8),
                    child: TextField(
                      controller: delegate.artistSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search artists (brand, name, email)...',
                        prefixIcon: const Icon(ZalmanimIcons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: delegate.showAddArtistDialog,
                          icon: const Icon(ZalmanimIcons.add),
                          label: const Text('Add artist'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: delegate.artistsList.isEmpty ? null : delegate.showMergeArtistsDialog,
                          icon: const Icon(ZalmanimIcons.merge),
                          label: const Text('Merge artists'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: delegate.sendArtistPortalInviteToAll,
                          icon: const Icon(ZalmanimIcons.campaignRequests),
                          label: const Text('Send portal invite to all'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: sideMargin),
                      child: Scrollbar(
                        controller: _horizontalController,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: tableWidth,
                            child: Column(
                              children: [
                                Container(
                                  height: _headerHeight,
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: Row(
                                    children: [
                                      _headerCell(context, 'Brand', 0, brandWidth),
                                      _headerCell(context, 'Full name', 1, nameWidth),
                                      _headerCell(context, 'Email', 2, emailWidth),
                                      _headerCell(context, 'Last Release', 3, releaseWidth),
                                      _headerCell(context, 'Profile updated', 4, profileUpdatedWidth),
                                      _headerCell(context, 'Last email sent', 5, lastEmailWidth),
                                      SizedBox(width: actionsWidth),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    controller: _verticalController,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    itemCount: sorted.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == sorted.length) {
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          child: _buildFooter(context),
                                        );
                                      }
                                      final artist = Artist.fromJson(sorted[index] as Map<String, dynamic>);
                                      final bgColor = artist.isActive
                                          ? null
                                          : Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.5);
                                      return Container(
                                        height: _rowHeight,
                                        color: bgColor,
                                        child: Row(
                                          children: [
                                            _brandCell(artist, brandWidth),
                                            _textCell(artist.fullName.isEmpty ? '-' : artist.fullName, nameWidth),
                                            _textCell(artist.email, emailWidth),
                                            _textCell(artist.lastReleaseDisplay, releaseWidth),
                                            _textCell(artist.lastProfileUpdatedDisplay, profileUpdatedWidth),
                                            _textCell(artist.lastEmailSentDisplay, lastEmailWidth),
                                            SizedBox(
                                              width: actionsWidth,
                                              child: SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.end,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    _actionButton(
                                                      icon: ZalmanimIcons.info,
                                                      color: Colors.grey,
                                                      tooltip: 'Details & logs',
                                                      onPressed: () => delegate.showArtistDetailsDialog(artist.id),
                                                    ),
                                                    _actionButton(
                                                      icon: ZalmanimIcons.releases,
                                                      color: Colors.blue,
                                                      tooltip: 'View releases',
                                                      onPressed: () => delegate.showArtistReleases(
                                                        artist.id,
                                                        artist.displayName,
                                                      ),
                                                    ),
                                                    _actionButton(
                                                      icon: ZalmanimIcons.edit,
                                                      color: Colors.orange,
                                                      tooltip: 'Edit',
                                                      onPressed: () => delegate.showEditArtistDialog(artist.id),
                                                    ),
                                                    _actionButton(
                                                      icon: ZalmanimIcons.campaignRequests,
                                                      color: Colors.indigo,
                                                      tooltip: 'Send portal access email',
                                                      onPressed: () => delegate.sendArtistPortalInvite(
                                                        artist.id,
                                                        artist.displayName,
                                                        artist.email,
                                                      ),
                                                    ),
                                                    _actionButton(
                                                      icon: ZalmanimIcons.delete,
                                                      color: Colors.red,
                                                      tooltip: 'Remove',
                                                      onPressed: () => delegate.removeArtist(
                                                        artist.id,
                                                        artist.displayName,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
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

  Widget _buildFooter(BuildContext context) {
    if (delegate.artistsLoadingMore) {
      return const Center(child: CircularProgressIndicator());
    }
    if (delegate.artistsHasMore) {
      return Text(
        'Scroll down to load more artists',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _headerCell(BuildContext context, String label, int columnIndex, double width) {
    final isActive = delegate.artistsSortColumn == columnIndex;
    return InkWell(
      onTap: () => delegate.setArtistsSort(
        columnIndex,
        isActive ? !delegate.artistsSortAsc : true,
      ),
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Row(
            children: [
              Flexible(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              if (isActive)
                Icon(
                  delegate.artistsSortAsc ? ZalmanimIcons.arrowDropUp : ZalmanimIcons.arrowDropDown,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _brandCell(Artist artist, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            if (!artist.isActive)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Chip(
                  label: const Text('Inactive', style: TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            Expanded(
              child: Text(
                artist.brand.isEmpty ? '-' : artist.brand,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            text.isEmpty ? '-' : text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        icon: Icon(icon, color: color, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
