# Zalmanim Artists – WordPress Plugin

Displays artists (with Linktree links), label releases list, and the demo submission form. Data is fetched from the Zalmanim backend API.

## Requirements

- WordPress 5.9+
- PHP 7.4+
- Zalmanim API with public endpoints:
  - `GET /public/artists-with-releases`
  - `GET /public/releases`
  - `POST /public/demo-submissions` (for embedded demo form)

## Installation

1. Copy the `zalmanim-artists` folder into `wp-content/plugins/`.
2. In WordPress admin go to **Plugins** and activate **Zalmanim Artists**.
3. Go to **Settings → Zalmanim Artists** and set:
   - **API base URL**: e.g. `https://api.zalmanim.com` (no trailing slash).
   - **Public Linktree base URL** (optional): e.g. `https://artists.zalmanim.com/linktree` – used when an artist has no Linktree URL.
   - **Artist portal URL** (optional): e.g. `https://artists.zalmanim.com` – used to embed the full demo form (with file upload) in an iframe.
   - **Demo submission token** (optional): if the API requires it for demo submissions (`x-demo-token` header).

## Shortcodes

### [zalmanim_artists]

List of artists who have released tracks, with links to their Linktree (or profile).

- `list_style`: `ul` (default), `ol`, or `comma`
- `class`: extra CSS class

Examples: `[zalmanim_artists]` — `[zalmanim_artists list_style="ol"]`

### [zalmanim_releases]

List of label releases (title and artist names).

- `list_style`: `ul` (default), `ol`, or `comma`
- `show_artists`: `1` (default) or `0`
- `class`: extra CSS class

Examples: `[zalmanim_releases]` — `[zalmanim_releases list_style="comma" show_artists="0"]`

### [zalmanim_demo_form]

Demo submission form from the portal.

- If **Artist portal URL** is set: embeds the portal in an **iframe** (full form with MP3 upload).
- Otherwise: shows an **embedded form** that submits to the API (artist name, email, track links, message; no file upload). Set **Demo submission token** if the API requires it.

- `mode`: `iframe` or `form` to force one mode
- `height`: iframe height in px (default 600)
- `class`: extra CSS class

Examples: `[zalmanim_demo_form]` — `[zalmanim_demo_form mode="iframe" height="700"]`

## Caching

Artists and releases data is cached for 15 minutes. Use **Clear cache** on the settings page to refresh.

## API

The plugin uses:

- `GET {api_base}/public/artists-with-releases?limit=500` — artists with optional `linktree_url`
- `GET {api_base}/public/releases?limit=200` — releases with `id`, `title`, `artist_names`, `created_at`
- `POST {api_base}/public/demo-submissions` — JSON body; optional header `x-demo-token`
