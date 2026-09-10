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
- Focus tile - a work/break (Pomodoro) timer with the now-playing track and
  transport controls; set the work/break lengths from the cog on the tile, and
  get an Omarchy desktop notification when each period ends
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
  is on it. The System tile is just another tile - it starts on the right,
  drag it wherever you want.
- **Appearance** - glass-card opacity and an optional hairline border.
- **Display** - which monitor the dashboard lives on.
- **Weather** - the city for the Weather and Sun tiles.
- **Focus Timer** - the work / break lengths (the cog on the Focus tile
  jumps straight here).

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
| coreutils | `ping`, `df`, `awk`, `hostname`, `uname` | already on your system |

Run `sudo sensors-detect` once if you've never configured `sensors`, or temp
tiles stay blank.

## Install

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/D3m0nZOnFire/omarchy-dashboard/main/install.sh)
```

One command: installs the dependencies, clones into
`~/.config/quickshell/dashboard`, enables the frosted-glass blur in
`looknfeel.lua`, and sets the dashboard to **auto-start** with Hyprland. It
then launches it right away. Safe to re-run - that's also how you update.
`~/.config/quickshell/dashboard/uninstall.sh` backs the config changes out.

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

1. Clone into your Quickshell config dir (folder name must stay `dashboard`):

   ```sh
   git clone https://github.com/D3m0nZOnFire/omarchy-dashboard ~/.config/quickshell/dashboard
   ```

2. Run it in the foreground first to catch errors, then detached:

   ```sh
   qs -c dashboard        # foreground
   qs -c dashboard -d     # detached; or add to autostart
   ```

   Autostart on Omarchy - add to `~/.config/hypr/autostart.lua`:

   ```lua
   o.launch_on_start("qs -c dashboard")
   ```

3. **Enable Hyprland background blur** - required. The cards are translucent by
   design; without blur they're just washed-out gray boxes.

   Omarchy (`~/.config/hypr/looknfeel.lua`):

   ```lua
   hl.config({
     decoration = { blur = { enabled = true, size = 6, passes = 3 } },
   })

   hl.layer_rule({
     match = { namespace = "quickshell:dashboard" },
     blur = true,
     xray = true,
     ignore_alpha = 0.2,
   })
   ```

   Vanilla Hyprland (`hyprland.conf`):

   ```
   decoration {
     blur { enabled = true; size = 6; passes = 3 }
   }

   layerrule = blur, quickshell:dashboard
   layerrule = xray, quickshell:dashboard
   layerrule = ignorealpha 0.2, quickshell:dashboard
   ```

   Then `hyprctl reload`. (`ignore_alpha` skips blurring the fully transparent
   gaps between cards - drop it if you want those blurred too.)

</details>

## Troubleshooting

- **Blank/zero tiles**: test the underlying command directly (`nvidia-smi`,
  `sensors`, `ping -c1 1.1.1.1`, `df -k /`).
- **Theme doesn't update**: check `inotifywait` is installed and
  `omarchy-theme-color --all` works.
- **Wrong monitor**: set `screenName` in `Config.qml` to the output you want
  (see `hyprctl monitors` for names).
- **Flat gray cards, no blur**: blur isn't on, or `hyprctl reload` didn't take
  - check `hyprctl getoption decoration:blur:enabled`.
- **Media tile says "Nothing playing"**: it needs a running player that
  exposes MPRIS - most do (Spotify, browsers playing audio/video, VLC, mpv
  with the `mpris` plugin, etc.).
- **Weather tile stuck on "Fetching…"**: check `curl` is installed and
  `curl -fsS 'https://wttr.in/?format=j1'` returns JSON; wttr.in rate-limits,
  so it can be briefly unavailable.

## License

MIT - see [LICENSE](LICENSE).
