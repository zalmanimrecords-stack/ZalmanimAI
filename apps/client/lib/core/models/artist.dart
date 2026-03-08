/// API artist model (matches server ArtistOut).
class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.email,
    required this.notes,
    required this.isActive,
    this.extra = const {},
    this.lastRelease,
  });

  final int id;
  final String name;
  final String email;
  final String notes;
  final bool isActive;
  final Map<String, dynamic> extra;
  final Map<String, dynamic>? lastRelease;

  String get brand =>
      (extra['artist_brand']?.toString().trim() ?? name).trim();

  String get fullName =>
      (extra['full_name']?.toString().trim() ?? '').trim();

  List<String> get artistBrands {
    final list = extra['artist_brands'];
    if (list is! List) return [];
    return list
        .map((e) => e?.toString().trim())
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toList();
  }

  String get displayName {
    if (brand.isNotEmpty) return brand;
    if (fullName.isNotEmpty) return fullName;
    return 'Unknown';
  }

  /// Last release display: "Title" or "Title (date)" or "—".
  String get lastReleaseDisplay {
    final lr = lastRelease;
    if (lr == null) return '—';
    final title = lr['title'] as String?;
    if (title == null || title.isEmpty) return '—';
    final created = lr['created_at'] as String?;
    if (created != null && created.isNotEmpty) {
      try {
        final dt = DateTime.parse(created);
        return '$title (${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')})';
      } catch (_) {}
    }
    return title;
  }

  factory Artist.fromJson(Map<String, dynamic> json) {
    final extra = json['extra'];
    return Artist(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      isActive: json['is_active'] as bool? ?? true,
      extra: extra is Map<String, dynamic> ? extra : {},
      lastRelease: json['last_release'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'notes': notes,
      'is_active': isActive,
      'extra': extra,
      if (lastRelease != null) 'last_release': lastRelease,
    };
  }
}
