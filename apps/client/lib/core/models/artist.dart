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
    this.lastProfileUpdatedAt,
  });

  final int id;
  final String name;
  final String email;
  final String notes;
  final bool isActive;
  final Map<String, dynamic> extra;
  final Map<String, dynamic>? lastRelease;
  final DateTime? lastProfileUpdatedAt;

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

  /// Last profile update display: short date or "—".
  String get lastProfileUpdatedDisplay {
    if (lastProfileUpdatedAt == null) return '—';
    final d = lastProfileUpdatedAt!;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
    DateTime? lastProfileUpdatedAt;
    final lpu = json['last_profile_updated_at'];
    if (lpu != null) {
      if (lpu is String) {
        try {
          lastProfileUpdatedAt = DateTime.parse(lpu);
        } catch (_) {}
      }
    }
    return Artist(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      notes: (json['notes'] as String?) ?? '',
      isActive: json['is_active'] as bool? ?? true,
      extra: extra is Map<String, dynamic> ? extra : {},
      lastRelease: json['last_release'] as Map<String, dynamic>?,
      lastProfileUpdatedAt: lastProfileUpdatedAt,
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
      if (lastProfileUpdatedAt != null) 'last_profile_updated_at': lastProfileUpdatedAt!.toIso8601String(),
    };
  }
}
