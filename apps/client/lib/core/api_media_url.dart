/// Rewrites API-hosted pending-release image URLs to use the same origin as [apiBaseUrl].
///
/// Stored URLs may point at another host (e.g. old dev URL in the database) while the app
/// is configured for production — the browser then fails to load them. External URLs are unchanged.
String resolveApiMediaUrl(String apiBaseUrl, String? rawUrl) {
  final raw = rawUrl?.trim() ?? '';
  if (raw.isEmpty) return raw;
  final parsed = Uri.tryParse(raw);
  if (parsed == null) return raw;
  final api = Uri.parse(apiBaseUrl);
  final origin = Uri(
    scheme: api.scheme,
    userInfo: api.userInfo,
    host: api.host,
    port: api.hasPort ? api.port : null,
  );
  if (!parsed.hasScheme || parsed.host.isEmpty) {
    final p = raw.startsWith('/') ? raw : '/$raw';
    return origin.resolve(p.substring(1)).toString();
  }
  final path = parsed.path.isEmpty ? '/' : parsed.path;
  if (path.contains('/public/pending-release') || path.contains('/public/releases/')) {
    var p = path;
    if (!p.startsWith('/api')) {
      p = '/api$p';
    }
    return origin.replace(path: p, query: parsed.query).toString();
  }
  return raw;
}
