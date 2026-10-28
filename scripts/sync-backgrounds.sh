#!/usr/bin/env bash
# Downloads the shipped themes' background images from the pinned Omarchy commit into
# ~/.local/share/focusdock/themes/<name>/backgrounds/, checking each against
# Themes/backgrounds.sha256. They are about 69 MB, so they never enter this repo.
# Usage: scripts/sync-backgrounds.sh [theme ...]   (no arguments: every theme)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT="$(sed -n 's/^Commit: *//p' "$ROOT/THIRD_PARTY.md" | head -n 1)"
MANIFEST="$ROOT/Themes/backgrounds.sha256"
DEST="${FOCUSDOCK_BACKGROUNDS:-$HOME/.local/share/focusdock/themes}"
BASE="https://raw.githubusercontent.com/basecamp/omarchy/$COMMIT/themes"

[[ $COMMIT =~ ^[0-9a-f]{40}$ ]] || { echo "no pinned commit in THIRD_PARTY.md" >&2; exit 1; }

wanted() {
  local theme="$1" name
  (( ${#THEMES[@]} == 0 )) && return 0
  for name in "${THEMES[@]+"${THEMES[@]}"}"; do [[ $name == "$theme" ]] && return 0; done
  return 1
}

THEMES=("$@")
fetched=0 kept=0 failed=0
while read -r sum path; do
  theme="${path%%/*}"
  wanted "$theme" || continue
  target="$DEST/$path"
  if [[ -f $target ]] && [[ $(shasum -a 256 "$target" | cut -d' ' -f1) == "$sum" ]]; then
    kept=$((kept + 1))
    continue
  fi
  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp "$target.XXXXXX")"
  if curl -fsSL --retry 2 -o "$tmp" "$BASE/$path" && [[ $(shasum -a 256 "$tmp" | cut -d' ' -f1) == "$sum" ]]; then
    chmod 644 "$tmp"
    mv "$tmp" "$target"
    fetched=$((fetched + 1))
  else
    rm -f "$tmp"
    echo "failed: $path (download or checksum)" >&2
    failed=$((failed + 1))
  fi
done <"$MANIFEST"

echo "backgrounds in $DEST: $fetched downloaded, $kept already present, $failed failed"
(( failed == 0 ))
