# WordPress + Zalmanim Artists Plugin (Docker)

This runs WordPress in Docker with the **Zalmanim Artists** plugin pre-mounted. Suitable for running on the Hostinger VPS alongside the main stack (API, web, artist portal).

## Prerequisites

- Docker and Docker Compose on the server (Hostinger VPS already has these for the main stack).
- This repo (or at least `deploy/wordpress/`, `wordpress-plugin/zalmanim-artists/`) on the server.

## 1. Create env file on the server

On the VPS (e.g. after SSH):

```bash
cd /root/ZalmanimAI   # or your repo path

cp deploy/wordpress/.env.example deploy/wordpress/.env
nano deploy/wordpress/.env   # set WORDPRESS_DB_PASSWORD and WORDPRESS_DB_ROOT_PASSWORD (and WORDPRESS_HOME_URL if you use a domain)
```

Use strong random passwords. If WordPress will be at `https://wp.zalmanim.com`, set:

```env
WORDPRESS_HOME_URL=https://wp.zalmanim.com
```

## 2. Start WordPress

From the **repo root** on the VPS:

```bash
docker compose -f deploy/wordpress/docker-compose.yml --project-directory . --env-file deploy/wordpress/.env up -d
```

- WordPress listens on **port 8080** (so it does not conflict with the main stack on port 80).
- The **Zalmanim Artists** plugin is mounted from `wordpress-plugin/zalmanim-artists` and is already in `wp-content/plugins/zalmanim-artists`.

## 3. Open WordPress and finish setup

1. In the browser open: `http://YOUR_VPS_IP:8080` (or your domain if you already pointed it and proxied to 8080).
2. Complete the WordPress installation (language, site title, admin user, password).
3. Go to **Plugins** and **Activate** “Zalmanim Artists”.
4. Go to **Settings → Zalmanim Artists** and set:
   - **API base URL**: e.g. `https://lmapi.zalmanim.com`
   - Optionally: Public Linktree base URL, Artist portal URL, Demo submission token.

## 4. (Optional) Serve WordPress on a domain (e.g. wp.zalmanim.com)

- **Option A – Reverse proxy on the same VPS**  
  Add a server block in the main nginx (or a separate proxy) so that `wp.zalmanim.com` proxies to `http://127.0.0.1:8080`. Then set `WORDPRESS_HOME_URL=https://wp.zalmanim.com` in `deploy/wordpress/.env` and restart WordPress.

- **Option B – Direct access**  
  Point a subdomain A record to the VPS and access `http://wp.zalmanim.com:8080`, or use a cloud proxy (e.g. Cloudflare) to forward `wp.zalmanim.com` to `http://VPS_IP:8080`.

## 5. Useful commands

From repo root:

```bash
# Stop WordPress
docker compose -f deploy/wordpress/docker-compose.yml --project-directory . --env-file deploy/wordpress/.env down

# View logs
docker compose -f deploy/wordpress/docker-compose.yml --project-directory . --env-file deploy/wordpress/.env logs -f wordpress

# Restart after plugin or .env change
docker compose -f deploy/wordpress/docker-compose.yml --project-directory . --env-file deploy/wordpress/.env up -d
```

## Hostinger VPS quick reference

1. SSH: `ssh hostinger-vps` (see `deploy/DEPLOY_VPS.md` for SSH config).
2. Go to repo: `cd /root/ZalmanimAI` (or your path).
3. Pull latest: `git pull` (if you deploy from git).
4. Create/copy `deploy/wordpress/.env` from `.env.example` and set passwords.
5. Run the `docker compose ... up -d` command from section 2 above.

The plugin is mounted from the repo, so after `git pull` you get the latest plugin code without rebuilding the image.
