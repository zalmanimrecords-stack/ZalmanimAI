#!/usr/bin/env bash
# Generate DKIM key pair and print DNS TXT for mail._domainkey.<domain>
# Usage: ./scripts/generate-dkim-dns.sh zalmanim.com [selector]
set -euo pipefail

DOMAIN="${1:-}"
SELECTOR="${2:-mail}"
OUT_DIR="${3:-/etc/opendkim/keys/${DOMAIN}}"

if [[ -z "${DOMAIN}" ]]; then
  echo "Usage: $0 <domain> [selector] [output_dir]" >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
PRIV="${OUT_DIR}/${SELECTOR}.private"
PUB="${OUT_DIR}/${SELECTOR}.txt"

openssl genrsa -out "${PRIV}" 2048 2>/dev/null
chmod 600 "${PRIV}"
openssl rsa -in "${PRIV}" -pubout -outform PEM 2>/dev/null | \
  grep -v '^-' | tr -d '\n' > "${OUT_DIR}/${SELECTOR}.pub.raw"

PUB_B64="$(cat "${OUT_DIR}/${SELECTOR}.pub.raw")"
DNS_NAME="${SELECTOR}._domainkey.${DOMAIN}"

cat > "${PUB}" <<EOF
${SELECTOR}._domainkey	IN	TXT	( "v=DKIM1; h=sha256; k=rsa; p=${PUB_B64}" )
EOF

echo ""
echo "=== DKIM DNS (publish at your DNS host) ==="
echo "Name: ${DNS_NAME}"
echo "Type: TXT"
echo "Value:"
echo "v=DKIM1; h=sha256; k=rsa; p=${PUB_B64}"
echo ""
echo "Private key: ${PRIV}"
echo "OpenDKIM KeyTable entry example:"
echo "${DNS_NAME} ${DOMAIN}:${SELECTOR}:${PRIV}"
echo ""
echo "SigningDomain / Selector in opendkim.conf: ${DOMAIN} / ${SELECTOR}"
