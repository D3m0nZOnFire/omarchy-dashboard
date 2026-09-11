#!/bin/bash
# Launches the dashboard at login. Installed with `omarchy hook install
# post-boot` (see install.sh) into ~/.config/omarchy/hooks/post-boot.d/ -
# Omarchy already runs every script there on every Hyprland start, so this
# needs no Hyprland config of its own (no autostart.lua edit).
#
# -d daemonizes (detaches so this hook script returns immediately instead of
# blocking the rest of the post-boot chain); -n skips the launch if an
# instance is already running, in case this ever fires twice in one session.
qs -c dashboard -d -n
