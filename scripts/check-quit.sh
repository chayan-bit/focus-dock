#!/usr/bin/env bash
# Checks that a `.terminateLater` quit cannot deadlock: builds scripts/quit-harness with the app's
# MainRunLoop.swift and quits it from a main-queue block, a main-actor task, and with a stuck
# replay. Needs a login session (it runs an NSApplication with no windows); touches no settings.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/.build/quit-harness"
mkdir -p "$(dirname "$OUT")"
xcrun swiftc -swift-version 6 -o "$OUT" "$ROOT/scripts/quit-harness/main.swift" "$ROOT/Sources/FocusDock/MainRunLoop.swift"

"$OUT" signal | grep -q "reply from replay"
"$OUT" task | grep -q "reply from replay"
"$OUT" stuck | grep -q "reply from timeout"
echo "quit harness: signal, task and stuck quits all replied"
