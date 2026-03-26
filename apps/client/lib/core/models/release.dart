/// API release model (matches server ReleaseOut).
class Release {
  const Release({
    required this.id,
    this.artistId,
    this.artistIds = const [],
    this.artistNames = const [],
    required this.title,
    required this.status,
    this.filePath,
    this.coverImageUrl,
    this.coverImageSourceUrl,
    this.platformLinks = const {},
    this.pendingLinkCandidatesCount = 0,
    this.lastLinkScanAt,
    required this.createdAt,
  });

  final int id;
  final int? artistId;
  final List<int> artistIds;
  final List<String> artistNames;
  final String title;
  final String status;
  final String? filePath;
  final String? coverImageUrl;
  final String? coverImageSourceUrl;
  final Map<String, String> platformLinks;
  final int pendingLinkCandidatesCount;
  final String? lastLinkScanAt;
  final String createdAt;

  bool get hasNoArtist => artistIds.isEmpty;

  factory Release.fromJson(Map<String, dynamic> json) {
    final ids = json['artist_ids'];
    List<int> list = const [];
    if (ids is List) {
      list = ids
          .map((e) => (e is int) ? e : int.tryParse(e.toString()) ?? 0)
          .where((e) => e != 0)
          .toList();
    }
    final names = json['artist_names'];
    final artistNames = names is List
        ? names
            .map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList()
        : const <String>[];
    final rawPlatformLinks = json['platform_links'];
    final platformLinks = <String, String>{};
    if (rawPlatformLinks is Map) {
      rawPlatformLinks.forEach((key, value) {
        final k = key?.toString().trim() ?? '';
        final v = value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          platformLinks[k] = v;
        }
      });
    }
    final pendingCount = json['pending_link_candidates_count'];
    return Release(
      id: json['id'] as int,
      artistId: json['artist_id'] as int?,
      artistIds: list,
      artistNames: artistNames,
      title: (json['title'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      filePath: json['file_path'] as String?,
      coverImageUrl: json['cover_image_url'] as String?,
      coverImageSourceUrl: json['cover_image_source_url'] as String?,
      platformLinks: platformLinks,
      pendingLinkCandidatesCount: pendingCount is int
          ? pendingCount
          : int.tryParse(pendingCount?.toString() ?? '') ?? 0,
      lastLinkScanAt: json['last_link_scan_at']?.toString(),
      createdAt: (json['created_at']?.toString()) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'artist_id': artistId,
        'artist_ids': artistIds,
        'artist_names': artistNames,
        'title': title,
        'status': status,
        'file_path': filePath,
        'cover_image_url': coverImageUrl,
        'cover_image_source_url': coverImageSourceUrl,
        'platform_links': platformLinks,
        'pending_link_candidates_count': pendingLinkCandidatesCount,
        'last_link_scan_at': lastLinkScanAt,
        'created_at': createdAt,
      };
}
