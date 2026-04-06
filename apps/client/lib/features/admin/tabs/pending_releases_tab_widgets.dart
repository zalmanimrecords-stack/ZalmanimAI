part of 'pending_releases_tab.dart';

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _DetailsTableCard extends StatelessWidget {
  const _DetailsTableCard({
    required this.title,
    required this.rows,
    required this.onOpenLink,
  });

  final String title;
  final List<_DetailRow> rows;
  final Future<void> Function(String value) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          Table(
            columnWidths: const <int, TableColumnWidth>{
              0: FixedColumnWidth(156),
              1: FlexColumnWidth(),
            },
            children: [
              for (int i = 0; i < rows.length; i++)
                TableRow(
                  decoration: BoxDecoration(
                    color: i.isEven ? Colors.transparent : scheme.surfaceContainerHighest.withOpacity(0.28),
                  ),
                  children: [
                    _DetailLabelCell(label: rows[i].label),
                    _DetailValueCell(
                      row: rows[i],
                      onOpenLink: onOpenLink,
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailLabelCell extends StatelessWidget {
  const _DetailLabelCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _DetailValueCell extends StatelessWidget {
  const _DetailValueCell({
    required this.row,
    required this.onOpenLink,
  });

  final _DetailRow row;
  final Future<void> Function(String value) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            row.value,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          if (row.isLink) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => onOpenLink(row.value),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open link'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ImageGalleryCard extends StatelessWidget {
  const _ImageGalleryCard({
    required this.title,
    required this.previews,
    required this.onOpenLink,
    required this.resolveMediaUrl,
    required this.onDownloadReleaseImage,
    required this.pendingReleaseId,
    required this.busyImageOps,
    required this.imageBusyKey,
    required this.storedDeleteBusyKey,
    required this.isServerStoredImageUrl,
    required this.onDeleteStoredImage,
    required this.onNormalizeImage,
    this.action,
  });

  final String title;
  final List<_ImagePreview> previews;
  final Future<void> Function(String value) onOpenLink;
  final String Function(String? url) resolveMediaUrl;
  final Future<void> Function(
    _ImagePreview preview,
    int index,
    String displayUrl,
  ) onDownloadReleaseImage;
  final int pendingReleaseId;
  final Set<String> busyImageOps;
  final String Function(int pendingReleaseId, String imageId, String op)
      imageBusyKey;
  final String Function(int pendingReleaseId, String imageUrl)
      storedDeleteBusyKey;
  final bool Function(String url) isServerStoredImageUrl;
  final Future<void> Function(int pendingReleaseId, String imageUrl)
      onDeleteStoredImage;
  final Future<void> Function(int pendingReleaseId, String imageId)
      onNormalizeImage;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.secondary.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.secondary,
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: previews.isEmpty
                ? Text(
                    'No release images yet. Upload one or more options so the artist can choose the best fit.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                : Column(
                    children: [
                      for (int i = 0; i < previews.length; i++) ...[
                        if (i > 0) const SizedBox(height: 16),
                        _ImagePreviewTile(
                          preview: previews[i],
                          imageIndex: i,
                          onOpenLink: onOpenLink,
                          onDownloadReleaseImage: onDownloadReleaseImage,
                          displayUrl: resolveMediaUrl(previews[i].url),
                          pendingReleaseId: pendingReleaseId,
                          busyImageOps: busyImageOps,
                          imageBusyKey: imageBusyKey,
                          storedDeleteBusyKey: storedDeleteBusyKey,
                          canDeleteStored:
                              isServerStoredImageUrl(previews[i].url),
                          onDeleteStoredImage: onDeleteStoredImage,
                          onNormalizeImage: onNormalizeImage,
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommentFeedCard extends StatelessWidget {
  const _CommentFeedCard({
    required this.comments,
    required this.onAddComment,
  });

  final List<Map<String, dynamic>> comments;
  final VoidCallback onAddComment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.tertiary.withOpacity(0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Release forum',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.tertiary,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onAddComment,
                  icon: const Icon(Icons.forum_outlined),
                  label: const Text('Add update'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: comments.isEmpty
                ? Text(
                    'No updates yet. Use this area like a mini forum for release progress.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  )
                : Column(
                    children: [
                      for (int i = 0; i < comments.length; i++) ...[
                        _CommentTile(comment: comments[i]),
                        if (i < comments.length - 1)
                          const SizedBox(height: 12),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sender = (comment['sender'] ?? '').toString() == 'artist'
        ? 'Artist'
        : 'Label';
    final createdAt = (comment['created_at'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            createdAt.isEmpty ? sender : '$sender - $createdAt',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            (comment['body'] ?? '').toString(),
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ImagePreviewTile extends StatefulWidget {
  const _ImagePreviewTile({
    required this.preview,
    required this.imageIndex,
    required this.onOpenLink,
    required this.onDownloadReleaseImage,
    required this.displayUrl,
    required this.pendingReleaseId,
    required this.busyImageOps,
    required this.imageBusyKey,
    required this.storedDeleteBusyKey,
    required this.canDeleteStored,
    required this.onDeleteStoredImage,
    required this.onNormalizeImage,
  });

  final _ImagePreview preview;
  final int imageIndex;
  final Future<void> Function(String value) onOpenLink;
  final Future<void> Function(
    _ImagePreview preview,
    int index,
    String displayUrl,
  ) onDownloadReleaseImage;
  final String displayUrl;
  final int pendingReleaseId;
  final Set<String> busyImageOps;
  final String Function(int pendingReleaseId, String imageId, String op)
      imageBusyKey;
  final String Function(int pendingReleaseId, String imageUrl)
      storedDeleteBusyKey;
  final bool canDeleteStored;
  final Future<void> Function(int pendingReleaseId, String imageUrl)
      onDeleteStoredImage;
  final Future<void> Function(int pendingReleaseId, String imageId)
      onNormalizeImage;

  @override
  State<_ImagePreviewTile> createState() => _ImagePreviewTileState();
}

class _ImagePreviewTileState extends State<_ImagePreviewTile> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await widget.onDownloadReleaseImage(
        widget.preview,
        widget.imageIndex,
        widget.displayUrl,
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const previewBox = 500.0;
    final scheme = Theme.of(context).colorScheme;
    final mid = widget.preview.managementImageId;
    final busyStoredDel = widget.busyImageOps.contains(
      widget.storedDeleteBusyKey(widget.pendingReleaseId, widget.preview.url),
    );
    final busyJpg = mid != null &&
        widget.busyImageOps
            .contains(widget.imageBusyKey(widget.pendingReleaseId, mid, 'jpg'));
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: scheme.surfaceContainerHighest.withOpacity(0.25),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.preview.label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (widget.preview.subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                widget.preview.subtitle,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _downloading ? null : _download,
                icon: _downloading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.primary,
                        ),
                      )
                    : const Icon(ZalmanimIcons.download, size: 18),
                label: Text(_downloading ? 'Downloadingâ€¦' : 'Download'),
              ),
              OutlinedButton.icon(
                onPressed: () => widget.onOpenLink(widget.preview.url),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open'),
              ),
              if (widget.canDeleteStored)
                OutlinedButton.icon(
                  onPressed: busyStoredDel || busyJpg
                      ? null
                      : () => widget.onDeleteStoredImage(
                            widget.pendingReleaseId,
                            widget.preview.url,
                          ),
                  icon: busyStoredDel
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        )
                      : const Icon(Icons.delete_outline, size: 18),
                  label: Text(busyStoredDel ? 'Removingâ€¦' : 'Delete'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                  ),
                ),
              if (mid != null)
                OutlinedButton.icon(
                  onPressed: busyStoredDel || busyJpg
                      ? null
                      : () => widget.onNormalizeImage(widget.pendingReleaseId, mid),
                  icon: busyJpg
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_size_select_large_outlined,
                          size: 18),
                  label: Text(busyJpg ? 'Convertingâ€¦' : 'JPG 3000Ã—3000'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: previewBox,
                height: previewBox,
                child: Image.network(
                  widget.displayUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: scheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Text('Could not preview image'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isLink = false,
  });

  final String label;
  final String value;
  final bool isLink;
}

class _ImagePreview {
  const _ImagePreview({
    required this.label,
    required this.url,
    this.subtitle = '',
    this.suggestedFilename,
    this.managementImageId,
  });

  final String label;
  final String url;
  final String subtitle;
  /// Hint for download filename (e.g. original upload name or URL path segment).
  final String? suggestedFilename;
  /// Label-uploaded option id (delete / normalize); null for reference URLs only.
  final String? managementImageId;
}

enum _PendingReleaseRemovalAction {
  archive,
  delete,
}
