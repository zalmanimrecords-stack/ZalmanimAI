# VPS Deployment

Production runs on **Docker on the Hostinger VPS** (Docker Compose: API, worker, web/admin/artist, Postgres, Redis, nginx).

## 0. SSH access (Hostinger VPS)

Add this to your SSH config (`~/.ssh/config` on Linux/macOS, `C:\Users\<You>\.ssh\config` on Windows) so you can connect with `ssh hostinger-vps` using your SSH key:

```
Host hostinger-vps
  HostName 187.124.22.93
  User root
  Port 22
  IdentityFile ~/.ssh/hostinger_vps
```

**Host key (verify on first connect):** ED25519 `SHA256:v91yecPlAb8XD5s/GjBw7qnxjotqTxdMOLsJ+9gkzL8` for `187.124.22.93`.

Then connect with `ssh hostinger-vps`, or explicitly:

```bash
ssh -i ~/.ssh/hostinger_vps root@187.124.22.93
```

**Windows:** If you see "Bad owner or permissions on .ssh/config", only your user should own the file. Remove any other users (e.g. CodexSandboxUsers) from the file’s permissions and set owner to your account.

### Install your public key on the VPS (first login / key rotation)

The deploy scripts (`scripts/deploy-prod-remote.ps1`, `scripts/deploy-staging-remote.ps1`, `scripts/lmupdate.ps1`) resolve the VPS key via `scripts/Resolve-HostingerSshKey.ps1`: **`LMUPDATE_SSH_KEY`** if set and the file exists, else **`hostinger_vps`**, else **`hostinger_vps_codex`** under `%USERPROFILE%\.ssh\`. The VPS must have the matching **public** key in **`/root/.ssh/authorized_keys`**.

1. **Create a key pair locally** (skip if `hostinger_vps` already exists):

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/hostinger_vps -C "zalmanim-deploy"
   ```

   On Windows PowerShell you can use the same paths under `$env:USERPROFILE\.ssh\`.

2. **Copy your public key** (one line starting with `ssh-ed25519`):

   ```powershell
   Get-Content $env:USERPROFILE\.ssh\hostinger_vps.pub
   ```

3. **Put it on the server** (pick one):

   - **Hostinger hPanel:** VPS → SSH access → add your **public** key, or use the browser/KVM terminal as root.
   - **One-time password login:** If the host still allows `root` password login, run from your PC:

     ```bash
     type %USERPROFILE%\.ssh\hostinger_vps.pub | ssh root@187.124.22.93 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
     ```

     (On Windows Git Bash or WSL; or paste the line manually in `/root/.ssh/authorized_keys` in the panel terminal.)

4. **Verify key login** (no password prompt):

   ```bash
   ssh -i ~/.ssh/hostinger_vps root@187.124.22.93 "echo ok"
   ```

5. **Custom key path** for deploy scripts only:

   ```powershell
   $env:LMUPDATE_SSH_KEY = "C:\Users\You\.ssh\your_other_key"
   .\scripts\deploy-prod-remote.ps1
   ```

**Hostinger flat deploy dir (no git clone):** If production lives under `/docker/labelops-lm` with `docker-compose.yml` and `.env` only, use:

```powershell
$env:LMUPDATE_SSH_KEY = "$env:USERPROFILE\.ssh\hostinger_vps_codex"
$env:PROD_REPO_PATH = "/docker/labelops-lm"
$env:LMUPDATE_SKIP_GIT = "1"
$env:LMUPDATE_COMPOSE_FILE = "docker-compose.yml"
$env:LMUPDATE_ENV_FILE = ".env"
$env:LMUPDATE_REMOTE_SERVICES_BUILD = "web api artist-web"
$env:LMUPDATE_REMOTE_SERVICES_RESTART = "api artist-web web"
.\scripts\deploy-prod-remote.ps1
```

Adjust `LMUPDATE_REMOTE_*` if your compose service names differ (`docker compose config --services` on the VPS).

**Hostinger MCP:** In Cursor the server is `user-hostinger-mcp`. You can use it to list VPS, domains, DNS, etc. (e.g. ask to list domains or VPS).

---

This production bundle targets:

- `lm.zalmanim.com` for the Flutter admin app
- `artists.zalmanim.com` for the artist portal
- `lmapi.zalmanim.com` for the FastAPI backend

## 1. Prepare the repo

Copy the production env template and fill in real secrets:

```bash
cp deploy/.env.production.example deploy/.env.production
```

Required values before the first deploy:

- `POSTGRES_PASSWORD`
- `JWT_SECRET`
- `OAUTH_REDIRECT_BASE=https://lmapi.zalmanim.com/api/admin/social/callback`
- `OAUTH_SUCCESS_REDIRECT=https://lm.zalmanim.com`
- any SMTP / OAuth / Mailchimp / WordPress secrets you actually use

## 2. Point DNS

Create `A` records for both subdomains so they point to the VPS:

