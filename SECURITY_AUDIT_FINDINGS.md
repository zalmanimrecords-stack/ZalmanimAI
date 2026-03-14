# Security Audit – Hardcoded Passwords & Secrets

**Date:** 2025-03-14  
**Scope:** Passwords and secrets stored in code (not in `.env` or env-only config).

---

## Summary

| Location | Type | Value / Risk | Recommended action |
|----------|------|--------------|--------------------|
| **1** | Backend seed/migration | Plaintext passwords in `routes.py` | Remove or move to env; use empty/random for seed |
| **2** | Docker Compose (dev) | Postgres, Minio, JWT | Replace with env vars or placeholders |
| **3** | Server config defaults | JWT secret, DB URL, demo token | Require env in prod; keep safe dev defaults |
| **4** | README | Demo credentials in docs | Remove or replace with “set via env” |
| **5** | Prod compose | Default `DEMO_SUBMISSION_TOKEN` | Require env (no default “TOKEN”) |

---

## 1. Backend seed/migration – **apps/server/app/api/routes.py**

**Lines ~832–900** (seed/migration block):

| Purpose | Email / user | Hardcoded password |
|---------|--------------|---------------------|
| Demo artist | `artist@label.local` | `artist123` |
| Admin (legacy/new) | `admin` / `admin@label.local` | `Zalmanim102030` |
| Simon admin | `simon@zalmanim.com` | `Sr102030!` |
| Artist user | `artist@label.local` | `artist123` |

**Risk:** High. Anyone with repo access sees real-looking admin/artist passwords. If these accounts exist in prod, they are guessable.

**Recommended change:**  
- Stop setting passwords in code. Either:  
  - Read initial passwords from env (e.g. `SEED_ADMIN_PASSWORD`, `SEED_ARTIST_PASSWORD`) and only set if provided, or  
  - Only create users without setting password (force “set password” on first login), or  
  - Use a single shared env var e.g. `SEED_DEMO_PASSWORD` for all seed users, empty = skip seed password set.

---

## 2. Docker Compose (development) – **docker-compose.yml**

| Service | Variable | Hardcoded value |
|---------|----------|-----------------|
| postgres | `POSTGRES_PASSWORD` | `label` |
| postgres | (in api/worker) | `DATABASE_URL` contains `label:label@postgres` |
| minio | `MINIO_ROOT_PASSWORD` | `miniopassword` |
| api, worker | `JWT_SECRET` | `change-me-in-prod` |

**Risk:** Medium for dev (expected). High if this file is ever used in prod without override.

**Recommended change:**  
- Use env vars with safe dev defaults, e.g.  
  `POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-label}`  
  `JWT_SECRET: ${JWT_SECRET:-change-me-in-prod}`  
- Add a comment: “Override in production; never commit real secrets.”

---

## 3. Server config defaults – **apps/server/app/core/config.py**

| Setting | Default value |
|---------|----------------|
| `jwt_secret` | `"change-me"` |
| `database_url` | `postgresql+psycopg2://label:label@postgres:5432/labelops` |
| `demo_submission_token` | `"TOKEN"` |

**Risk:** High in production if env is not set (predictable JWT and demo token).

**Recommended change:**  
- In production, fail startup if `jwt_secret == "change-me"` (or if not set).  
- Keep defaults for local dev only; document that prod must set env.  
- `demo_submission_token`: no default in prod (require env or leave empty to disable).

---

## 4. README – **README.md**

**Lines 51–52:**  
- Admin: `admin@label.local` / `admin123`  
- Artist: `artist@label.local` / `artist123`

**Risk:** Medium. Documents default credentials; should not be in repo if you remove seed passwords.

**Recommended change:**  
- Remove the exact passwords. Replace with: “Seed users are created on first run; set initial passwords via env (see deploy docs) or change after first login.”

---

## 5. Production Docker Compose – **docker-compose.prod.yml**

**Lines 35, 76:**  
- `DEMO_SUBMISSION_TOKEN: ${DEMO_SUBMISSION_TOKEN:-TOKEN}`  
- Build arg `DEMO_SUBMISSION_TOKEN: ${DEMO_SUBMISSION_TOKEN:-TOKEN}`

**Risk:** Medium. Default `TOKEN` is guessable; if used in prod, demo endpoint is unprotected.

**Recommended change:**  
- No default in prod: use `DEMO_SUBMISSION_TOKEN: ${DEMO_SUBMISSION_TOKEN:?set DEMO_SUBMISSION_TOKEN}` or leave unset to disable.

---

## 6. Other files (no change needed for “passwords in code”)

- **SECURITY_REVIEW.md** – Describes the risk of pre-filled credentials; **apps/client** login page no longer pre-fills email/password (controllers are empty). No deletion needed; optional: update SECURITY_REVIEW to “fixed” for that item.
- **tmp_users.sql** / **reports/db_sync/prod-backup-...** – Contain hashes/emails from DB; not “passwords in code”. Prefer not committing real backups; if they stay, ensure they’re in `.gitignore`.

---

## Next step

Reply with which of the following you want applied (you can say “all” or list numbers):

1. **Backend seed passwords** – Remove hardcoded passwords from `routes.py` (use env or “no default password”).
2. **docker-compose.yml** – Replace hardcoded Postgres/Minio/JWT with env vars (with dev defaults).
3. **config.py** – Add prod check for default `jwt_secret` and/or remove default `demo_submission_token`.
4. **README.md** – Remove explicit seed passwords from docs.
5. **docker-compose.prod.yml** – Require `DEMO_SUBMISSION_TOKEN` in prod (no default `TOKEN`).

After you confirm, the changes can be applied step by step.
