#!/usr/bin/env bash
# omarchy-dashboard installer.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/D3m0nZOnFire/omarchy-dashboard/main/install.sh)
#
# Clones (or updates) the dashboard, installs its dependencies, turns on the
# frosted-glass blur, and wires it into Hyprland's autostart. Safe to re-run.
# Targets Omarchy's Lua hypr config; for vanilla Hyprland see the README's
# "Manual setup" section. Back it out with ./uninstall.sh.
#
# Test a non-main branch:
#   BRANCH=dev bash <(curl -fsSL https://raw.githubusercontent.com/D3m0nZOnFire/omarchy-dashboard/dev/install.sh)

set -euo pipefail

REPO_URL="https://github.com/D3m0nZOnFire/omarchy-dashboard"
BRANCH="${BRANCH:-main}"
DEST="$HOME/.config/quickshell/dashboard"
HYPR="$HOME/.config/hypr"
LOOKNFEEL="$HYPR/looknfeel.lua"
AUTOSTART="$HYPR/autostart.lua"
NS="quickshell:dashboard"
BEGIN="-- >>> omarchy-dashboard (managed) >>>"
END="-- <<< omarchy-dashboard (managed) <<<"

say()  { printf '\033[1;32m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# --- a. preflight -----------------------------------------------------------
command -v pacman >/dev/null || die "This installer is for Arch/Omarchy (no pacman found)."
[ -f "$LOOKNFEEL" ] && [ -f "$AUTOSTART" ] || die \
  "Expected $LOOKNFEEL and $AUTOSTART (Omarchy Lua config). See the README's Manual setup section."

# --- b. clone / update -----------------------------------------------------
if [ -e "$DEST/.git" ] && git -C "$DEST" remote get-url origin 2>/dev/null | grep -q 'omarchy-dashboard'; then
  cur="$(git -C "$DEST" symbolic-ref --short -q HEAD || echo '')"
  if [ "$cur" = "$BRANCH" ]; then
    say "Updating $DEST ($cur)"
    git -C "$DEST" pull --ff-only origin "$cur" || warn "Could not fast-forward $cur - update manually."
  else
    warn "$DEST is on branch '$cur' (expected '$BRANCH') - leaving it as-is."
  fi
elif [ -e "$DEST" ]; then
  die "$DEST already exists and is not an omarchy-dashboard checkout. Move it aside and re-run."
else
  say "Cloning into $DEST ($BRANCH)"
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$DEST"
fi

# --- c. dependencies -----------------------------------------------------
missing=()
for pkg in qt6-5compat lm_sensors inotify-tools; do
  pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if ! command -v qs >/dev/null && ! command -v quickshell >/dev/null; then
  missing+=(quickshell-git)
fi
if { [ -d /proc/driver/nvidia ] || lspci 2>/dev/null | grep -qi 'vga.*nvidia'; } \
   && ! pacman -Qq nvidia-utils >/dev/null 2>&1; then
  missing+=(nvidia-utils)
fi

if [ "${#missing[@]}" -gt 0 ]; then
  helper=""
  for h in yay paru; do command -v "$h" >/dev/null && { helper="$h"; break; }; done
  [ -n "$helper" ] || die "Missing packages (${missing[*]}) and no AUR helper. Install 'yay' first, then re-run."
  say "Installing: ${missing[*]}"
  "$helper" -S --needed "${missing[@]}"
else
  say "All dependencies present."
fi

# --- helper: append the managed block to a lua file ------------------------
append_block() { # $1 = file, $2... = lines
  local file="$1"; shift
  { printf '\n%s\n' "$BEGIN"; printf '%s\n' "$@"; printf '%s\n' "$END"; } >>"$file"
}

# --- d. blur config ------------------------------------------------------
if grep -q "$NS" "$LOOKNFEEL"; then
  say "Blur already configured in looknfeel.lua - leaving it."
else
  say "Enabling dashboard blur in looknfeel.lua"
  append_block "$LOOKNFEEL" \
    'hl.config({ decoration = { blur = { enabled = true, size = 6, passes = 3 } } })' \
    'hl.layer_rule({' \
    "  match = { namespace = \"$NS\" }," \
    '  blur = true,' \
    '  xray = true,' \
    '  ignore_alpha = 0.2,' \
    '})'
fi

# --- e. autostart ------------------------------------------------------
if grep -Eq 'quickshell/dashboard|-c dashboard' "$AUTOSTART"; then
  say "Autostart already set in autostart.lua - leaving it."
else
  say "Adding dashboard to autostart.lua"
  append_block "$AUTOSTART" 'o.launch_on_start("qs -c dashboard")'
fi

# --- f. sensors nudge -------------------------------------------------
if ! sensors 2>/dev/null | grep -Eq 'Core|Package|temp'; then
  warn "No temp sensors detected - run 'sudo sensors-detect --auto' once or the temp tiles stay blank."
fi

# --- g. apply now -------------------------------------------------------
if command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi
if ! pgrep -f '(quickshell|qs) .*(-c dashboard|quickshell/dashboard)' >/dev/null 2>&1; then
  say "Launching the dashboard"
  qs -c dashboard >/dev/null 2>&1 & disown
else
  say "Dashboard already running - restart Hyprland or 'qs -c dashboard' to pick up changes."
fi

# --- h. summary --------------------------------------------------------
cat <<EOF

$(say "Done.")
  - dashboard   -> $DEST
  - blur        -> $LOOKNFEEL
  - autostart   -> $AUTOSTART (starts on next login too)

If the tiles look wrong, run 'qs -c dashboard' in a terminal to see errors.
Re-run this script any time to update. Undo with: $DEST/uninstall.sh
EOF
