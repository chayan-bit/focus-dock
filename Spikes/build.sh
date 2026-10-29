#!/usr/bin/env bash
# Builds libSpikeKit.dylib and, only if missing, assembles the ad-hoc signed FocusDockSpike.app.
# The app holds only the stable C loader, so rebuilding the dylib never changes its cdhash and
# TCC grants survive. Pass --rebuild-app to re-sign the app (this resets its TCC grants).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/build"
APP="$OUT/FocusDockSpike.app"
heavy() { if command -v mac-heavy >/dev/null 2>&1; then mac-heavy "$@"; else "$@"; fi; }

cd "$HERE"
heavy swift build -c release >&2
BIN="$(swift build -c release --show-bin-path)"
mkdir -p "$OUT"
cp "$BIN/libSpikeKit.dylib" "$OUT/libSpikeKit.dylib"
codesign --force --sign - --timestamp=none "$OUT/libSpikeKit.dylib" >&2

if [[ "${1:-}" == "--rebuild-app" ]]; then rm -rf "$APP"; fi
if [[ ! -d "$APP" ]]; then
  mkdir -p "$APP/Contents/MacOS"
  cp "$BIN/FocusDockSpike" "$APP/Contents/MacOS/FocusDockSpike"
  cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>FocusDockSpike</string>
	<key>CFBundleIdentifier</key><string>dev.focusdock.spike</string>
	<key>CFBundleName</key><string>FocusDockSpike</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
  plutil -lint "$APP/Contents/Info.plist" >&2
  codesign --force --sign - --timestamp=none "$APP" >&2
fi
codesign --verify --strict "$APP" >&2
codesign -dv "$APP" 2>&1 | grep -E 'CDHash|Identifier' >&2
echo "$APP"
