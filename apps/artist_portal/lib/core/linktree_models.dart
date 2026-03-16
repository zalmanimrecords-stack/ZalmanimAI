/// DTOs for public linktree API response (matches server LinktreeOut).
class LinktreeLink {
  LinktreeLink({required this.label, required this.url});
  final String label;
  final String url;

  static LinktreeLink? fromJson(dynamic e) {
    if (e is! Map<String, dynamic>) return null;
    final url = (e['url'] ?? '').toString().trim();
    if (url.isEmpty) return null;
    final label = (e['label'] ?? e['url'] ?? 'Link').toString();
    return LinktreeLink(label: label, url: url);
  }
}

class LinktreeRelease {
  LinktreeRelease({required this.title, this.url});
  final String title;
  final String? url;

  static LinktreeRelease? fromJson(dynamic e) {
    if (e is! Map<String, dynamic>) return null;
    final title = (e['title'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final url = e['url']?.toString().trim();
    return LinktreeRelease(title: title, url: url?.isEmpty == true ? null : url);
  }
}

class LinktreeOut {
  LinktreeOut({
    required this.artistId,
    required this.name,
    required this.links,
    required this.releases,
    this.profileImageUrl,
    this.logoUrl,
  });

  final int artistId;
  final String name;
  final List<LinktreeLink> links;
  final List<LinktreeRelease> releases;
  final String? profileImageUrl;
  final String? logoUrl;

  static LinktreeOut fromJson(Map<String, dynamic> data) {
    final linksRaw = data['links'] is List ? data['links'] as List : <dynamic>[];
    final links = linksRaw
        .map((e) => LinktreeLink.fromJson(e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}))
        .whereType<LinktreeLink>()
        .toList();
    final releasesRaw = data['releases'] is List ? data['releases'] as List : <dynamic>[];
    final releases = releasesRaw
        .map((e) => LinktreeRelease.fromJson(e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}))
        .whereType<LinktreeRelease>()
        .toList();
    final name = (data['name']?.toString().trim() ?? 'Artist');
    final profileImageUrl = data['profile_image_url']?.toString().trim();
    final logoUrl = data['logo_url']?.toString().trim();
    return LinktreeOut(
      artistId: data['artist_id'] as int,
      name: name,
      links: links,
      releases: releases,
      profileImageUrl: profileImageUrl != null && profileImageUrl.isNotEmpty ? profileImageUrl : null,
      logoUrl: logoUrl != null && logoUrl.isNotEmpty ? logoUrl : null,
    );
  }
}
