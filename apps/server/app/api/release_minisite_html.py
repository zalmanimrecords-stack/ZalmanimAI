"""Release minisite HTML rendering."""

import html
from typing import Any

from fastapi import Request

from app.api.release_minisite_helpers import release_base_url, release_minisite_config
from app.models.models import Release
from app.services.release_link_discovery import parse_platform_links

def release_minisite_gallery_urls(request: Request, release: Release, config: dict) -> list[str]:
    urls: list[str] = []
    if getattr(release, "cover_image_path", None):
        urls.append(f"{release_base_url(request)}/public/releases/{release.id}/cover-image")
    raw_gallery = config.get("gallery_urls")
    if isinstance(raw_gallery, list):
        for item in raw_gallery:
            value = str(item or "").strip()
            if value and value not in urls:
                urls.append(value)
    return urls


def _release_minisite_theme(theme_key: str) -> dict[str, str]:
    themes = {
        "nebula": {
            "bg": "radial-gradient(circle at top, #1f355e 0%, #07111f 55%, #02060c 100%)",
            "panel": "rgba(8, 17, 30, 0.72)",
            "text": "#f2f7ff",
            "muted": "#b8c8df",
            "accent": "#7ad8ff",
            "border": "rgba(122, 216, 255, 0.22)",
        },
        "sunset_poster": {
            "bg": "linear-gradient(145deg, #f7d794 0%, #f19066 45%, #6d214f 100%)",
            "panel": "rgba(87, 25, 74, 0.78)",
            "text": "#fff7ef",
            "muted": "#ffe3cb",
            "accent": "#ffd166",
            "border": "rgba(255, 209, 102, 0.28)",
        },
        "paperwave": {
            "bg": "linear-gradient(180deg, #f5efe1 0%, #dfe7dc 100%)",
            "panel": "rgba(255, 252, 246, 0.88)",
            "text": "#263126",
            "muted": "#51624f",
            "accent": "#1f7a6c",
            "border": "rgba(31, 122, 108, 0.18)",
        },
    }
    return themes.get(theme_key, themes["nebula"])


def _release_candidate_status_allows_link(status_value: Any) -> bool:
    status = str(status_value or "").strip()
    return status not in {"rejected", "auto_rejected"}


def _release_candidate_platform_url(candidate: Any) -> tuple[str, str]:
    platform = str(getattr(candidate, "platform", "") or "").strip()
    url = str(getattr(candidate, "url", "") or "").strip()
    return platform, url


def _select_best_platform_candidate_links(candidates: list[Any], existing_links: dict[str, str]) -> dict[str, tuple[float, str]]:
    best_by_platform: dict[str, tuple[float, str]] = {}
    for candidate in candidates:
        if not _release_candidate_status_allows_link(getattr(candidate, "status", "")):
            continue
        platform, url = _release_candidate_platform_url(candidate)
        if not platform or not url or existing_links.get(platform):
            continue
        confidence = float(getattr(candidate, "confidence", 0.0) or 0.0)
        current = best_by_platform.get(platform)
        if current is None or confidence > current[0]:
            best_by_platform[platform] = (confidence, url)
    return best_by_platform


def _release_minisite_platform_links(release: Release) -> dict[str, str]:
    links = parse_platform_links(getattr(release, "platform_links_json", None))
    candidates = getattr(release, "link_candidates", []) or []
    best_candidates = _select_best_platform_candidate_links(candidates, links)
    for platform, (_, url) in best_candidates.items():
        links[platform] = url
    return links


def _release_minisite_artist_name(release: Release) -> str:
    artist_names = [a.name for a in getattr(release, "artists", []) or [] if (a.name or "").strip()]
    if not artist_names and getattr(release, "artist", None) is not None and (release.artist.name or "").strip():
        artist_names = [release.artist.name.strip()]
    return ", ".join(artist_names) or "Unknown Artist"


def _release_minisite_artist_extra(release: Release) -> dict[str, Any]:
    artist = getattr(release, "artist", None)
    if artist is None or not getattr(artist, "extra_json", None):
        return {}
    try:
        data = json.loads(artist.extra_json) or {}
    except (json.JSONDecodeError, TypeError):
        return {}
    return data if isinstance(data, dict) else {}


def _release_minisite_socials(artist_extra: dict[str, Any]) -> list[tuple[str, str]]:
    socials: list[tuple[str, str]] = []
    for key in ("website", "instagram", "spotify", "soundcloud", "youtube", "apple_music", "linktree"):
        value = str(artist_extra.get(key) or "").strip()
        if value:
            url = value if "://" in value else f"https://{value}"
            socials.append((key.replace("_", " ").title(), url))
    return socials


def _release_minisite_platform_links_markup(platform_links: dict[str, str]) -> str:
    return "".join(
        f'<a class="pill" href="{html.escape(url)}" target="_blank" rel="noopener">{html.escape(label.replace("_", " ").title())}</a>'
        for label, url in sorted(platform_links.items())
    )


def _release_minisite_gallery_markup(release: Release, gallery_urls: list[str]) -> str:
    return "".join(
        f'<img src="{html.escape(url)}" alt="{html.escape(release.title)} artwork" />'
        for url in gallery_urls
    )


