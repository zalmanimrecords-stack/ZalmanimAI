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
    required this.theme,
    required this.galleryImageUrls,
    this.profileImageUrl,
    this.logoUrl,
    this.headline,
    this.bio,
  });

  final int artistId;
  final String name;
  final List<LinktreeLink> links;
  final List<LinktreeRelease> releases;
  final String theme;
  final List<String> galleryImageUrls;
  final String? profileImageUrl;
  final String? logoUrl;
  final String? headline;
  final String? bio;

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
    final galleryRaw = data['gallery_image_urls'] is List
        ? data['gallery_image_urls'] as List
        : <dynamic>[];
    final gallery = galleryRaw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
    final name = (data['name']?.toString().trim() ?? 'Artist');
    final profileImageUrl = data['profile_image_url']?.toString().trim();
    final logoUrl = data['logo_url']?.toString().trim();
    final headline = data['headline']?.toString().trim();
    final bio = data['bio']?.toString().trim();
    final theme = (data['theme']?.toString().trim().toLowerCase() ?? 'ocean');
    return LinktreeOut(
      artistId: data['artist_id'] as int,
      name: name,
      links: links,
      releases: releases,
      theme: theme.isEmpty ? 'ocean' : theme,
      galleryImageUrls: gallery,
      profileImageUrl: profileImageUrl != null && profileImageUrl.isNotEmpty ? profileImageUrl : null,
      logoUrl: logoUrl != null && logoUrl.isNotEmpty ? logoUrl : null,
      headline: headline != null && headline.isNotEmpty ? headline : null,
      bio: bio != null && bio.isNotEmpty ? bio : null,
    );
  }
}
