# VPS Deployment

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

## 4. Verify

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

## 5. SSL

The included nginx config is HTTP-only so the stack can come up cleanly on first boot.
Once SSH is ready, add TLS on the VPS and switch both domains to HTTPS:

- `https://lm.zalmanim.com`
- `https://artists.zalmanim.com`
- `https://lmapi.zalmanim.com`

At that point, keep these values in `deploy/.env.production`:

- `API_BASE_URL=https://lmapi.zalmanim.com/`
- `OAUTH_REDIRECT_BASE=https://lmapi.zalmanim.com/api/admin/social/callback`
- `OAUTH_SUCCESS_REDIRECT=https://lm.zalmanim.com`
