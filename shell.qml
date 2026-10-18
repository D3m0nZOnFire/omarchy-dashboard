import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects
import "tiles"

Scope {
    id: shell

    // Machine-specific settings - see Config.qml
    Config { id: config }

    // Shared screen reference - which output to put the panels on.
    // 1. Explicit override picked in the reorder/settings modal
    //    (persisted in tile-order.json), if set.
    // 2. Explicit override from Config.screenName, if set.
    // 3. Fall back to the first screen.
    readonly property var _mainScreen: {
        var wanted = shell.screenName !== "" ? shell.screenName : config.screenName
        if (wanted !== "") {
            for (var i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === wanted) return Quickshell.screens[i]
            }
        }
        return Quickshell.screens[0]
    }

    // Shared: is the laptop currently running on battery? Slows every
    // metrics/weather poll down below (see SystemMetrics.qml/WeatherService.qml).
    // Gated by the Performance page's "Slow down on battery" toggle.
    readonly property bool _onBattery: shell.throttleOnBattery && UPower.displayDevice
        ? UPower.displayDevice.state === UPowerDeviceState.Discharging
        : false

    // Shared: is there any window open on the dashboard's own monitor right
    // now? Wayland has no true occlusion signal (no compositor tells a
    // client what's drawn over it - that's deliberate, same reason
    // screenshotting another app needs a portal), and the generic
    // Quickshell.Wayland "fullscreen"/"maximized" toplevel flags turned out
    // not to be the right proxy either: Hyprland is a *tiling* WM, so a
    // perfectly ordinary tiled window fills the whole workspace (covering
    // the dashboard's Bottom-layer edges right along with it) without ever
    // being reported as fullscreen or maximized - those flags only apply to
    // floating windows. What's actually reliable here is Hyprland's own
    // workspace state: whether the active workspace on this monitor has any
    // toplevels on it at all. Empty workspace (just wallpaper) = not
    // covered; anything open = covered, tiled or not. Fully event-driven via
    // Hyprland's IPC socket, no polling. Gated by the Performance page's
    // "Pause when covered" toggle.
    readonly property var _dashMonitor: shell._mainScreen ? Hyprland.monitorFor(shell._mainScreen) : null
    readonly property bool _dashboardCovered: {
        if (!shell.pauseWhenCovered) return false
        var mon = shell._dashMonitor
        var ws = mon ? mon.activeWorkspace : null
        // Only count windows Wayland still knows about: Quickshell
        // snapshots Hyprland's window list at startup, and a window that
        // closes during that startup misses its close event and lingers in
        // `toplevels` forever (Hyprland.refreshToplevels() doesn't drop it
        // either) - which left the screen "covered" and every poll paused.
        // The About page's updater hit this every time: its terminal closes
        // right after relaunching the dashboard. Such a ghost has no
        // `wayland` handle; every live window does.
        return !!ws && ws.toplevels.values.some(t => t.wayland !== null)
    }

    // Shared metrics (accessible from both panels by id). Each *Enabled flag
    // stops that metric's subprocess polling entirely while its tile isn't
    // placed on either edge, or while the screen is covered - no point
    // forking nvidia-smi/sensors/ping/df for a tile nobody sees.
    SystemMetrics {
        id: metrics
        pingHost:    config.pingHost
        onBattery:   shell._onBattery
        cpuEnabled:  (shell._placeOf("cpu") !== "hidden" || shell._placeOf("memory") !== "hidden") && !shell._dashboardCovered
        gpuEnabled:  shell._placeOf("gpu") !== "hidden" && !shell._dashboardCovered
        netEnabled:  shell._placeOf("network") !== "hidden" && !shell._dashboardCovered
        pingEnabled: shell._placeOf("ping") !== "hidden" && !shell._dashboardCovered
        diskEnabled: shell._placeOf("disk") !== "hidden" && !shell._dashboardCovered
    }

    // Shared weather data for the Weather and Sun tiles. Location comes from
    // Omarchy's own weather setting (see WeatherService.qml). Only polls
    // while one of those two tiles is actually placed on an edge and the
    // screen isn't covered.
    WeatherService {
        id: weather
        onBattery: shell._onBattery
        enabled:   (shell._placeOf("weather") !== "hidden" || shell._placeOf("sun") !== "hidden") && !shell._dashboardCovered
    }

    // Live Omarchy theme palette (accessible from both panels by id).
    // glassAlpha / glassBorder carry the persisted BLUR and BORDER
    // settings to every StatCard without per-tile plumbing.
    Theme { id: theme; glassAlpha: shell.blurAlpha; glassBorder: shell.tileBorder }
    // Unshadowed alias - inside a Component {} block (see the per-tile
    // Components below), a bare `theme: theme` binding on an object with
    // its own `theme` property resolves to itself (null) instead of this
    // id, since the Component root shadows outer ids of the same name.
    // Use `shell._theme` there instead.
    readonly property Item _theme: theme
    // Same for the tiles in tiles/: each takes a `shell` property, so they
    // get the root and the ids they read through these instead.
    readonly property var _shell: shell
    readonly property var _metrics: metrics
    readonly property var _weather: weather
    readonly property var _config: config
    readonly property var _reorderModal: reorderModal

    // ── Tile placement - which tiles show, on which edge, in what order ──
    // Persisted to disk so a drag (via double-click → Settings → Layout)
    // survives restarts. `tileOrder` is the master order; `placement` maps
    // each id to "left" | "right" | "hidden". Per-edge lists are the order
    // filtered by placement, so a within-edge reorder just rewrites order.
    readonly property var defaultTileOrder: ["cpu", "gpu", "memory", "disk", "battery", "network", "ping", "sun", "system", "focus", "media", "weather"]
    // Where a tile sits when the user has never moved it. Anything not
    // listed defaults to "left". Media and Weather start hidden - they need a
    // player running / a location set to be useful.
    readonly property var defaultPlacement: ({ system: "right", focus: "right", media: "hidden", weather: "hidden" })
    readonly property var tileLabels: ({
        weather: "Weather",
        sun:     "Sun",
        cpu:     "CPU",
        memory:  "Memory",
        gpu:     "GPU",
        battery: "Battery",
        disk:    "Disk",
        network: "Network",
        ping:    "Ping",
        media:   "Media",
        focus:   "Focus",
        system:  "System",
    })
    // id → Component, shared by both panels (see the Component blocks near
    // the end of this file).
    readonly property var tileMap: ({
        weather: weatherTile, sun: sunTile, cpu: cpuTile, memory: memoryTile,
        gpu: gpuTile, battery: batteryTile, disk: diskTile, network: networkTile,
        ping: pingTile, media: mediaTile, focus: focusTile, system: systemTile,
    })
    property var tileOrder: defaultTileOrder
    property var placement: ({})
    // Output the panels are pinned to, chosen in the modal's Display picker.
    // "" means "no override" - fall back to Config.screenName / auto-detect.
    property string screenName: ""
    // Glass-card tint, chosen in the modal's BLUR picker. Stored as a
    // percentage (one of 0/25/50/75/100); the on-screen alpha is derived
    // via _blurAlphaFor and kept low/capped on purpose - the actual "more
    // blur" feel comes from _blurParamsFor growing the real compositor blur
    // radius below, not from painting a more solid color over the card. A
    // card at full alpha with no blur behind it would just be a flat
    // rectangle, which is the "fake dark tile" this split avoids.
    property int blurPercent: 50
    readonly property real blurAlpha: shell._blurAlphaFor(shell.blurPercent)
    function _blurAlphaFor(pct) {
        switch (pct) {
            case 0:   return 0.0    // fully transparent - compositor blur is skipped too, see _syncCompositorBlur
            case 25:  return 0.25
            case 75:  return 0.45
            case 100: return 0.55
            default:  return 0.35   // Medium / unknown
        }
    }
    // Real compositor blur strength for each preset - size is the blur
    // radius, passes multiplies its effective spread. Growing these (rather
    // than just the tint alpha above) is what actually makes higher presets
    // look "more blurred" instead of "more opaque".
    function _blurParamsFor(pct) {
        switch (pct) {
            case 25:  return { size: 3, passes: 1 }
            case 75:  return { size: 7, passes: 3 }
            case 100: return { size: 9, passes: 4 }
            default:  return { size: 5, passes: 2 }   // Medium / unknown
        }
    }
    // Hyprland ships decoration.blur.enabled=false by default, and that's
    // the master switch the per-tile BackgroundEffect regions below still
    // depend on - the ext-background-effect protocol says *where* to blur,
    // but Hyprland won't render any blur at all until this is on. Requested
    // live through the Lua config API instead of ever being persisted to
    // looknfeel.lua, so the dashboard never writes to a Hyprland config
    // file. It's a global toggle though (not scoped to this app's own
    // windows), and Hyprland resets it on any config reload, so it's kept
    // in sync with the BLUR picker - re-asserted at startup, on every
    // change, and after every Hyprland config reload (see the
    // configreloaded listener below) - rather than set once, and turned
    // back off when the user picks "Transparent".
    function _syncCompositorBlur() {
        var on = shell.blurPercent > 0
        var p = shell._blurParamsFor(shell.blurPercent)
        compositorBlurProc.command = ["hyprctl", "eval",
            "hl.config({decoration={blur={enabled=" + (on ? "true" : "false") +
            ",size=" + p.size + ",passes=" + p.passes + "}}})"]
        compositorBlurProc.running = true
    }
    Process { id: compositorBlurProc; running: false }
    // A config reload (file save under ~/.config/hypr, monitor hotplug,
    // Omarchy toggles...) resets decoration.blur back to the config file's
    // value, leaving the cards as a bare faint tint - re-assert ours.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                Qt.callLater(shell._syncCompositorBlur)
        }
    }
    // Whether the glass cards draw a hairline outline. Chosen in the
    // modal's BORDER toggle; off by default.
    property bool tileBorder: false
    // Focus tile work/break lengths (minutes), edited via the cog on the tile.
    property int focusWorkMinutes: 25
    property int focusBreakMinutes: 5
    // Whether the Focus tile plays a chime when a period ends. Toggled by the
    // bell on the tile and on the modal's Focus Timer page.
    property bool focusSound: true
    // Power-saving toggles, edited on the modal's Performance page - see
    // _onBattery / _dashboardCovered above for what each one gates.
    property bool throttleOnBattery: true
    property bool pauseWhenCovered:  true

    // Resolved placement of one tile, honouring the default.
    function _placeOf(id) {
        var z = shell.placement[id]
        if (z === "left" || z === "right" || z === "hidden") return z
        return shell.defaultPlacement[id] || "left"
    }
    // What each panel renders.
    readonly property var leftTiles:  shell.tileOrder.filter(function(id) { return shell._placeOf(id) === "left" })
    readonly property var rightTiles: shell.tileOrder.filter(function(id) { return shell._placeOf(id) === "right" })

    // Collects each visible tile's own blur Region (a child of that tile's
    // wrapper Item in the panel's Repeater, see leftTileRepeater /
    // rightTileRepeater below) into the panel-level container Region, so
    // only the card rectangles blur - not the gaps between them or the
    // margins around them. Re-run whenever a panel's tile count changes
    // (tile added/removed/hidden/moved to the other edge).
    function _rebuildBlurRegions(repeater, container) {
        var arr = []
        for (var i = 0; i < repeater.count; i++) {
            var it = repeater.itemAt(i)
            if (it && it.blurRegion) arr.push(it.blurRegion)
        }
        container.regions = arr
    }
    function _rebuildLeftBlur()  { shell._rebuildBlurRegions(leftTileRepeater, leftBlurRegion) }
    function _rebuildRightBlur() { shell._rebuildBlurRegions(rightTileRepeater, rightBlurRegion) }

    // Reconciles the saved order against the known tile ids - drops
    // anything unrecognized, appends any tile missing from a stale file.
    function _reconcileTileOrder(raw) {
        const known = shell.defaultTileOrder
        const seen  = {}
        const result = []
        for (var i = 0; i < raw.length; i++) {
            const id = raw[i]
            if (known.indexOf(id) !== -1 && !seen[id]) {
                result.push(id)
                seen[id] = true
            }
        }
        for (var j = 0; j < known.length; j++) {
            if (!seen[known[j]]) result.push(known[j])
        }
        return result
    }
    function _applyLoadedTileOrder() {
        shell.tileOrder = shell._reconcileTileOrder(tileOrderAdapter.order || [])
        shell.placement = shell._loadPlacement()
        shell.screenName = tileOrderAdapter.screenName || ""
        shell.blurPercent = [0, 25, 50, 75, 100].indexOf(tileOrderAdapter.blur) !== -1
                            ? tileOrderAdapter.blur : 50
        shell.tileBorder = tileOrderAdapter.border === true
        shell.focusWorkMinutes  = _clampInt(tileOrderAdapter.focusWork,  1, 180, 25)
        shell.focusBreakMinutes = _clampInt(tileOrderAdapter.focusBreak, 1, 60,  5)
        shell.focusSound = tileOrderAdapter.focusSound !== false
        shell.throttleOnBattery = tileOrderAdapter.throttleOnBattery !== false
        shell.pauseWhenCovered  = tileOrderAdapter.pauseWhenCovered  !== false
        shell._syncCompositorBlur()
    }
    // Reads `placement`, or migrates a pre-placement file (old `hidden`
    // array + `rightPanel` bool) the first time it is seen.
    function _loadPlacement() {
        var raw = tileOrderAdapter.placement || ({})
        var valid = { left: true, right: true, hidden: true }
        var out = {}
        var hasKeys = false
        for (var k in raw) {
            hasKeys = true
            if (shell.defaultTileOrder.indexOf(k) !== -1 && valid[raw[k]]) out[k] = raw[k]
        }
        if (hasKeys) return out

        var oldHidden = tileOrderAdapter.hidden || []
        var p = {}
        for (var i = 0; i < shell.tileOrder.length; i++) {
            var id = shell.tileOrder[i]
            if (id !== "system" && oldHidden.indexOf(id) !== -1) p[id] = "hidden"
        }
        p["system"] = (tileOrderAdapter.rightPanel === false) ? "hidden" : "right"
        // Persist the upgraded shape once, after this load settles.
        Qt.callLater(function() { shell.savePlacement(shell.tileOrder, p) })
        return p
    }
    function _clampInt(v, lo, hi, fallback) {
        var n = parseInt(v)
        return (!isNaN(n) && n >= lo && n <= hi) ? n : fallback
    }
    function savePlacement(newOrder, newPlacement) {
        shell.tileOrder = newOrder
        shell.placement = newPlacement
        tileOrderAdapter.order = newOrder
        tileOrderAdapter.placement = newPlacement
        tileOrderFile.writeAdapter()
    }
    function saveScreenName(name) {
        shell.screenName = name
        tileOrderAdapter.screenName = name
        tileOrderFile.writeAdapter()
    }
    function saveBlurPercent(pct) {
        shell.blurPercent = pct
        tileOrderAdapter.blur = pct
        tileOrderFile.writeAdapter()
        shell._syncCompositorBlur()
    }
    function saveTileBorder(on) {
        shell.tileBorder = on
        tileOrderAdapter.border = on
        tileOrderFile.writeAdapter()
    }
    function saveFocusTimers(workMin, breakMin) {
        shell.focusWorkMinutes  = workMin
        shell.focusBreakMinutes = breakMin
        tileOrderAdapter.focusWork  = workMin
        tileOrderAdapter.focusBreak = breakMin
        tileOrderFile.writeAdapter()
    }
    function saveFocusSound(on) {
        shell.focusSound = on
        tileOrderAdapter.focusSound = on
        tileOrderFile.writeAdapter()
    }
    function saveThrottleOnBattery(on) {
        shell.throttleOnBattery = on
        tileOrderAdapter.throttleOnBattery = on
        tileOrderFile.writeAdapter()
    }
    function savePauseWhenCovered(on) {
        shell.pauseWhenCovered = on
        tileOrderAdapter.pauseWhenCovered = on
        tileOrderFile.writeAdapter()
    }
    // Re-runs the one-shot nvidia-smi/sensors presence checks (SystemMetrics.qml)
    // - for after installing GPU drivers or running sensors-detect without
    // restarting the whole shell.
    function recheckHardware() { metrics.recheckHardware() }

    FileView {
        id: tileOrderFile
        path: Quickshell.stateDir + "/tile-order.json"
        watchChanges: true
        printErrors: false
        onLoaded:         shell._applyLoadedTileOrder()
        onAdapterUpdated: shell._applyLoadedTileOrder()

        JsonAdapter {
            id: tileOrderAdapter
            property var order: shell.defaultTileOrder
            property var placement: ({})
            // `hidden` and `rightPanel` are read only to migrate a
            // pre-placement file (see _loadPlacement); no longer written.
            property var hidden: []
            property bool rightPanel: true
            property string screenName: ""
            property int blur: 50
            property bool border: false
            property int focusWork: 25
            property int focusBreak: 5
            property bool focusSound: true
            property bool throttleOnBattery: true
            property bool pauseWhenCovered:  true
        }
    }

    // Writes the shared Omarchy weather location when it's changed from the
    // settings modal. A city name is geocoded first (Open-Meteo, same as the
    // Omarchy weather widget) so coordinates get stored too - that's what lets
    // both this dashboard and the bar use Open-Meteo for exact conditions.
    // WeatherService's file watch then refetches.
    property string _pendingWeatherName: ""
    function setWeatherLocation(name) {
        var n = (name || "").trim()
        if (n === "") {
            weatherLocProc.command = ["omarchy-weather-location", "--clear"]
            weatherLocProc.running = true
            return
        }
        shell._pendingWeatherName = n
        weatherGeoProc.command = ["curl", "-fsS", "--max-time", "6",
            "https://geocoding-api.open-meteo.com/v1/search?count=1&format=json&name=" + encodeURIComponent(n)]
        weatherGeoProc.running = true
    }
    Process {
        id: weatherGeoProc
        running: false
        stdout: StdioCollector {
            id: weatherGeoOut
            onStreamFinished: {
                var name = shell._pendingWeatherName
                var lat = null, lon = null
                try {
                    var r = JSON.parse(String(weatherGeoOut.text || "")).results
                    if (r && r[0] && r[0].latitude !== undefined) { lat = r[0].latitude; lon = r[0].longitude }
                } catch (e) {}
                weatherLocProc.command = (lat !== null)
                    ? ["omarchy-weather-location", "--set", name, lat + "," + lon]
                    : ["omarchy-weather-location", "--set", name]
                weatherLocProc.running = true
            }
        }
    }
    Process { id: weatherLocProc; running: false }

    Updater { id: updater; modal: reorderModal }

    // ── Helpers (at Scope level so all children can resolve them) ─
    // Theme foreground at a given alpha (defaults to fully opaque) - use
    // this instead of hardcoding white/rgba(1,1,1,x) so text follows the
    // active Omarchy theme.
    function _fg(a) {
        return Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, a === undefined ? 1 : a)
    }
    // Readable text/icon color for content sitting on theme.accent - picks
    // whichever of foreground/background contrasts more with accent.
    function _onAccent() {
        function lum(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
        var a = lum(theme.accent), f = lum(theme.foreground), b = lum(theme.background)
        return Math.abs(f - a) >= Math.abs(b - a) ? theme.foreground : theme.background
    }
    function _batTimeText() {
        if (!UPower.displayDevice) return ""
        const st = UPower.displayDevice.state
        if (st === UPowerDeviceState.FullyCharged) return ""
        if (st === UPowerDeviceState.Charging) {
            const s = UPower.displayDevice.timeToFull
            return (s && s > 0) ? _fmtBatTime(s) + " to full" : ""
        }
        if (st === UPowerDeviceState.Discharging) {
            const s = UPower.displayDevice.timeToEmpty
            return (s && s > 0) ? _fmtBatTime(s) + " remaining" : ""
        }
        return ""
    }
    function _fmtBatTime(secs) {
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }
    function _fmtNet(kbs) {
        if (kbs >= 1024) return (kbs / 1024).toFixed(1) + " MB/s"
        return Math.round(kbs) + " KB/s"
    }
    function _fmtDuration(secs) {
        if (!secs || secs < 0) return "0:00"
        const total = Math.floor(secs)
        const m = Math.floor(total / 60)
        const s = total % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    // Like _fmtDuration but always shows whole minutes (a countdown clock,
    // e.g. "25:00", "4:59") - used by the Focus tile.
    function _fmtClock(secs) {
        const total = Math.max(0, Math.floor(secs))
        const m = Math.floor(total / 60)
        const s = total % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function _pingMax() {
        var m = 50
        var h = metrics.pingHistory
        for (var i = 0; i < h.length; i++) if (h[i] > m) m = h[i]
        return m
    }
    function _netMax() {
        var m = 100
        var rx = metrics.netRxHistory, tx = metrics.netTxHistory
        for (var i = 0; i < rx.length; i++) if (rx[i] > m) m = rx[i]
        for (var i = 0; i < tx.length; i++) if (tx[i] > m) m = tx[i]
        return m
    }
    // ════════════════════════════════════════════════════════════
    //  LEFT PANEL - System Stats
    // ════════════════════════════════════════════════════════════
    PanelWindow {
        id: leftPanel

        visible:         shell.leftTiles.length > 0
        screen:          shell._mainScreen
        anchors {        top: true; left: true; bottom: true; right: false }
        implicitWidth:   tileFlow.width + 16   // 8 left + 8 right margins

        WlrLayershell.layer:         WlrLayer.Bottom
        WlrLayershell.namespace:     "quickshell:dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode:               ExclusionMode.Ignore
        color:                       "transparent"

        // Compositor-native blur via the ext-background-effect-v1 Wayland
        // protocol, requested straight from QML - no layer_rule needed.
        // leftBlurRegion is an empty container; shell._rebuildLeftBlur fills
        // its `regions` list with each tile's own Region (see leftTileRepeater
        // below), so only the card rectangles blur, not the gaps between
        // them or the panel's own margins. Hyprland still needs
        // decoration.blur.enabled on for the render pass itself - see
        // _syncCompositorBlur.
        BackgroundEffect.blurRegion: shell.blurPercent > 0 ? leftBlurRegion : null
        Region { id: leftBlurRegion }

        // ── Tile columns ──────────────────────────────────────────────
        // Column count is dynamic: tiles stack top-to-bottom until the
        // next one wouldn't fit the screen's height, then a new column
        // starts to the right. Screen height is read live from `screen`,
        // so this reflows if the dashboard ever moves to a different
        // monitor. No scrolling, no clipped/unreachable tiles.
        Flow {
            id: tileFlow
            anchors {
                top: parent.top;   topMargin:  40
                left: parent.left; leftMargin: 8
            }
            height: Math.max(1, (leftPanel.screen ? leftPanel.screen.height : 1000) - 40 - 8)
            flow: Flow.TopToBottom
            spacing: 12

            Repeater {
                id: leftTileRepeater
                model: shell.leftTiles
                onCountChanged: Qt.callLater(shell._rebuildLeftBlur)
                delegate: Item {
                    id: tileWrap
                    width: 296
                    height: tileLoader.height

                    // Exposed so shell._rebuildLeftBlur can collect just this
                    // tile's own rectangle into the panel's blur region -
                    // see the note by leftBlurRegion below.
                    property var blurRegion: tileBlurRegion
                    Region { id: tileBlurRegion; item: tileWrap; radius: 16 }

                    // Double-click the tile itself (not the empty panel
                    // around it) to open Settings. Sits behind the loaded
                    // card's own content, so any interactive control inside
                    // it (e.g. the media tile's playback buttons) still
                    // takes priority.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onDoubleClicked: reorderModal.open()
                    }

                    Loader {
                        id: tileLoader
                        width: parent.width
                        sourceComponent: shell.tileMap[modelData]
                    }
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════
    //  Tile registry - Components shared by the left and right panels
    // ════════════════════════════════════════════════════════════

                Component { id: cpuTile; CpuTile { shell: _shell } }

                Component { id: memoryTile; MemoryTile { shell: _shell } }

                Component { id: gpuTile; GpuTile { shell: _shell } }

                Component { id: batteryTile; BatteryTile { shell: _shell } }

                Component { id: diskTile; DiskTile { shell: _shell } }

                Component { id: networkTile; NetworkTile { shell: _shell } }

                Component { id: pingTile; PingTile { shell: _shell } }

                Component { id: mediaTile; MediaTile { shell: _shell } }

                Component { id: weatherTile; WeatherTile { shell: _shell } }

                Component { id: sunTile; SunTile { shell: _shell } }

                Component { id: focusTile; FocusTile { shell: _shell } }

                Component { id: systemTile; SystemTile { shell: _shell } }

    // Settings window - opened by double-clicking any tile or card.
    SettingsModal {
        id: reorderModal
        screen: shell._mainScreen
        theme: theme
        tileLabels: shell.tileLabels
        order: shell.tileOrder
        placement: shell.placement
        defaultPlacement: shell.defaultPlacement
        screens: Quickshell.screens
        overrideScreenName: shell.screenName
        activeScreenName: shell._mainScreen ? shell._mainScreen.name : ""
        blurPercent: shell.blurPercent
        borderEnabled: shell.tileBorder
        weatherLocation: weather.locName
        workMinutes: shell.focusWorkMinutes
        breakMinutes: shell.focusBreakMinutes
        focusSoundEnabled: shell.focusSound
        versionName: updater.verName
        versionSubject: updater.verSubject
        versionDate: updater.verDate
        repoWeb: updater.repoWeb
        throttleOnBattery: shell.throttleOnBattery
        pauseWhenCovered:  shell.pauseWhenCovered
        gpuAvailable:      metrics.gpuAvailable
        sensorsAvailable:  metrics.sensorsAvailable
        dashboardCovered:  shell._dashboardCovered
        onBattery:         shell._onBattery
        onPlacementEdited: (o, p) => shell.savePlacement(o, p)
        onScreenEdited: name => shell.saveScreenName(name)
        onBlurEdited: pct => shell.saveBlurPercent(pct)
        onBorderEdited: on => shell.saveTileBorder(on)
        onWeatherLocationEdited: name => shell.setWeatherLocation(name)
        onFocusTimersEdited: (work, brk) => shell.saveFocusTimers(work, brk)
        onFocusSoundEdited: on => shell.saveFocusSound(on)
        onUpdateCheckRequested: updater.checkForUpdate()
        onUpdateRunRequested: updater.runUpdate()
        onThrottleOnBatteryEdited: on => shell.saveThrottleOnBattery(on)
        onPauseWhenCoveredEdited: on => shell.savePauseWhenCovered(on)
        onRecheckHardwareRequested: shell.recheckHardware()
    }

    // ════════════════════════════════════════════════════════════
    //  RIGHT PANEL - user-placed tiles on the right screen edge
    // ════════════════════════════════════════════════════════════
    // Mirror of the left panel: tiles stack top-to-bottom and overflow
    // into a new column toward screen centre. Shown only when at least
    // one tile is assigned to the right edge (Settings → Layout).
    PanelWindow {
        id: rightPanel

        visible:         shell.rightTiles.length > 0
        screen:          shell._mainScreen
        anchors {        top: true; right: true; bottom: true }
        implicitWidth:   rightFlow.width + 16

        WlrLayershell.layer:         WlrLayer.Bottom
        WlrLayershell.namespace:     "quickshell:dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode:               ExclusionMode.Ignore
        color:                       "transparent"

        // Mirror of leftPanel's blur setup - see the comment there.
        BackgroundEffect.blurRegion: shell.blurPercent > 0 ? rightBlurRegion : null
        Region { id: rightBlurRegion }

        Flow {
            id: rightFlow
            anchors {
                top: parent.top;     topMargin:   40
                right: parent.right; rightMargin: 8
            }
            height: Math.max(1, (rightPanel.screen ? rightPanel.screen.height : 1000) - 40 - 8)
            flow: Flow.TopToBottom
            spacing: 12
            // Mirror the layout direction so the first column hugs the
            // screen edge (like the left panel) and extra columns grow
            // inward. Only the Flow itself is mirrored, not tile content.
            LayoutMirroring.enabled: true
            LayoutMirroring.childrenInherit: false

            Repeater {
                id: rightTileRepeater
                model: shell.rightTiles
                onCountChanged: Qt.callLater(shell._rebuildRightBlur)
                delegate: Item {
                    id: rTileWrap
                    width: 296
                    height: rTileLoader.height

                    property var blurRegion: rTileBlurRegion
                    Region { id: rTileBlurRegion; item: rTileWrap; radius: 16 }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onDoubleClicked: reorderModal.open()
                    }

                    Loader {
                        id: rTileLoader
                        width: parent.width
                        sourceComponent: shell.tileMap[modelData]
                    }
                }
            }
        }
    }
}
