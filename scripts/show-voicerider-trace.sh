#!/usr/bin/env bash
# scripts/show-voicerider-trace.sh — dump the last 60 seconds of the
# `com.voicerider:trace` category, formatted for grepping by tag.
#
# Each line in the trace category starts with a tag like `trace:hk-onarm`
# or `trace:overlay-show`; see Appendix A of
# docs/plans/20260517T1535-overlay-diagnosis-plan.md for the full catalog.
#
# Usage:
#   ./scripts/show-voicerider-trace.sh                # last 60s
#   ./scripts/show-voicerider-trace.sh 5m             # last 5 minutes
#   ./scripts/show-voicerider-trace.sh --stream       # live tail (Ctrl-C to stop)
#
# Notes:
# - Apple's `log show` requires a duration *or* an absolute start time.
#   This script defaults to a 60-second window because that is comfortably
#   longer than the press → overlay chain (worst case ~250ms).
# - Output is the raw `log show` formatting; the trace tags are stable
#   and grep-able. Pipe through `grep` if you only want one link.

set -euo pipefail

PRED='subsystem == "com.voicerider" AND category == "trace"'
LEVEL=debug

if [ "${1:-}" = "--stream" ]; then
    exec log stream --predicate "$PRED" --level "$LEVEL"
fi

DURATION="${1:-60s}"

# `log show` expects values like "60s", "5m", "1h" via `--last`.
exec log show \
    --predicate "$PRED" \
    --info \
    --debug \
    --last "$DURATION" \
    --style compact
