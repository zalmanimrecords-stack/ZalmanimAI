/// API catalog track model (matches server CatalogTrackOut).
class CatalogTrack {
  const CatalogTrack({
    required this.id,
    required this.catalogNumber,
    required this.releaseTitle,
    this.preOrderDate,
    this.releaseDate,
    this.upc,
    this.isrc,
    this.originalArtists,
    this.trackTitle,
    this.mixTitle,
    this.duration,
    required this.createdAt,
  });

  final int id;
  final String catalogNumber;
  final String releaseTitle;
  final String? preOrderDate;
  final String? releaseDate;
  final String? upc;
  final String? isrc;
  final String? originalArtists;
  final String? trackTitle;
  final String? mixTitle;
  final String? duration;
  final String createdAt;

  String get releaseDateDisplay => releaseDate ?? '';

  factory CatalogTrack.fromJson(Map<String, dynamic> json) {
    return CatalogTrack(
      id: json['id'] as int,
      catalogNumber: (json['catalog_number'] as String?) ?? '',
      releaseTitle: (json['release_title'] as String?) ?? '',
      preOrderDate: json['pre_order_date']?.toString(),
      releaseDate: json['release_date']?.toString(),
      upc: json['upc']?.toString(),
      isrc: json['isrc']?.toString(),
      originalArtists: json['original_artists']?.toString(),
      trackTitle: json['track_title']?.toString(),
      mixTitle: json['mix_title']?.toString(),
      duration: json['duration']?.toString(),
      createdAt: (json['created_at']?.toString()) ?? '',
    );
  }
}
