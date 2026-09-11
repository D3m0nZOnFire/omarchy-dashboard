#!/usr/bin/env bash
# omarchy-dashboard installer.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/D3m0nZOnFire/omarchy-dashboard/main/install.sh)
#
# Clones (or updates) the dashboard, installs its dependencies, and wires it
# into Omarchy's post-boot hooks so it autostarts. Safe to re-run - that is
# also how you update. Tracks tagged releases (vX.Y.Z), not raw main; see
# RELEASING.md. Never touches ~/.config/hypr/* - blur is requested by the
# dashboard itself at runtime (see shell.qml), and autostart goes through
# `omarchy hook install`, not an autostart.lua edit. Requires Omarchy (uses
# the `omarchy` CLI); for vanilla Hyprland see the README's "Manual setup"
# section. Back it out with ./uninstall.sh.
#
# Track a branch tip instead of releases (dev testing):
#   BRANCH=dev bash <(curl -fsSL https://raw.githubusercontent.com/D3m0nZOnFire/omarchy-dashboard/dev/install.sh)

set -euo pipefail

REPO_URL="https://github.com/D3m0nZOnFire/omarchy-dashboard"
BRANCH="${BRANCH:-main}"
DEST="$HOME/.config/quickshell/dashboard"
HYPR="$HOME/.config/hypr"
HOOK_TYPE="post-boot"
HOOK_SRC="$DEST/hooks/post-boot.sh"
HOOK_DEST="$HOME/.config/omarchy/hooks/$HOOK_TYPE.d/$(basename "$HOOK_SRC")"
BEGIN="-- >>> omarchy-dashboard (managed) >>>"
END="-- <<< omarchy-dashboard (managed) <<<"

