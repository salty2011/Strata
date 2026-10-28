#!/bin/sh
# Upstream strata-dsv41 on the LAN (production): 0.0.0.0:8150, API key from ~/.config/ds41e/api-key (600, never
# printed), model id "local" accepted (config alias), web chat at /. Config: prod.json beside this script (engine args,
# lookup drafts, slot folder, log). Use restart-lan.sh (under the GPU lock) or ~/bin/ds-switch rather than this directly.
H="$(cd "$(dirname "$0")" && pwd)"
UP="$(dirname "$H")"
STRATA_API_KEY=$(cat "$HOME/.config/ds41e/api-key") || exit 1
export STRATA_API_KEY
cd "$UP" || exit 1
exec "$UP/.venv/bin/python" "$UP/serve/server.py" --engine strata --config "$H/prod.json" --host 0.0.0.0 --port 8150
