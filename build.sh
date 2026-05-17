#!/usr/bin/env bash
# build.sh — fast development iteration. Compiles in debug mode, runs the
# unit tests. No .app bundle, no codesign. Use this while iterating on
# code; use ./prod-build.sh when you want something to launch.
#
# Usage:
#   ./build.sh           # compile + test
#   ./build.sh test      # only run tests
#   ./build.sh strict    # release build with -strict-concurrency=complete
#                          (informational; emits warnings under macOS 13
#                          AVFoundation imports — see steering rules)

set -euo pipefail
cd "$(dirname "$0")"

case "${1:-all}" in
  test)
    echo "==> Tests only"
    VOICERIDER_RUN_AUDIO_TESTS=0 swift test
    ;;

  strict)
    echo "==> Strict-concurrency build (informational)"
    LOG=$(mktemp)
    trap 'rm -f "$LOG"' EXIT
    swift build -c release -Xswiftc -strict-concurrency=complete 2>&1 | tee "$LOG"
    COUNT=$(grep -cE '^(.*: )?warning:' "$LOG" || true)
    echo
    echo "strict: $COUNT warning(s) under -strict-concurrency=complete"
    echo "(this is informational, not a release gate — see voice-project.md)"
    ;;

  all|"")
    echo "==> Debug build"
    swift build
    echo
    echo "==> Tests"
    VOICERIDER_RUN_AUDIO_TESTS=0 swift test
    echo
    echo "build.sh: OK — produce a runnable .app with ./prod-build.sh"
    ;;

  *)
    echo "usage: $0 [all|test|strict]" >&2
    exit 2
    ;;
esac
