#!/usr/bin/env bash
# scripts/render-resources.sh — rebuild Resources/AppIcon.icns and
# Resources/RecordingOverlay.pdf from the SVG sources in Resources/svg/.
#
# Requires:
#   - rsvg-convert  (brew install librsvg)
#   - iconutil      (preinstalled on macOS)
#
# Idempotent. Safe to re-run after editing an SVG.

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "✘ rsvg-convert not found. Install with:  brew install librsvg" >&2
  exit 1
fi
if ! command -v iconutil >/dev/null 2>&1; then
  echo "✘ iconutil not found (this should ship with macOS)." >&2
  exit 1
fi

SVG_ICON="Resources/svg/AppIcon.svg"
SVG_OVL="Resources/svg/RecordingOverlay.svg"
[ -f "$SVG_ICON" ] || { echo "missing $SVG_ICON" >&2; exit 1; }
[ -f "$SVG_OVL"  ] || { echo "missing $SVG_OVL"  >&2; exit 1; }

# ─────────────────────────────────────────────────────────────────────
# 1. AppIcon.icns
# ─────────────────────────────────────────────────────────────────────
# Apple's canonical iconset. Each PNG file is named so iconutil knows
# its size + retina factor.

ICONSET=$(mktemp -d)
trap 'rm -rf "$ICONSET"' EXIT

declare -a SIZES=(16 32 128 256 512)
for s in "${SIZES[@]}"; do
  rsvg-convert -w "$s"           -h "$s"           "$SVG_ICON" -o "$ICONSET/icon_${s}x${s}.png"
  rsvg-convert -w "$((s * 2))"   -h "$((s * 2))"   "$SVG_ICON" -o "$ICONSET/icon_${s}x${s}@2x.png"
done

# rename the temp dir to .iconset (iconutil is picky about the suffix)
mv "$ICONSET" "${ICONSET}.iconset"
ICONSET="${ICONSET}.iconset"
trap 'rm -rf "$ICONSET"' EXIT

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "✓ rendered Resources/AppIcon.icns ($(stat -f%z Resources/AppIcon.icns) bytes)"

# ─────────────────────────────────────────────────────────────────────
# 2. RecordingOverlay.pdf
# ─────────────────────────────────────────────────────────────────────
# PDF embeds the SVG as a vector path; NSImage handles PDF natively
# and rasterizes at any display scale without quality loss.
rsvg-convert -f pdf "$SVG_OVL" -o Resources/RecordingOverlay.pdf
echo "✓ rendered Resources/RecordingOverlay.pdf ($(stat -f%z Resources/RecordingOverlay.pdf) bytes)"
