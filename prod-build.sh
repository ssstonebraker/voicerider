#!/usr/bin/env bash
# prod-build.sh — produce a runnable VoiceRider.app from scratch.
#   1. release-mode compile
#   2. zero-warning gate (refuses to package if any warning surfaced)
#   3. full test run with VOICERIDER_RUN_AUDIO_TESTS=0
#   4. assemble .app bundle layout
#   5. ad-hoc codesign with the canonical bundle id
#
# Usage:
#   ./prod-build.sh                 # build + test + bundle
#   ./prod-build.sh --skip-tests    # skip the test step (faster)
#   ./prod-build.sh --install       # also `mv VoiceRider.app /Applications/`

set -euo pipefail
cd "$(dirname "$0")"

APP="VoiceRider.app"
BIN=".build/release/VoiceRider"
BUNDLE_ID="com.voicerider"
SKIP_TESTS=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --skip-tests) SKIP_TESTS=1 ;;
    --install)    INSTALL=1 ;;
    -h|--help)
      sed -n '2,15p' "$0"; exit 0 ;;
    *)
      echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# 0. Render Resources/Info.plist from the template + .env.local
#    (gitignored so your LAN host doesn't leak into commits).
echo "==> Rendering Resources/Info.plist"
./scripts/render-info-plist.sh

# 1. Release build with zero-warning gate.
echo "==> Release build"
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
swift build -c release 2>&1 | tee "$LOG"
if grep -E '^(.*: )?warning:' "$LOG" >/dev/null; then
  echo
  echo "✘ Release build emitted warnings — refusing to package."
  echo "  Fix the warnings above (or escalate to a steering-rule change)"
  echo "  before re-running prod-build.sh."
  exit 1
fi

# 2. Tests.
if [ "$SKIP_TESTS" -eq 0 ]; then
  echo
  echo "==> Tests"
  VOICERIDER_RUN_AUDIO_TESTS=0 swift test
fi

# 3. Bundle layout.
echo
echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/VoiceRider"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Copy bundled assets. Each is regenerated from SVG sources by
# scripts/render-resources.sh; both committed as binary artifacts so
# fresh clones work without librsvg installed.
for asset in AppIcon.icns RecordingOverlay.pdf; do
  if [ -f "Resources/$asset" ]; then
    cp "Resources/$asset" "$APP/Contents/Resources/"
  else
    echo "✘ Missing Resources/$asset (run ./scripts/render-resources.sh)" >&2
    exit 1
  fi
done

# 4. Ad-hoc codesign with the canonical bundle id. TCC pins permissions
# to bundle id + signature + path; keeping --identifier stable across
# rebuilds means users don't re-grant after each `prod-build.sh`.
echo
echo "==> Ad-hoc codesign (identifier=$BUNDLE_ID)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"

# 5. Optional install to /Applications.
if [ "$INSTALL" -eq 1 ]; then
  echo
  echo "==> Installing to /Applications/$APP"
  rm -rf "/Applications/$APP"
  cp -R "$APP" "/Applications/$APP"
  echo "Installed."
fi

echo
echo "✓ Built $APP (id=$BUNDLE_ID)"
echo "  Run with:  open $APP"
if [ "$INSTALL" -eq 0 ]; then
  echo "  Install:   ./prod-build.sh --install   (or: mv $APP /Applications/)"
fi
