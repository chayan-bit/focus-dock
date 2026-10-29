#!/usr/bin/env bash
# Runs one spike test through LaunchServices, so TCC attributes it to FocusDockSpike.app
# (not to the calling terminal). Usage: run.sh <test> <evidence-dir> [key=value...]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST="$1"; EVID="$2"; shift 2
mkdir -p "$EVID"; : > "$EVID/$TEST.stdout"; : > "$EVID/$TEST.stderr"
open -W -n --stdout "$EVID/$TEST.stdout" --stderr "$EVID/$TEST.stderr" "$HERE/build/FocusDockSpike.app" \
  --args "$TEST" --out "$EVID/results.jsonl" --evidence "$EVID" "$@"
cat "$EVID/$TEST.stdout"
