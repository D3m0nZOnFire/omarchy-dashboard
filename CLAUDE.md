# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`omarchy-dashboard` is a [Quickshell](https://quickshell.outfoxxed.me/) widget for
[Omarchy](https://omarchy.org) (Hyprland + Arch): glass-card tiles (system stats,
weather, Pomodoro focus timer, neofetch-style host info) docked to the left/right
screen edges. Pure QML + JS, no build step, no package manager, no test suite
(qmllint in CI is the only automated check).

## Running / testing changes

There is no build system. QML hot-reloads while the shell is running.

```sh
qs -c dashboard        # run in foreground - watch for QML errors, must print "Configuration Loaded"
qs -c dashboard -d -n  # detached, skip launch if already running (what the post-boot hook does)
```

To exercise a change: run in the foreground, double-click any tile to open
**Dashboard Settings**, and walk the pages relevant to your change (Layout,
Appearance, Display, Weather, Focus Timer, About). There are no unit tests.

Before pushing, lint (CI runs the same in an Arch container, see
`.github/workflows/qmllint.yml`; disabled categories and why are in
`.qmllint.ini`):

```sh
/usr/lib/qt6/bin/qmllint -I . --max-warnings 0 *.qml tiles/*.qml
```

## Architecture

- **`shell.qml`** is the root `Scope` - it owns all persisted state, the
  tile registry (`tileMap`: one `Component` per tile id), the two edge
  panels and the settings window. Almost everything wires through
  `id: shell`.
- **Tiles** live in `tiles/<Name>Tile.qml`, one `StatCard` each. A tile
  gets the root through its `shell` property and reads everything else
  through it (`shell._theme`, `shell._fg()`, `metrics`/`weather` via
  `shell._metrics` / `shell._weather`). In shell.qml, bind it with
  `shell: _shell`, never `shell: shell`: inside a `Component` block the
  tile's own `shell` property shadows the root id, so `shell: shell` binds
  to itself (null). Same reason for `_theme`.
- **`EdgePanel.qml`** is one screen edge (`edge: "left" | "right"`): a
  layer-shell `PanelWindow` that lays out its tiles and their blur regions.
- **`Updater.qml`** is the About page's updater (see below).
- **Tile placement model**: `defaultTileOrder` (master list of tile ids) +
  a `placement` map (`"left" | "right" | "hidden"` per id) derived into
  `leftTiles` / `rightTiles`. Both panels render their tiles via `Repeater`
  inside a `Flow { flow: Flow.TopToBottom }`, so columns overflow
  automatically instead of clipping when tiles don't fit the screen height.
  The right panel additionally sets `LayoutMirroring.enabled: true` so its
  first column hugs the screen edge like the left panel's does.
- **Persistence**: a single `FileView` + `JsonAdapter` (`tileOrderFile` /
  `tileOrderAdapter` in `shell.qml`) writes everything - tile order,
  placement, screen choice, blur %, border toggle, focus timer lengths, mute
  state - to `Quickshell.stateDir + "/tile-order.json"`. There is no other
  config file; add new persisted settings as properties on `tileOrderAdapter`
  and call `tileOrderFile.writeAdapter()`.
- **`Config.qml`** is a separate, much smaller escape hatch for the couple of
  settings not exposed in the UI (`screenName` fallback, `pingHost`) - edited
  by hand, not persisted by the app.
- **Live theming**: `Theme.qml` shells out to `omarchy-theme-color --all` and
  watches `~/.local/state/omarchy/current` (via `inotifywait`) to re-resolve
  whenever the Omarchy theme changes - no restart needed. `shell.qml`
  instantiates one shared `Theme { id: theme }` and passes it down to every
  tile/`StatCard`/`Ui*` control as a `theme` property; `ColorUtil.js` (a
  `.pragma library`) has the shared contrast/luminance helpers used to pick
  readable text/icon colors against the current accent.
- **Blur**: requested at runtime over the `ext-background-effect-v1` Wayland
  protocol (`BackgroundEffect.blurRegion` on each `EdgePanel`, filled with
  per-tile `Region`s so only the cards blur, not the gaps). On Omarchy,
  `shell.qml` also flips `decoration.blur.enabled` on/off live via
  `hyprctl eval 'hl.config(...)'` to match the Appearance page's picker -
  never a Hyprland config file edit. Needs Hyprland >= 0.56.0 and Quickshell
  >= 0.3.
- **Data sources are all external processes/services**, not libraries: CPU
  via `/proc` + `sensors`, GPU via `nvidia-smi` (NVIDIA-only - swap the
  parser in `SystemMetrics.qml` for AMD/Intel), battery via
  `Quickshell.Services.UPower`, media via `Quickshell.Services.Mpris`,
  weather via Open-Meteo/wttr.in in `WeatherService.qml` (mirrors what the
  Omarchy bar's weather widget reads from
  `~/.local/state/omarchy/settings/weather.json`, including geocoding on
  location change so both stay in sync).
- **Updater** (`Updater.qml`, backs the Settings "About" page): read-only
  `git fetch --tags` + comparison against the newest `vX.Y.Z` tag to check
  for updates; the actual update re-runs `install.sh` in a spawned terminal
  (needs sudo for deps). It refuses to update if the checkout has local edits
  to tracked files. The dashboard **only ever tracks tagged releases**, never
  raw `main` - see `RELEASING.md` before assuming a commit on `main` is "live"
  for users.
- **UI primitives** (`UiToggle`, `UiSegmented`, `UiChoiceRow`, `UiStepper`)
  are small stateless controls under `Ui*.qml` - they render a prop and emit
  a signal; the parent (usually `SettingsModal.qml`) owns the actual value
  and persistence. Reuse these instead of hand-rolling a new control for a
  settings page.
- **`SettingsModal.qml`** is the "Dashboard Settings" window: a left category
  rail (Layout / Appearance / Display / Weather / Focus Timer / About) with
  the selected page's controls on the right, opened by double-clicking any
  tile.

## Conventions

- Never edit `~/.config/hypr/*` - blur and autostart are both wired at
  runtime/through Omarchy hooks (`hooks/post-boot.sh` via
  `omarchy hook install post-boot`), specifically so this dashboard doesn't
  touch the user's Hyprland config.
- New persisted UI state goes on `tileOrderAdapter` in `shell.qml`, not a new
  file.
- Releases are cut by tagging `main` (`vX.Y.Z`); see `RELEASING.md` for the
  full checklist (smoke test, tag, `gh release create`, verify from a
  throwaway clone) before assuming a change needs a version bump.