def _release_minisite_social_markup(socials: list[tuple[str, str]]) -> str:
    return "".join(
        f'<a class="social" href="{html.escape(url)}" target="_blank" rel="noopener">{html.escape(label)}</a>'
        for label, url in socials
    )


def release_minisite_html(request: Request, release: Release, config: dict) -> str:
    theme_name = str(config.get("theme") or "nebula").strip() or "nebula"
    theme = _release_minisite_theme(theme_name)
    artist_name = _release_minisite_artist_name(release)
    description = str(config.get("description") or "").strip()
    download_url = str(config.get("download_url") or "").strip()
    gallery_urls = release_minisite_gallery_urls(request, release, config)
    platform_links = _release_minisite_platform_links(release)
    artist_extra = _release_minisite_artist_extra(release)
    artist_blurb = str(artist_extra.get("full_name") or artist_extra.get("artist_brand") or "").strip()
    socials = _release_minisite_socials(artist_extra)
    links_markup = _release_minisite_platform_links_markup(platform_links)
    gallery_markup = _release_minisite_gallery_markup(release, gallery_urls)
    social_markup = _release_minisite_social_markup(socials)
    release_date = release.created_at.strftime("%Y-%m-%d") if getattr(release, "created_at", None) else ""
    download_markup = (
        f'<a class="cta" href="{html.escape(download_url)}" target="_blank" rel="noopener">Download Release</a>'
        if download_url
        else ""
    )
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(release.title)} | {html.escape(artist_name)}</title>
  <style>
    :root {{
      --bg: {theme["bg"]};
      --panel: {theme["panel"]};
      --text: {theme["text"]};
      --muted: {theme["muted"]};
      --accent: {theme["accent"]};
      --border: {theme["border"]};
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: Georgia, "Times New Roman", serif;
      color: var(--text);
      background: var(--bg);
      min-height: 100vh;
    }}
    .wrap {{
      max-width: 1080px;
      margin: 0 auto;
      padding: 28px 18px 60px;
    }}
    .hero {{
      display: grid;
      grid-template-columns: minmax(220px, 360px) 1fr;
      gap: 24px;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 28px;
      padding: 24px;
      backdrop-filter: blur(14px);
      box-shadow: 0 20px 70px rgba(0,0,0,.22);
    }}
    .hero img {{
      width: 100%;
      aspect-ratio: 1 / 1;
      object-fit: cover;
      border-radius: 22px;
      border: 1px solid var(--border);
    }}
    .eyebrow {{ color: var(--muted); text-transform: uppercase; letter-spacing: .18em; font-size: 12px; }}
    h1 {{ margin: 10px 0 8px; font-size: clamp(36px, 6vw, 70px); line-height: .96; }}
    h2 {{ margin: 0 0 16px; font-size: clamp(20px, 2vw, 26px); color: var(--muted); font-weight: 500; }}
    p {{ line-height: 1.7; }}
    .meta {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 18px 0; }}
    .pill, .social {{
      display: inline-flex; align-items: center; justify-content: center;
      padding: 10px 14px; border-radius: 999px; text-decoration: none;
      color: var(--text); border: 1px solid var(--border); background: rgba(255,255,255,.04);
      margin: 0 10px 10px 0;
    }}
    .cta {{
      display: inline-block; margin-top: 10px; text-decoration: none; font-weight: 700;
      background: var(--accent); color: #07111f; padding: 14px 18px; border-radius: 999px;
    }}
    .section {{
      margin-top: 24px; background: var(--panel); border: 1px solid var(--border);
      border-radius: 24px; padding: 20px;
    }}
    .gallery {{
      display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 16px;
    }}
    .gallery img {{
      width: 100%; aspect-ratio: 1 / 1; object-fit: cover; border-radius: 18px; border: 1px solid var(--border);
    }}
    @media (max-width: 780px) {{
      .hero {{ grid-template-columns: 1fr; }}
    }}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="hero">
      <div>{f'<img src="{html.escape(gallery_urls[0])}" alt="{html.escape(release.title)} cover" />' if gallery_urls else ''}</div>
      <div>
        <div class="eyebrow">Release Minisite</div>
        <h1>{html.escape(release.title)}</h1>
        <h2>{html.escape(artist_name)}</h2>
        <div class="meta">
          {f'<span class="pill">Created {html.escape(release_date)}</span>' if release_date else ''}
          <span class="pill">Theme: {html.escape(theme_name)}</span>
        </div>
        {f'<p>{html.escape(description)}</p>' if description else ''}
        {f'<p>{html.escape(artist_blurb)}</p>' if artist_blurb else ''}
        {download_markup}
        <div style="margin-top:18px;">{links_markup}</div>
      </div>
    </div>
    {f'<div class="section"><h3>Images</h3><div class="gallery">{gallery_markup}</div></div>' if gallery_markup else ''}
    {f'<div class="section"><h3>Artist Links</h3><div>{social_markup}</div></div>' if social_markup else ''}
  </div>
</body>
</html>"""


