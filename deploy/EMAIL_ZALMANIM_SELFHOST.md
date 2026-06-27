# Self-hosted email for zalmanim.com (VPS 187.124.22.93)

Mirror the `familyzone.online` pattern: outbound mail from the VPS, authenticated with SPF, DKIM, DMARC, and matching reverse DNS (PTR).

## Status (automated vs manual)

| Step | Status |
|------|--------|
| VPS PTR → `mail.zalmanim.com` | **Requested via Hostinger** (action `ipam_set_reverse`). Confirm in hPanel → VPS → IP → Reverse DNS after a few minutes. |
| `zalmanim.com` DNS on **Cloudflare** | **You add records** in Cloudflare Dashboard (see [Cloudflare setup](#cloudflare-setup) below). |
| Docker `mailserver` HELO hostname | Set in `docker-compose*.yml` as `HOSTNAME=mail.zalmanim.com`. |
| DKIM key | Generate on the VPS with `scripts/generate-dkim-dns.sh zalmanim.com` and publish the TXT record. |
| OpenDKIM signing on Postfix | **Manual on VPS** — the stock `boky/postfix` container relays mail but does **not** sign DKIM. See [DKIM signing](#dkim-signing-on-the-vps) below. |

## Cloudflare setup

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com) → **zalmanim.com** → **DNS** → **Records**.
2. Click **Add record** for each row below.
3. **Critical:** For the `mail` **A** record, set proxy status to **DNS only** (grey cloud). If the cloud is orange (proxied), mail and PTR alignment break.
4. Do **not** enable **Email Routing** for `@` if you want the VPS to send as `info@zalmanim.com` — routing can conflict with your MX/SPF story. (Receiving at Cloudflare is separate from outbound via VPS.)
5. If you already have a **TXT** record at `@` starting with `v=spf1`, **merge** into one SPF record or replace it — never publish two SPF records at `@`.
6. Long DKIM TXT values: paste the full string in **Content**; Cloudflare accepts one line. If the UI warns about length, use **TXT** type and the full `v=DKIM1; h=sha256; k=rsa; p=...` value from the generate script.

| Type | Name (Cloudflare) | Content | Proxy | TTL |
|------|-------------------|---------|-------|-----|
| A | `mail` | `187.124.22.93` | **DNS only** (grey) | Auto |
| MX | `@` | `mail.zalmanim.com` | — | Priority **10** |
| TXT | `@` | `v=spf1 mx a ip4:187.124.22.93 -all` | — | Auto |
| TXT | `mail._domainkey` | *(from `scripts/generate-dkim-dns.sh`)* | — | Auto |
| TXT | `_dmarc` | `v=DMARC1; p=none; rua=mailto:info@zalmanim.com; pct=100` | — | Auto |

Use `p=none` on DMARC for the first 1–2 weeks, then change to `p=quarantine` in Cloudflare when tests look good.

After saving, use **DNS** → **Records** → search `mail` and confirm the cloud icon is **grey** for `mail.zalmanim.com`.

Propagation is usually a few minutes on Cloudflare; use [DNS → Records → Check DNS records](https://dash.cloudflare.com) or:

```bash
dig @1.1.1.1 +short mail.zalmanim.com A
dig @1.1.1.1 +short zalmanim.com MX
```

## 1. DNS records (reference)

Same values as the Cloudflare table above. Replace the DKIM `p=` value with output from the generate script.

| Type | Name | Value | Notes |
|------|------|-------|--------|
| **A** | `mail` | `187.124.22.93` | Must exist **before** PTR is valid. |
| **MX** | `@` | `10 mail.zalmanim.com.` | Priority 10; trailing dot optional depending on UI. |
| **TXT** | `@` | `v=spf1 mx a ip4:187.124.22.93 -all` | One SPF record only. |
| **TXT** | `mail._domainkey` | `v=DKIM1; h=sha256; k=rsa; p=<YOUR_PUBLIC_KEY>` | From `scripts/generate-dkim-dns.sh`. |
| **TXT** | `_dmarc` | `v=DMARC1; p=quarantine; sp=quarantine; adkim=s; aspf=s; pct=100; rua=mailto:info@zalmanim.com` | Start with `p=none` for the first 2 weeks if you prefer monitoring only. |

Keep existing **A** records for `lm`, `artists`, `lmapi`, etc. unchanged.

### Verify DNS (after propagation)

```bash
dig +short mail.zalmanim.com A
dig +short zalmanim.com MX
dig +short zalmanim.com TXT
dig +short mail._domainkey.zalmanim.com TXT
dig +short _dmarc.zalmanim.com TXT
dig +short -x 187.124.22.93
```

Expected PTR: `mail.zalmanim.com.`

Online checks: [MXToolbox](https://mxtoolbox.com/SuperTool.aspx?domain=zalmanim.com), [mail-tester.com](https://www.mail-tester.com/) (send a test from Admin → Mail settings).

## 2. Application SMTP (LabelOps)

Production already uses the internal Docker relay:

```env
SMTP_HOST=mailserver
SMTP_PORT=25
SMTP_USE_TLS=false
SMTP_USE_SSL=false
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=info@zalmanim.com
MAILSERVER_ALLOWED_SENDER_DOMAINS=zalmanim.com
EMAILS_PER_HOUR=30
```

No change required if the stack runs on the VPS with the `mailserver` service. After DNS + DKIM are live, send a test from **Settings → Mail settings**.

### Incoming email → admin Inbox (IMAP ingestion)

Mail addressed to the label (MX → `mail.familyzone.online`, the docker-mailserver on the VPS) can be
surfaced in the admin **Inbox** tab, tagged **Email** alongside artist portal messages. The worker
polls the mailbox over IMAP (read-only — it never deletes server mail) and stores each new message,
deduplicated by RFC `Message-ID`.

1. Create the mailbox on docker-mailserver:
   ```bash
   docker exec -ti mailserver setup email add simon@zalmanim.com
   ```
2. Set in `deploy/.env.production` (the worker reads these via `env_file`):
   ```env
   IMAP_HOST=mail.familyzone.online
   IMAP_PORT=993
   IMAP_USE_SSL=true
   IMAP_USER=simon@zalmanim.com
   IMAP_PASSWORD=<the mailbox password>
   IMAP_MAILBOX=INBOX
   IMAP_POLL_SECONDS=120
   ```
   Leave `IMAP_HOST` empty to disable ingestion. Restart the `worker` service to apply.

## 3. DKIM signing on the VPS

The `boky/postfix` container sends mail but does **not** add DKIM signatures. Receivers often treat unsigned mail as spam when SPF/DMARC are strict.

**Option A — Host-level OpenDKIM (recommended, same idea as familyzone)**

On the VPS (as root), install and configure OpenDKIM for `zalmanim.com`, then either:

- Point the app at host Postfix (`SMTP_HOST=host.docker.internal` or the host IP, port 587), or  
- Configure the Docker mail relay to use the host as `RELAYHOST` (advanced).

**Option B — Keep Docker relay only (quick, weaker deliverability)**

Publish SPF + DMARC and PTR only. Accept higher spam risk until DKIM signing is added.

Use the generate script for the **DNS** side; wire the **private** key into OpenDKIM on the host:

```bash
cd /docker/labelops-lm   # or your deploy path
bash scripts/generate-dkim-dns.sh zalmanim.com
# Follow printed steps for /etc/opendkim and Postfix milter
```

## 4. Deliverability rules

- Warm up volume: stay within `EMAILS_PER_HOUR` (default 30); increase slowly.
- Use `info@zalmanim.com` for transactional mail; use `news@zalmanim.com` for campaigns when you add the native email channel.
- Only send to `subscribed` audience members with consent metadata.
- Ensure the global email footer (Settings → Email templates) includes a physical address for CAN-SPAM.

## 5. Hostinger vs Cloudflare

- **PTR** is on Hostinger (VPS IP) — already `mail.zalmanim.com`.
- **Forward DNS** (A/MX/TXT) stays on **Cloudflare** while nameservers point to Cloudflare.
- Moving the zone to Hostinger is optional; not required if Cloudflare works for you.
