#!/usr/bin/env bash
# Runs the tests with code coverage and fails when FocusDockCore's line coverage is below the
# minimum. CI runs this same script.
# Usage: scripts/coverage.sh [minimum-percent]   (default: 80)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIMUM="${1:-80}"

heavy() {
  if command -v mac-heavy >/dev/null 2>&1; then mac-heavy "$@"; else "$@"; fi
}

cd "$ROOT"
heavy swift build --build-tests --enable-code-coverage
# Pool width 1: a test that blocks a cooperative thread hangs here and in CI alike.
heavy env LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --skip-build --enable-code-coverage

BIN="$(swift build --show-bin-path)"
REPORT="$(xcrun llvm-cov report "$BIN/FocusDockCoreTests.xctest/Contents/MacOS/FocusDockCoreTests" \
  -instr-profile "$BIN/codecov/default.profdata" "$ROOT/Sources/FocusDockCore")"
echo "$REPORT"

# The TOTAL row's line coverage, the tenth column ("95.70%").
LINES="$(awk '$1 == "TOTAL" { sub("%", "", $10); print $10 }' <<<"$REPORT")"
[[ -n $LINES ]] || { echo "no TOTAL row in the llvm-cov report" >&2; exit 1; }
if awk -v lines="$LINES" -v minimum="$MINIMUM" 'BEGIN { exit !(lines < minimum) }'; then
  echo "FocusDockCore line coverage ${LINES}% is below ${MINIMUM}%" >&2
  exit 1
fi
echo "FocusDockCore line coverage ${LINES}% (minimum ${MINIMUM}%)"
