#!/usr/bin/env bash
# Back out what install.sh changed: strip the managed blocks from the Hyprland
# Lua config and stop the running dashboard. Leaves the clone and any installed
# packages in place.

set -euo pipefail

HYPR="$HOME/.config/hypr"
DEST="$HOME/.config/quickshell/dashboard"
BEGIN="-- >>> omarchy-dashboard (managed) >>>"
END="-- <<< omarchy-dashboard (managed) <<<"

say() { printf '\033[1;32m::\033[0m %s\n' "$*"; }

for file in "$HYPR/looknfeel.lua" "$HYPR/autostart.lua"; do
  [ -f "$file" ] || continue
  if grep -qF "$BEGIN" "$file"; then
    say "Removing managed block from $file"
    # delete the marker range, then squeeze runs of blank lines left behind
    awk -v b="$BEGIN" -v e="$END" '
      $0 == b { skip = 1 }
      !skip   { if ($0 == "" && prev == "") next; print; prev = $0 }
      $0 == e { skip = 0 }
    ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
  fi
done

if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi
pkill -f '(quickshell|qs) .*(-c dashboard|quickshell/dashboard)' 2>/dev/null || true

say "Done. The clone is still at $DEST - 'rm -rf $DEST' to remove it."
