#!/usr/bin/env bash
set -e

REPO_RAW="https://raw.githubusercontent.com/ParvaneZone/BH_Parv/main/backhaul-manager.sh"
DEST="/usr/local/bin/ParvBH"

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo)." >&2
  exit 1
fi

command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }

curl -fsSL "$REPO_RAW" -o "$DEST"
chmod +x "$DEST"

echo "Installed. From anywhere on this server, run: ParvBH"
exec "$DEST"
