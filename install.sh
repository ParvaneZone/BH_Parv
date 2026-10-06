#!/usr/bin/env bash
set -eo pipefail

# Pin a tag/commit with BH_REF (e.g. BH_REF=v0.7.4-parv1); defaults to main.
REF="${BH_REF:-main}"
[[ $REF =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "Invalid BH_REF." >&2; exit 1; }
REPO_RAW="https://raw.githubusercontent.com/ParvaneZone/BH_Parv/${REF}/backhaul-manager.sh"
DEST="/usr/local/bin/ParvBH"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

# Prepare the minimum needed to download the manager (the manager installs the rest itself).
if ! command -v curl >/dev/null 2>&1; then
  echo "curl not found, installing..."
  if   command -v apt-get >/dev/null 2>&1; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates
  elif command -v dnf     >/dev/null 2>&1; then dnf install -y -q curl ca-certificates
  elif command -v yum     >/dev/null 2>&1; then yum install -y -q curl ca-certificates
  elif command -v apk     >/dev/null 2>&1; then apk add --quiet curl ca-certificates
  else echo "Please install curl manually." >&2; exit 1
  fi
fi

TMP="$(mktemp)"
curl -fsSL --proto '=https' --tlsv1.2 "$REPO_RAW" -o "$TMP"
bash -n "$TMP" || { echo "Downloaded manager failed a syntax check; aborting." >&2; rm -f "$TMP"; exit 1; }
echo "Manager SHA-256: $(sha256sum "$TMP" | awk '{print $1}')"
install -m 755 "$TMP" "$DEST"
rm -f "$TMP"

echo "Installed. From anywhere on this server, run: ParvBH"
exec "$DEST"
