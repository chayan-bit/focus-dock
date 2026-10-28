#!/usr/bin/env bash
# Builds a release binary and assembles an ad-hoc signed build/FocusDock.app.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/FocusDock.app"

heavy() {
  if command -v mac-heavy >/dev/null 2>&1; then mac-heavy "$@"; else "$@"; fi
}

cd "$ROOT"
heavy swift build -c release --product FocusDock >&2
BIN="$(swift build -c release --show-bin-path)/FocusDock"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/FocusDock"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# Shipped themes and templates (docs/THEMES.md); backgrounds are synced separately.
mkdir -p "$APP/Contents/Resources"
cp -R "$ROOT/Themes" "$ROOT/Templates" "$APP/Contents/Resources/"
plutil -lint "$APP/Contents/Info.plist" >&2
codesign --force --sign - --timestamp=none "$APP" >&2
codesign --verify --strict "$APP" >&2

echo "$APP"
