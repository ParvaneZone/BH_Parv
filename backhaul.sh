#!/usr/bin/env bash
# DEPRECATED: the old installer pulled the upstream (Musixal) binary.
# Kept only so old links keep working; it now opens the ParvBH manager.
if command -v ParvBH >/dev/null 2>&1; then exec ParvBH; fi
exec bash -c "$(curl -fsSL --proto '=https' --tlsv1.2 https://raw.githubusercontent.com/ParvaneZone/BH_Parv/main/install.sh)"
