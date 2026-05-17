#!/usr/bin/env bash
# scripts/render-info-plist.sh — render Resources/Info.plist from
# Resources/Info.plist.template, substituting __VOICERIDER_LAN_HOST__
# with the value of $VOICERIDER_LAN_HOST.
#
# Resolution order, lowest to highest precedence:
#   1. Default `localhost`
#   2. `.env.local` if it exists (sourced)
#   3. Any pre-existing $VOICERIDER_LAN_HOST in the calling shell
#
# Run from the repo root. Idempotent — safe to call before every build.

set -euo pipefail
cd "$(dirname "$0")/.."

TEMPLATE="Resources/Info.plist.template"
OUT="Resources/Info.plist"

[ -f "$TEMPLATE" ] || { echo "missing $TEMPLATE" >&2; exit 1; }

# 1. Default
: "${VOICERIDER_LAN_HOST:=localhost}"

# 2. .env.local — only override if the caller didn't already export
if [ -f .env.local ]; then
  # shellcheck disable=SC1091
  ENV_HOST=$(grep -E '^VOICERIDER_LAN_HOST=' .env.local | tail -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
  if [ -n "${ENV_HOST:-}" ] && [ -z "${VOICERIDER_LAN_HOST_FROM_SHELL:-}" ]; then
    VOICERIDER_LAN_HOST="$ENV_HOST"
  fi
fi

# Validate: alphanumerics, dots, dashes, slash for CIDR
if ! printf '%s' "$VOICERIDER_LAN_HOST" | grep -qE '^[A-Za-z0-9._/-]+$'; then
  echo "invalid VOICERIDER_LAN_HOST=$VOICERIDER_LAN_HOST" >&2
  exit 1
fi

# Substitute. Use a delimiter that can't appear in hostnames.
sed "s|__VOICERIDER_LAN_HOST__|${VOICERIDER_LAN_HOST}|g" "$TEMPLATE" > "$OUT"
echo "rendered $OUT (VOICERIDER_LAN_HOST=$VOICERIDER_LAN_HOST)"