- `lm.zalmanim.com`
- `artists.zalmanim.com`
- `lmapi.zalmanim.com`

## 3. Deploy

From the project root on the VPS:

```bash
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d --build
```

What this does:

- builds the API image from `apps/server`
- builds the admin app and artist portal inside Docker with `API_BASE_URL`
- starts `postgres`, `redis`, `api`, `worker`, and `web`
- serves the admin app, artist portal, and reverse-proxies the API through nginx

When you deploy with `scripts/deploy-prod.sh` or `scripts/deploy-prod-remote.ps1`, the built images are tagged with **IMAGE_TAG** = date and time of the deploy (e.g. `2025-03-14-1530`). If `IMAGE_TAG` is not set, `latest` is used.

**API URL in the web build (`API_BASE_URL` / `ARTIST_API_BASE_URL`):** Production defaults use the **same host** as each app (`https://lm.zalmanim.com/` for admin, `https://artists.zalmanim.com/` for the portal) so the browser calls `https://…/api/…` and nginx proxies to the API. That avoids cross-origin calls to `lmapi.zalmanim.com`, which can break if CORS or routing is misconfigured. If your `deploy/.env.production` still sets `API_BASE_URL=https://lmapi.zalmanim.com/`, update it to match the example file and **rebuild the `web` image**.

**Health checks:** The Flutter client calls `GET /health` on the **same origin** as the API base (e.g. `https://lm.zalmanim.com/health`). Nginx must proxy that path to the API container (see `location = /health` in `deploy/nginx/default.conf`). Without it, `/health` would return the SPA shell and connection checks would fail.

## 4. Deploy latest updates to production

**If PROD doesn’t show your latest changes**, the VPS likely has old code or Docker used cached images. Do this on the VPS from the project root:

1. **Pull latest code** (so the next build uses it):

   ```bash
   git pull
   ```

2. **Rebuild and restart** (use `--no-cache` if you want to force a full rebuild and avoid stale cache):

   ```bash
   docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d --build
   ```

   To force rebuild of web/admin/artist without cache:

   ```bash
   docker compose --env-file deploy/.env.production -f docker-compose.prod.yml build --no-cache web api worker
   docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d
   ```

You can also use the script (run from repo root on the VPS):

```bash
./scripts/deploy-prod.sh
```

**From your local machine (Windows):** Run this from the repo root. It SSHs to `hostinger-vps`, pulls, and rebuilds. Requires SSH to work (see note above on .ssh/config permissions). Default repo path on the Hostinger VPS is `/root/labelops-lm`; override with `$env:PROD_REPO_PATH` if your clone lives elsewhere.

```powershell
.\scripts\deploy-prod-remote.ps1
```

## 5. Verify

Check container status:

```bash
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml ps
```

Useful logs:

```bash
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml logs -f api
docker compose --env-file deploy/.env.production -f docker-compose.prod.yml logs -f web
```

Then test:

- `http://lmapi.zalmanim.com/health`
- `http://lm.zalmanim.com`
- `http://artists.zalmanim.com`

## 5b. Local vs server: why the server shows an old version

If the server doesn’t show your latest changes, work through this:

1. **Push local commits**  
   The server runs `git pull` from the remote. If you didn’t push, the server can’t see your commits.
   ```bash
   git push origin master
   ```

2. **Run a full deploy**  
   After pushing, run the deploy so the server pulls and rebuilds:
   ```powershell
   .\scripts\deploy-prod-remote.ps1
   ```

3. **Compare commits**  
   - **Local (what you’re on):** `git log -1 --oneline`  
   - **What the server should have after pull:** same as `origin/master`, so run `git log origin/master -1 --oneline` locally.  
   - **On the VPS:** SSH in and run `cd /root/labelops-lm && git log -1 --oneline`. It should match `origin/master`.

4. **Force rebuild**  
   If the commit on the server is correct but the app still looks old, rebuild without cache:
   ```bash
   # On the VPS, in /root/labelops-lm
   docker compose --env-file deploy/.env.production -f docker-compose.prod.yml build --no-cache web api worker
   docker compose --env-file deploy/.env.production -f docker-compose.prod.yml up -d
   ```

5. **Browser cache**  
   Try a hard refresh (Ctrl+Shift+R) or an incognito window.

## 6. SSL

The included nginx config is HTTP-only so the stack can come up cleanly on first boot.
Once SSH is ready, add TLS on the VPS and switch both domains to HTTPS:

- `https://lm.zalmanim.com`
- `https://artists.zalmanim.com`
- `https://lmapi.zalmanim.com`

At that point, keep these values in `deploy/.env.production`:

- `API_BASE_URL=https://lmapi.zalmanim.com/`
- `OAUTH_REDIRECT_BASE=https://lmapi.zalmanim.com/api/admin/social/callback`
- `OAUTH_SUCCESS_REDIRECT=https://lm.zalmanim.com`