say()  { printf '\033[1;32m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# Never run repo-local hook scripts during any git operation here.
GIT=(git -c core.hooksPath=/dev/null)

# Newest vX.Y.Z tag in $DEST, or empty if there are none.
latest_release_tag() {
  "${GIT[@]}" -C "$DEST" tag -l --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1 || true
}

# Move $DEST onto the newest release tag. $1 = "clone" forces the checkout
# (fresh tree, nothing to lose); otherwise fast-forward only. Fetches over
# HTTPS ($REPO_URL) so it never depends on an SSH key.
sync_to_release() {
  "${GIT[@]}" -C "$DEST" fetch --tags --quiet "$REPO_URL" \
    || { warn "Could not fetch tags - staying on the current version."; return 0; }
  local tag; tag="$(latest_release_tag)"
  if [ -z "$tag" ]; then
    warn "No release tags found - using '$BRANCH' HEAD."; return 0
  fi
  if [ "$("${GIT[@]}" -C "$DEST" describe --tags --abbrev=0 2>/dev/null || true)" = "$tag" ]; then
    say "Already on the latest release ($tag)."
  elif [ "${1:-}" = "clone" ]; then
    say "Checking out $tag"
    "${GIT[@]}" -C "$DEST" checkout -q -B "$BRANCH" "$tag"
  else
    say "Updating to $tag"
    "${GIT[@]}" -C "$DEST" merge --ff-only "$tag" \
      || warn "Could not fast-forward to $tag - resolve manually (git -C $DEST status)."
  fi
}

# --- a. preflight -----------------------------------------------------------
command -v pacman >/dev/null || die "This installer is for Arch/Omarchy (no pacman found)."
command -v omarchy >/dev/null || die \
  "The 'omarchy' command wasn't found. See the README's Manual setup section for vanilla Hyprland."

# --- b. clone / update -----------------------------------------------------
# Default (BRANCH=main): $DEST tracks the newest vX.Y.Z release tag. Setting
# BRANCH=<name> tracks that branch's tip instead, for dev testing.
DEV_BRANCH=false; [ "$BRANCH" = "main" ] || DEV_BRANCH=true

if [ -e "$DEST/.git" ] && git -C "$DEST" remote get-url origin 2>/dev/null | grep -q 'omarchy-dashboard'; then
  cur="$(git -C "$DEST" symbolic-ref --short -q HEAD || echo '')"
  if [ "$cur" != "$BRANCH" ]; then
    warn "$DEST is on branch '$cur' (expected '$BRANCH') - leaving it as-is."
  elif $DEV_BRANCH; then
    say "Updating $DEST (branch $cur)"
    "${GIT[@]}" -C "$DEST" pull --ff-only origin "$cur" \
      || warn "Could not fast-forward $cur - update manually."
  else
    say "Updating $DEST"
    sync_to_release
  fi
elif [ -e "$DEST" ]; then
  die "$DEST already exists and is not an omarchy-dashboard checkout. Move it aside and re-run."
else
  say "Cloning into $DEST"
  mkdir -p "$(dirname "$DEST")"
  # Full history but no historical file blobs - lets `git describe` / release
  # tags work while keeping the download small.
  "${GIT[@]}" clone --filter=blob:none --branch "$BRANCH" "$REPO_URL" "$DEST"
  $DEV_BRANCH || sync_to_release clone
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

# --- d. remove any pre-hook install ---------------------------------------
# Versions before the ext-background-effect blur rework edited
# ~/.config/hypr/looknfeel.lua and autostart.lua directly (marked with the
# BEGIN/END banner below). Someone updating from one of those - the normal
# path is re-running this script, not uninstall.sh - would otherwise keep
# the old namespace-wide layer_rule, which blurs the whole panel again and
# fights the new per-tile blur. Strip it here too, not just on uninstall.
reload_needed=false
for file in "$HYPR/looknfeel.lua" "$HYPR/autostart.lua"; do
  [ -f "$file" ] || continue
  if grep -qF -- "$BEGIN" "$file"; then
    say "Removing old managed block from $file"
    awk -v b="$BEGIN" -v e="$END" '
      $0 == b { skip = 1 }
      !skip   { if ($0 == "" && prev == "") next; print; prev = $0 }
      $0 == e { skip = 0 }
    ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
    reload_needed=true
  fi
done
if $reload_needed && command -v hyprctl >/dev/null && hyprctl version >/dev/null 2>&1; then
  hyprctl reload >/dev/null 2>&1 || true
fi

# --- e. autostart --------------------------------------------------------
# `omarchy hook install` copies $HOOK_SRC into ~/.config/omarchy/hooks/
# post-boot.d/ (overwriting any previous copy), which Omarchy's own base
# Hyprland config already runs on every login - no autostart.lua edit needed.
say "Installing the autostart hook"
omarchy hook install "$HOOK_TYPE" "$HOOK_SRC" >/dev/null

# --- f. sensors nudge -------------------------------------------------
if ! sensors 2>/dev/null | grep -Eq 'Core|Package|temp'; then
  warn "No temp sensors detected - run 'sudo sensors-detect --auto' once or the temp tiles stay blank."
fi

# --- g. apply now -------------------------------------------------------
# A running instance already hot-reloaded shell.qml as soon as step b's git
# merge touched it - including its own compositor-blur sync - *before* step
# d's hyprctl reload re-read the (now legacy-free) config files and reset
# decoration.blur.enabled back to file default. So a plain "leave it running"
# would silently land on blur-off. If we just migrated a legacy install,
# restart it instead of leaving it running, so it re-syncs blur cleanly
# after the config files have already settled.
running=$(pgrep -f '(quickshell|qs) .*(-c dashboard|quickshell/dashboard)' || true)
if [ -z "$running" ]; then
  say "Launching the dashboard"
  qs -c dashboard >/dev/null 2>&1 & disown
elif $reload_needed; then
  say "Restarting the dashboard to re-sync blur after the legacy config cleanup"
  kill $running 2>/dev/null || true
  sleep 1
  qs -c dashboard >/dev/null 2>&1 & disown
else
  say "Dashboard already running - restart Hyprland or 'qs -c dashboard' to pick up changes."
fi

# --- h. summary --------------------------------------------------------
cat <<EOF

$(say "Done.")
  - dashboard   -> $DEST
  - autostart   -> $HOOK_DEST (starts on next login too)

Blur is requested by the dashboard itself at runtime - nothing under
~/.config/hypr/ was touched. If the tiles look wrong, run 'qs -c dashboard'
in a terminal to see errors.
Update later from Dashboard Settings -> About, or by re-running this script.
Undo with: $DEST/uninstall.sh
EOF
