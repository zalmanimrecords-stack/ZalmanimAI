/// API release model (matches server ReleaseOut).
class Release {
  const Release({
    required this.id,
    this.artistId,
    this.artistIds = const [],
    required this.title,
    required this.status,
    this.filePath,
    required this.createdAt,
  });

  final int id;
  final int? artistId;
  final List<int> artistIds;
  final String title;
  final String status;
  final String? filePath;
  final String createdAt;

  bool get hasNoArtist => artistIds.isEmpty;

  factory Release.fromJson(Map<String, dynamic> json) {
    final ids = json['artist_ids'];
    List<int> list = const [];
    if (ids is List) {
      list = ids.map((e) => (e is int) ? e : int.tryParse(e.toString()) ?? 0).where((e) => e != 0).toList();
    }
    return Release(
      id: json['id'] as int,
      artistId: json['artist_id'] as int?,
      artistIds: list,
      title: (json['title'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      filePath: json['file_path'] as String?,
      createdAt: (json['created_at']?.toString()) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'artist_id': artistId,
        'artist_ids': artistIds,
        'title': title,
        'status': status,
        'file_path': filePath,
        'created_at': createdAt,
      };
}
