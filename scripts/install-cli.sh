#!/usr/bin/env bash
# Installs a `focusdock` wrapper for `FocusDock.app/Contents/MacOS/FocusDock` into ~/.local/bin,
# only when that directory is on PATH; otherwise prints the command to use instead.
# Usage: scripts/install-cli.sh [path/to/FocusDock.app]   (default: build/FocusDock.app)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$(cd "$(dirname "${1:-$ROOT/build/FocusDock.app}")" && pwd)/$(basename "${1:-$ROOT/build/FocusDock.app}")"
BIN="$APP/Contents/MacOS/FocusDock"
DIR="$HOME/.local/bin"

[[ -x $BIN ]] || { echo "no FocusDock binary at $BIN; run scripts/build-app.sh first" >&2; exit 1; }

case ":$PATH:" in
  *":$DIR:"*) ;;
  *)
    echo "$DIR is not on PATH, so nothing was installed. Use:"
    echo "  \"$BIN\" theme list"
    exit 0
    ;;
esac

mkdir -p "$DIR"
cat >"$DIR/focusdock" <<WRAPPER
#!/bin/sh
# Installed by focus-dock/scripts/install-cli.sh
exec "$BIN" "\$@"
WRAPPER
chmod 755 "$DIR/focusdock"
echo "installed $DIR/focusdock -> $BIN"
