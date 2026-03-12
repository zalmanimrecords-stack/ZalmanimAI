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
    required this.createdAt,
  });

  final int id;
  final int? artistId;
  final List<int> artistIds;
  final List<String> artistNames;
  final String title;
  final String status;
  final String? filePath;
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
    return Release(
      id: json['id'] as int,
      artistId: json['artist_id'] as int?,
      artistIds: list,
      artistNames: artistNames,
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
        'artist_names': artistNames,
        'title': title,
        'status': status,
        'file_path': filePath,
        'created_at': createdAt,
      };
}