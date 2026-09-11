# omarchy-dashboard

A [Quickshell](https://quickshell.outfoxxed.me/) widget for
[Omarchy](https://omarchy.org) (Hyprland + Arch): live system stats, weather,
a Pomodoro timer and neofetch-style host info as glass cards on the left and
right screen edges - put each tile on whichever edge you like. Cards follow
your Omarchy theme live, no restart needed.

| Tokyo Night | White | Vantablack | Catppuccin |
| ---------------------- | ---------------------- | ---------------------- | ---------------------- |
| ![Tokyo Night](assets/Tokyo-Night.png) | ![White](assets/White.png) | ![Vantablack](assets/Vantablack.png) | ![Catppuccin](assets/Catppuccin.png) |

| Ethereal | Matte Black | Everforest | Osaka Jade |
| ---------------------- | ---------------------- | ---------------------- | ---------------------- |
| ![Ethereal](assets/Ethereal.png) | ![Matte Black](assets/Matte-Black.png) | ![Everforest](assets/Everforest.png) | ![Osaka Jade](assets/Osaka-Jade.png) |

## Features

- Per-core CPU bars, package/core temps, rolling sparkline
- Memory, disk, and NVIDIA GPU usage (utilization, VRAM, temp, power draw)
- Battery status with time-to-full/empty (UPower)
- Network throughput (RX/TX) and ping, both with sparklines
- Now-playing media tile (MPRIS) - art, title/artist, progress bar, and
  prev/play-pause/next controls, for whichever player is currently active
- Weather tile (wttr.in) - temperature, condition, feels-like, humidity, wind
- Sun tile - sunrise/sunset times with a live sun-position arc
- Focus tile - a work/break (Pomodoro) timer; set the work/break lengths from
  the cog on the tile, get an Omarchy desktop notification and a chime when
  each period ends (mute the chime with the bell on the tile or from the
  Focus Timer settings page)
- Neofetch-style System tile (host, kernel, uptime, WM, theme, CPU, GPU, memory)
- Live theme sync with Omarchy
- Put any tile on the left edge, the right edge, or hide it - see below
- Columns adapt automatically: if the tiles don't fit your screen's height,
  extras overflow into a new column instead of running off-screen

## Settings

Double-click any tile to open **Dashboard Settings** - a window with a
category rail on the left:

- **Layout** - a screen-shaped board with a **Left edge**, a **Right edge**
  and a **Hidden** tray. Drag tiles between the zones and reorder within a
  zone; changes apply immediately. The right panel appears only while a tile
  is on it. Out of the box the system metrics (CPU, GPU, Memory, Disk,
  Battery, Network, Ping) plus Sun sit on the left, System and Focus on the
  right, and Media and Weather start hidden - drag any of them wherever you
  like.
- **Appearance** - glass-card opacity and an optional hairline border.
- **Display** - which monitor the dashboard lives on.
- **Weather** - the city for the Weather and Sun tiles.
- **Focus Timer** - the work / break lengths (the cog on the Focus tile
  jumps straight here).
- **About** - the installed version and an **Update now** button: it updates
  to the newest tagged release, installs any new dependencies and re-syncs the
  post-boot autostart hook (a terminal opens for the steps that need your
  password). This is the everyday way to update; re-running the install
  script does the same thing. It refuses if you have local edits to tracked
  files.

Everything is remembered automatically - no config file to edit.

The Weather and Sun tiles share their location with the Omarchy bar weather
widget (`~/.local/state/omarchy/settings/weather.json`) - set it from either
place, or with `omarchy-weather-location --set <city>`. With nothing set, the
location is auto-detected from your IP.

## Dependencies

| Dependency | Used for | Arch package |
| --- | --- | --- |
| [Quickshell](https://quickshell.outfoxxed.me/) | Runs the shell | `quickshell-git` (AUR) |
| Hyprland + [Omarchy](https://omarchy.org) | Live theming | ships with Omarchy |
| Qt5Compat | Theme-colored Omarchy logo (`ColorOverlay`) | `qt6-5compat` |
| `nvidia-smi` | GPU stats (NVIDIA only) | `nvidia-utils` |
| `lm-sensors` | CPU temps | `lm_sensors` |
| `inotify-tools` | Live theme/state watching | `inotify-tools` |
| `curl` | Weather / Sun tiles (wttr.in) | `curl` |
| `paplay` & `sound-theme-freedesktop` | Focus tile chime | `libpulse`, `sound-theme-freedesktop` (both ship with Omarchy) |
| coreutils | `ping`, `df`, `awk`, `hostname`, `uname` | already on your system |

Run `sudo sensors-detect` once if you've never configured `sensors`, or temp
tiles stay blank.

## Install

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/D3m0nZOnFire/omarchy-dashboard/main/install.sh)
```

One command: installs the dependencies, clones into
`~/.config/quickshell/dashboard`, and registers an `omarchy hook install
post-boot` hook so the dashboard **auto-starts** with Hyprland. It then
launches it right away. It checks out the newest tagged release, not bleeding
`main`.

Nothing under `~/.config/hypr/` is ever touched - the frosted-glass blur is
requested by the dashboard itself at runtime (Quickshell's `BackgroundEffect`,
over the `ext-background-effect-v1` Wayland protocol), and autostart goes
through Omarchy's own post-boot hooks instead of an `autostart.lua` edit.

**Updating:** Dashboard Settings -> **About** -> *Update now* (or just re-run
the install command). Both move you to the latest release.
`~/.config/quickshell/dashboard/uninstall.sh` backs the hook out.

No config file to touch afterwards: the panels attach to your laptop screen
automatically (or the first screen otherwise), and you pick a different output
from the **Display** page of Dashboard Settings (double-click any tile). QML edits
hot-reload while it's running. [`Config.qml`](Config.qml) is only for edge
cases: `screenName` as a fallback output when the picker is on "Automatic", or
`pingHost` if `1.1.1.1` doesn't work for you.

**NVIDIA GPU tile**: stats come from `nvidia-smi` (`SystemMetrics.qml`). On
AMD/Intel, swap in `radeontop` or `intel_gpu_top` and adjust the parser.

<details>
<summary>Manual setup / vanilla Hyprland</summary>

1. Clone into your Quickshell config dir (folder name must stay `dashboard`)
   and check out the latest release:

   ```sh
   git clone https://github.com/D3m0nZOnFire/omarchy-dashboard ~/.config/quickshell/dashboard
   cd ~/.config/quickshell/dashboard
   git checkout -B main "$(git tag -l --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n1)"
   ```

   To update later: `git fetch --tags` then re-run that `git checkout` line
   (or use Dashboard Settings -> About).

2. Run it in the foreground first to catch errors, then detached:

   ```sh
   qs -c dashboard        # foreground
   qs -c dashboard -d     # detached; or add to autostart
   ```

   Autostart on Omarchy - install a post-boot hook instead of editing
   `autostart.lua` (see [`hooks/post-boot.sh`](hooks/post-boot.sh)):

   ```sh
   omarchy hook install post-boot ~/.config/quickshell/dashboard/hooks/post-boot.sh
   ```

   Vanilla Hyprland has no post-boot hook system - add to `hyprland.conf`
   instead: `exec-once = qs -c dashboard`.

3. **Blur needs Hyprland >= 0.56.0** and **Quickshell >= 0.3** (`hyprctl
   version` / `qs --version`) - both ship the `ext-background-effect-v1`
   Wayland protocol the dashboard uses to request its own blur at runtime, no
   `layer_rule` needed. On Omarchy, Hyprland still ships
   `decoration.blur.enabled = false` by default; the dashboard flips that on
   for you live (`hyprctl dispatch 'hl.config(...)'`, not a file edit) and
   keeps it in sync with the **Appearance** page's blur picker - off again
   when you pick "Transparent". No action needed on your part. On vanilla
   Hyprland there's no Lua config API for the dashboard to call, so set
   `decoration { blur { enabled = true } }` yourself in `hyprland.conf` - the
   protocol request still works, only the auto-toggle is Omarchy-specific. On
   older Hyprland/Quickshell the cards still render, just without blur -
   washed-out gray boxes rather than glass.

</details>

## Troubleshooting

- **Blank/zero tiles**: test the underlying command directly (`nvidia-smi`,
  `sensors`, `ping -c1 1.1.1.1`, `df -k /`).
- **Theme doesn't update**: check `inotifywait` is installed and
  `omarchy-theme-color --all` works.
- **Wrong monitor**: set `screenName` in `Config.qml` to the output you want
  (see `hyprctl monitors` for names).
- **Flat gray cards, no blur**: check `hyprctl version` (needs >= 0.56.0) and
  `qs --version` (needs >= 0.3); on vanilla Hyprland, check
  `hyprctl getoption decoration:blur:enabled` is `true`.
- **Media tile says "Nothing playing"**: it needs a running player that
  exposes MPRIS - most do (Spotify, browsers playing audio/video, VLC, mpv
  with the `mpris` plugin, etc.).
- **Weather tile stuck on "Fetching…"**: check `curl` is installed and
  `curl -fsS 'https://wttr.in/?format=j1'` returns JSON; wttr.in rate-limits,
  so it can be briefly unavailable.

## License

MIT - see [LICENSE](LICENSE).
