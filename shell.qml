import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Qt5Compat.GraphicalEffects

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

    // Shared metrics (accessible from both panels by id)
    SystemMetrics { id: metrics; pingHost: config.pingHost }

    // Shared weather data for the Weather and Sun tiles. Location comes from
    // Omarchy's own weather setting (see WeatherService.qml).
    WeatherService { id: weather }

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
    // Glass-card opacity, chosen in the modal's BLUR picker. Stored as a
    // percentage (one of 0/25/50/75/100); the on-screen alpha is derived
    // via _blurAlphaFor. 50 = 0.5 = the previous hardcoded default.
    property int blurPercent: 50
    readonly property real blurAlpha: shell._blurAlphaFor(shell.blurPercent)
    function _blurAlphaFor(pct) {
        switch (pct) {
            case 0:   return 0.0    // fully transparent - compositor blur is skipped too, see _syncCompositorBlur
            case 25:  return 0.3
            case 75:  return 0.75
            case 100: return 1.0
            default:  return 0.5    // Medium / unknown
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
    // in sync with the BLUR picker - re-asserted at startup and on every
    // change - rather than set once, and turned back off when the user
    // picks "Transparent".
    function _syncCompositorBlur() {
        var on = shell.blurPercent > 0
        compositorBlurProc.command = ["hyprctl", "dispatch",
            "hl.config({decoration={blur={enabled=" + (on ? "true" : "false") + ",size=6,passes=3}}})"]
        compositorBlurProc.running = true
    }
    Process { id: compositorBlurProc; running: false }
    // Whether the glass cards draw a hairline outline. Chosen in the
    // modal's BORDER toggle; off by default.
    property bool tileBorder: false
    // Focus tile work/break lengths (minutes), edited via the cog on the tile.
    property int focusWorkMinutes: 25
    property int focusBreakMinutes: 5
    // Whether the Focus tile plays a chime when a period ends. Toggled by the
    // bell on the tile and on the modal's Focus Timer page.
    property bool focusSound: true

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

    // ── Updater ─────────────────────────────────────────────────────
    // Backs the settings modal's About page. It tracks tagged releases on
    // GitHub (vX.Y.Z), not raw `main`. The check is read-only git run from
    // here; the update itself - fast-forward `main` to the newest release
    // tag, then a full install.sh re-run (deps, autostart, blur) - runs in a
    // detached terminal via omarchy-launch-terminal, so it survives the
    // hot-reload the new files trigger. install.sh needs a password for the
    // package installs. `-c core.hooksPath=/dev/null` keeps a tampered
    // .git/hooks from running during any of it; `--ff-only` blocks history
    // rewrites and rollbacks. See RELEASING.md for how tags are published.
    readonly property string _repoDir:   Quickshell.env("HOME") + "/.config/quickshell/dashboard"
    readonly property string _repoHttps: "https://github.com/D3m0nZOnFire/omarchy-dashboard.git"
    readonly property string _repoWeb:   "https://github.com/D3m0nZOnFire/omarchy-dashboard"
    // Shared by the check and the update: newest vX.Y.Z tag, newest first.
    readonly property string _tagPick:
        "git tag -l --sort=-v:refname | grep -E '^v[0-9]+\\.[0-9]+\\.[0-9]+$' | head -n1"

    property string verName: ""      // installed release, e.g. "v1.0.0" (git describe)
    property string verSubject: ""
    property string verDate: ""

    function _readVersion() { versionProc.running = true }
    function checkForUpdate() {
        if (reorderModal.updateState === "checking" || reorderModal.updateState === "launching") return
        reorderModal.updateError = ""
        reorderModal.updateState = "checking"
        checkProc.running = true
    }
    function runUpdate() {
        if (reorderModal.updateState === "checking" || reorderModal.updateState === "launching") return
        reorderModal.updateError = ""
        reorderModal.updateState = "checking"
        statusProc.running = true
    }
    function _lines(s) {
        return String(s || "").split("\n").filter(function(l) { return l.trim() !== "" })
    }

    // Installed version line: `git describe` + the tip commit's subject / age.
    Process {
        id: versionProc
        running: false
        command: ["bash", "-c",
            "d=$1; git -C \"$d\" describe --tags --always 2>/dev/null || echo '?'; "
            + "git -C \"$d\" log -1 --format=%s%x1f%cr",
            "_", shell._repoDir]
        stdout: StdioCollector {
            id: versionOut
            onStreamFinished: {
                var ls = shell._lines(versionOut.text)
                shell.verName = ls[0] || "?"
                var meta = String(ls[1] || "").split("\x1f")
                shell.verSubject = meta[0] || ""
                shell.verDate    = meta[1] || ""
            }
        }
    }

    // ── check: fetch tags, report installed vs newest release + changelog ──
    // Output is line-prefixed so a partial read can't be misparsed:
    //   err-network        fetch failed
    //   cur <tag|>         nearest release tag reachable from HEAD
    //   new <tag|>         newest vX.Y.Z tag on the remote
    //   log <subject>      one per commit between cur and new
    Process {
        id: checkProc
        running: false
        command: ["bash", "-c",
            "d=$1; url=$2; "
            + "git -C \"$d\" -c core.hooksPath=/dev/null fetch --tags --quiet \"$url\" || { echo err-network; exit 0; }; "
            + "cur=$(git -C \"$d\" describe --tags --abbrev=0 2>/dev/null || true); "
            + "new=$(cd \"$d\" && " + shell._tagPick + "); "
            + "echo \"cur $cur\"; echo \"new $new\"; "
            + "if [ -n \"$new\" ] && [ \"$cur\" != \"$new\" ]; then "
            + "git -C \"$d\" log --format='log %s' \"${cur:+$cur..}$new\"; fi",
            "_", shell._repoDir, shell._repoHttps]
        stdout: StdioCollector {
            id: checkOut
            onStreamFinished: {
                var cur = "", neu = "", log = [], net = true
                shell._lines(checkOut.text).forEach(function(l) {
                    if (l === "err-network") net = false
                    else if (l.indexOf("cur ") === 0) cur = l.slice(4).trim()
                    else if (l.indexOf("new ") === 0) neu = l.slice(4).trim()
                    else if (l.indexOf("log ") === 0) log.push(l.slice(4))
                })
                if (!net) {
                    reorderModal.updateError = "Couldn't reach GitHub. Check your connection and retry."
                    reorderModal.updateState = "error"
                    return
                }
                reorderModal.latestVersion = neu
                reorderModal.incomingLog = log
                reorderModal.commitsBehind = log.length
                reorderModal.updateState = (neu !== "" && neu !== cur) ? "available" : "uptodate"
            }
        }
    }

    // ── run flow: dirty guard, then hand off to a detached terminal ──
    Process {
        id: statusProc
        running: false
        command: ["git", "-c", "core.hooksPath=/dev/null",
                  "-C", shell._repoDir, "status", "--porcelain", "--untracked-files=no"]
        stdout: StdioCollector {
            id: statusOut
            onStreamFinished: {
                var lines = shell._lines(statusOut.text)
                if (lines.length > 0) {
                    reorderModal.dirtyFiles = lines.map(function(l) { return l.slice(3) })
                    reorderModal.updateState = "dirty"
                    return
                }
                reorderModal.updateState = "launching"
                termProc.running = true
            }
        }
    }
    // The whole update, in a terminal that outlives this shell's hot-reload:
    // fetch tags over HTTPS, fast-forward `main` to the newest release tag,
    // then install.sh for deps + autostart + blur. The prompt stays open on
    // a `read` so the result is visible.
    Process {
        id: termProc
        running: false
        command: ["omarchy-launch-terminal", "bash", "-c",
            "d=$1; url=$2; cd \"$d\" || exit 1; "
            + "git -c core.hooksPath=/dev/null fetch --tags --quiet \"$url\" && "
            + "tag=$(" + shell._tagPick + ") && [ -n \"$tag\" ] && "
            + "echo \"Updating to $tag\" && "
            + "git -c core.hooksPath=/dev/null merge --ff-only \"$tag\" && "
            + "./install.sh; "
            + "ec=$?; echo; read -rp \"Update finished (exit $ec) - press Enter to close \" _",
            "_", shell._repoDir, shell._repoHttps]
    }

    Component.onCompleted: shell._readVersion()

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

                // ── CPU ──────────────────────────────────────────────
                Component { id: cpuTile; StatCard {
                    label: "CPU" + (metrics.cpuModel ? " · " + metrics.cpuModel : "")
                    theme: shell._theme
                    Layout.fillWidth: true

                    // Main row: ring + stats + sparkline
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RingChart {
                            textColor: theme.foreground
                            trackColor: _fg(0.08)
                            value:     metrics.cpuPercent
                            fillColor: metrics.cpuPercent > 95 ? theme.red
                                     : metrics.cpuPercent > 80 ? theme.orange : theme.blue
                            subText:   metrics.cpuPackageTemp > 0 ? metrics.cpuPackageTemp.toFixed(0) + "°C" : ""
                            width: 72; height: 72
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text:           Math.round(metrics.cpuPercent) + "%"
                                color:          _fg()
                                font.pixelSize: 20
                                font.weight:    Font.Light
                            }
                            Text {
                                text:           "Max core: " + metrics.cpuMaxCoreTemp.toFixed(0) + "°C"
                                color:          _fg(0.35)
                                font.pixelSize: 9
                                visible:        metrics.cpuMaxCoreTemp > 0
                            }
                            SparkLine {
                                Layout.fillWidth: true
                                values:    metrics.cpuHistory
                                lineColor: metrics.cpuPercent > 80 ? theme.orange : theme.blue
                            }
                        }
                    }

                    // Per-core bars (Canvas)
                    Canvas {
                        id: coreBarsCanvas
                        Layout.fillWidth: true
                        height: 28
                        property var data: metrics.corePercents
                        // Bound (not read directly in onPaint) so the canvas
                        // repaints automatically when the theme changes.
                        property color colorLow:  theme.blue
                        property color colorMid:  theme.orange
                        property color colorHigh: theme.red
                        property color colorTrack: _fg(0.07)
                        onDataChanged:      requestPaint()
                        onWidthChanged:      requestPaint()
                        onColorLowChanged:   requestPaint()
                        onColorMidChanged:   requestPaint()
                        onColorHighChanged:  requestPaint()
                        onColorTrackChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const cores = data
                            if (!cores || cores.length === 0) return
                            const n    = cores.length
                            const gap  = 2
                            const barW = Math.max(2, Math.floor((width - (n - 1) * gap) / n))
                            for (let i = 0; i < n; i++) {
                                const v = cores[i] || 0
                                const x = i * (barW + gap)
                                // Background track
                                ctx.fillStyle = colorTrack
                                ctx.fillRect(x, 0, barW, height)
                                // Value fill from bottom
                                if (v > 0) {
                                    const h = Math.max(2, v / 100 * height)
                                    ctx.fillStyle = v > 80 ? colorHigh : v > 50 ? colorMid : colorLow
                                    ctx.fillRect(x, height - h, barW, h)
                                }
                            }
                        }
                    }
                } }

                // ── MEMORY ───────────────────────────────────────────
                Component { id: memoryTile; StatCard {
                    label: "Memory"
                    theme: shell._theme
                    Layout.fillWidth: true

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RingChart {
                            textColor: theme.foreground
                            trackColor: _fg(0.08)
                            value:     metrics.ramPercent
                            fillColor: metrics.ramPercent > 90 ? theme.red
                                     : metrics.ramPercent > 75 ? theme.orange : theme.accent
                            width: 72; height: 72
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text:           metrics.ramUsedGB.toFixed(1) + " GB"
                                color:          _fg()
                                font.pixelSize: 20
                                font.weight:    Font.Light
                            }
                            Text {
                                text:           "of " + metrics.ramTotalGB.toFixed(0) + " GB"
                                color:          _fg(0.35)
                                font.pixelSize: 9
                            }
                            SparkLine {
                                Layout.fillWidth: true
                                values:    metrics.ramHistory
                                lineColor: theme.accent
                            }
                        }
                    }
                } }

                // ── GPU ──────────────────────────────────────────────
                Component { id: gpuTile; StatCard {
                    label: "GPU" + (metrics.gpuName ? " · " + metrics.gpuName : "")
                    theme: shell._theme
                    Layout.fillWidth: true

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RingChart {
                            textColor: theme.foreground
                            trackColor: _fg(0.08)
                            value:     metrics.gpuPercent
                            fillColor: metrics.gpuPercent > 90 ? theme.red
                                     : metrics.gpuPercent > 70 ? theme.orange : theme.accent
                            subText:   metrics.gpuTempC + "°C"
                            width: 72; height: 72
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text:           metrics.gpuPercent + "%"
                                color:          _fg()
                                font.pixelSize: 20
                                font.weight:    Font.Light
                            }
                            Text {
                                text:           metrics.vramUsedMB + " / " + metrics.vramTotalMB + " MB"
                                color:          _fg(0.35)
                                font.pixelSize: 9
                            }
                            Text {
                                text:           metrics.gpuPowerW.toFixed(0) + " W"
                                color:          _fg(0.5)
                                font.pixelSize: 11
                                font.weight:    Font.Medium
                            }
                            SparkLine {
                                Layout.fillWidth: true
                                values:    metrics.gpuHistory
                                lineColor: theme.accent
                            }
                        }
                    }
                } }

                // ── BATTERY ──────────────────────────────────────────
                Component { id: batteryTile; StatCard {
                    label: "Battery"
                    theme: shell._theme
                    Layout.fillWidth: true
                    visible: UPower.displayDevice !== null

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        RingChart {
                            textColor: theme.foreground
                            trackColor: _fg(0.08)
                            value: UPower.displayDevice
                                   ? UPower.displayDevice.percentage * 100 : 0
                            fillColor: {
                                if (!UPower.displayDevice) return theme.blue
                                const pct = UPower.displayDevice.percentage * 100
                                const st  = UPower.displayDevice.state
                                if (st === UPowerDeviceState.Charging ||
                                    st === UPowerDeviceState.FullyCharged) return theme.accent
                                if (pct > 40) return theme.blue
                                if (pct > 20) return theme.orange
                                return theme.red
                            }
                            width: 72; height: 72
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: {
                                    if (!UPower.displayDevice) return "-"
                                    const st = UPower.displayDevice.state
                                    if (st === UPowerDeviceState.FullyCharged) return "Full"
                                    if (st === UPowerDeviceState.Charging)     return "Charging"
                                    if (st === UPowerDeviceState.Discharging)  return "Discharging"
                                    return "-"
                                }
                                color: {
                                    if (!UPower.displayDevice) return _fg(0.65)
                                    const st = UPower.displayDevice.state
                                    if (st === UPowerDeviceState.FullyCharged ||
                                        st === UPowerDeviceState.Charging) return theme.accent
                                    return _fg()
                                }
                                font.pixelSize: 13
                                font.weight:    Font.Medium
                            }

                            Text {
                                visible: UPower.displayDevice !== null && _batTimeText() !== ""
                                text:    _batTimeText()
                                color:   _fg(0.5)
                                font.pixelSize: 10
                            }

                            Text {
                                visible: UPower.displayDevice !== null &&
                                         UPower.displayDevice.changeRate > 0
                                text:    (UPower.displayDevice
                                          ? UPower.displayDevice.changeRate : 0).toFixed(1) + " W"
                                color:   _fg(0.35)
                                font.pixelSize: 9
                            }
                        }
                    }
                } }

                // ── DISK ─────────────────────────────────────────────
                Component { id: diskTile; StatCard {
                    label: "Disk  /"
                    theme: shell._theme
                    Layout.fillWidth: true

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        RingChart {
                            textColor: theme.foreground
                            trackColor: _fg(0.08)
                            value:     metrics.diskPercent
                            fillColor: metrics.diskPercent > 90 ? theme.red
                                     : metrics.diskPercent > 75 ? theme.orange : theme.accent
                            width: 72; height: 72
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text:           metrics.diskUsedGB.toFixed(0) + " GB"
                                color:          _fg()
                                font.pixelSize: 20
                                font.weight:    Font.Light
                            }
                            Text {
                                text:           "of " + metrics.diskTotalGB.toFixed(0) + " GB · " + metrics.diskPercent + "%"
                                color:          _fg(0.35)
                                font.pixelSize: 9
                            }
                        }
                    }
                } }

                // ── NETWORK ──────────────────────────────────────────
                Component { id: networkTile; StatCard {
                    label: "Network"
                    theme: shell._theme
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text:"↓  RX"; color:_fg(0.35); font.pixelSize:9 }
                                Text {
                                    text:           _fmtNet(metrics.netRxKBs)
                                    color:          theme.blue
                                    font.pixelSize: 14
                                    font.weight:    Font.Medium
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Text { text:"↑  TX"; color:_fg(0.35); font.pixelSize:9 }
                                Text {
                                    text:           _fmtNet(metrics.netTxKBs)
                                    color:          theme.orange
                                    font.pixelSize: 14
                                    font.weight:    Font.Medium
                                }
                            }
                        }
                        SparkLine {
                            Layout.fillWidth: true
                            values:     metrics.netRxHistory
                            values2:    metrics.netTxHistory
                            maxValue:   _netMax()
                            lineColor:  theme.blue
                            lineColor2: theme.orange
                        }
                    }
                } }

                // ── PING ─────────────────────────────────────────────
                Component { id: pingTile; StatCard {
                    label: "Ping · " + config.pingHost
                    theme: shell._theme
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: metrics.pingMs < 0   ? theme.red
                                     : metrics.pingMs < 30  ? theme.accent
                                     : metrics.pingMs < 100 ? theme.orange : theme.red
                            }
                            Text {
                                text: metrics.pingMs < 0 ? "Timeout"
                                    : metrics.pingMs.toFixed(1) + " ms"
                                color: metrics.pingMs < 0   ? _fg(0.35)
                                     : metrics.pingMs < 30  ? theme.accent
                                     : metrics.pingMs < 100 ? theme.orange : theme.red
                                font.pixelSize: 16
                                font.weight:    Font.Medium
                            }
                            Item { Layout.fillWidth: true }
                        }
                        SparkLine {
                            Layout.fillWidth: true
                            values:    metrics.pingHistory
                            maxValue:  _pingMax()
                            lineColor: metrics.pingMs < 0   ? theme.red
                                     : metrics.pingMs < 30  ? theme.accent
                                     : metrics.pingMs < 100 ? theme.orange : theme.red
                        }
                    }
                } }

                // ── MEDIA (MPRIS "Now Playing") ───────────────────────
                Component { id: mediaTile; StatCard {
                    id: mediaCard
                    theme: shell._theme
                    Layout.fillWidth: true

                    // Bumped whenever the player list or a player's playing
                    // state changes, to force activePlayer to re-pick - see
                    // the Connections/Instantiator below. Per-track fields
                    // (title, position, art, ...) update on their own via
                    // normal property bindings once a player is selected.
                    property int _mpTick: 0
                    property var activePlayer: {
                        _mpTick
                        const list = Mpris.players ? Mpris.players.values : []
                        for (var i = 0; i < list.length; i++) if (list[i].isPlaying) return list[i]
                        for (var i = 0; i < list.length; i++) if (list[i].trackTitle) return list[i]
                        return null
                    }
                    readonly property bool hasMedia: activePlayer !== null &&
                        (activePlayer.trackTitle !== "" || activePlayer.trackArtist !== "")

                    label: "Media" + (hasMedia && activePlayer.identity ? " · " + activePlayer.identity : "")

                    // `Mpris.players` is a constant model reference (no
                    // playersChanged signal) - a player appearing/disappearing
                    // is instead caught by this delegate's own creation/
                    // destruction, alongside isPlaying flips on existing ones.
                    Instantiator {
                        model: Mpris.players
                        delegate: Connections {
                            required property var modelData
                            target: modelData
                            function onIsPlayingChanged() { if (mediaCard) mediaCard._mpTick++ }
                            Component.onCompleted: { if (mediaCard) mediaCard._mpTick++ }
                            // Guarded: if the whole tile is being torn down
                            // (e.g. hidden via the reorder modal), mediaCard
                            // may already be gone by the time this fires.
                            Component.onDestruction: { if (mediaCard) mediaCard._mpTick++ }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: !mediaCard.hasMedia
                        text: "Nothing playing"
                        color: _fg(0.35)
                        font.pixelSize: 12
                        font.italic: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: mediaCard.hasMedia
                        spacing: 10

                        ClippingRectangle {
                            width: 56; height: 56
                            radius: 8
                            color: _fg(0.06)

                            Image {
                                anchors.fill: parent
                                source: mediaCard.activePlayer && mediaCard.activePlayer.trackArtUrl ? mediaCard.activePlayer.trackArtUrl : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !(mediaCard.activePlayer && mediaCard.activePlayer.trackArtUrl)
                                text: "♪"
                                color: _fg(0.25)
                                font.pixelSize: 22
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                text: mediaCard.activePlayer ? (mediaCard.activePlayer.trackTitle || "-") : ""
                                color: _fg()
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: mediaCard.activePlayer ? (mediaCard.activePlayer.trackArtist || "") : ""
                                color: _fg(0.5)
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                height: 3
                                Rectangle { anchors.fill: parent; radius: 1.5; color: _fg(0.1) }
                                Rectangle {
                                    readonly property real ratio: mediaCard.activePlayer && mediaCard.activePlayer.length > 0
                                        ? mediaCard.activePlayer.position / mediaCard.activePlayer.length : 0
                                    width: parent.width * Math.max(0, Math.min(1, ratio))
                                    height: parent.height
                                    radius: 1.5
                                    color: theme.accent
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: mediaCard.activePlayer ? _fmtDuration(mediaCard.activePlayer.position) : ""
                                    color: _fg(0.35)
                                    font.pixelSize: 9
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: mediaCard.activePlayer && mediaCard.activePlayer.length > 0 ? _fmtDuration(mediaCard.activePlayer.length) : ""
                                    color: _fg(0.35)
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: mediaCard.hasMedia
                        spacing: 20

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "◀◀"
                            font.pixelSize: 12
                            color: mediaCard.activePlayer && mediaCard.activePlayer.canGoPrevious ? _fg(0.8) : _fg(0.2)
                            MouseArea {
                                anchors { fill: parent; margins: -6 }
                                enabled: mediaCard.activePlayer && mediaCard.activePlayer.canGoPrevious
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mediaCard.activePlayer.previous()
                            }
                        }
                        Item {
                            // Drawn instead of using the "⏸" glyph - that
                            // codepoint defaults to colored emoji presentation
                            // on most systems, clashing with the plain-text
                            // triangles used everywhere else on this tile.
                            width: 15; height: 15
                            Text {
                                anchors.centerIn: parent
                                visible: !(mediaCard.activePlayer && mediaCard.activePlayer.isPlaying)
                                text: "▶"
                                font.pixelSize: 15
                                color: _fg(0.9)
                            }
                            Row {
                                anchors.centerIn: parent
                                visible: mediaCard.activePlayer && mediaCard.activePlayer.isPlaying
                                spacing: 3
                                Rectangle { width: 4; height: 13; radius: 1; color: _fg(0.9) }
                                Rectangle { width: 4; height: 13; radius: 1; color: _fg(0.9) }
                            }
                            MouseArea {
                                anchors { fill: parent; margins: -6 }
                                enabled: mediaCard.activePlayer && mediaCard.activePlayer.canTogglePlaying
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mediaCard.activePlayer.togglePlaying()
                            }
                        }
                        Text {
                            text: "▶▶"
                            font.pixelSize: 12
                            color: mediaCard.activePlayer && mediaCard.activePlayer.canGoNext ? _fg(0.8) : _fg(0.2)
                            MouseArea {
                                anchors { fill: parent; margins: -6 }
                                enabled: mediaCard.activePlayer && mediaCard.activePlayer.canGoNext
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mediaCard.activePlayer.next()
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                } }

                // ── WEATHER (wttr.in - shares Omarchy's location) ─────
                Component { id: weatherTile; StatCard {
                    label: "Weather"
                    theme: shell._theme
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        visible: !weather.ready
                        text: "Fetching weather…"
                        color: _fg(0.35)
                        font.pixelSize: 12
                        font.italic: true
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: weather.ready
                        spacing: 12

                        // Same Nerd Font weather glyph the Omarchy bar uses,
                        // in the accent colour.
                        Text {
                            text: weather.iconGlyph
                            font.family: theme.monoFamily
                            font.pixelSize: 38
                            color: theme.accent
                            Layout.alignment: Qt.AlignVCenter
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                text:        weather.tempC + "°"
                                color:       _fg()
                                font.pixelSize: 32
                                font.weight: Font.Light
                            }
                            Text {
                                Layout.fillWidth: true
                                text:  weather.displayLocation.toUpperCase()
                                color: _fg(0.5)
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Layout.bottomMargin: 2
                        visible: weather.ready
                        height: 1
                        color: _fg(0.1)
                    }

                    // FEELS / WIND / HUMID - same labels and formats as the bar.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: weather.ready
                        Text { text: "FEELS"; color: _fg(0.4); font.pixelSize: 9; font.letterSpacing: 1 }
                        Item { Layout.fillWidth: true }
                        Text { text: weather.feelsC + "°"; color: _fg(); font.pixelSize: 11 }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: weather.ready
                        Text { text: "WIND"; color: _fg(0.4); font.pixelSize: 9; font.letterSpacing: 1 }
                        Item { Layout.fillWidth: true }
                        Text { text: weather.windKmph + " km/h"; color: _fg(); font.pixelSize: 11 }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: weather.ready
                        Text { text: "HUMID"; color: _fg(0.4); font.pixelSize: 9; font.letterSpacing: 1 }
                        Item { Layout.fillWidth: true }
                        Text { text: weather.humidity + "%"; color: _fg(); font.pixelSize: 11 }
                    }
                } }

                // ── SUN (sunrise / sunset arc) ───────────────────────
                Component { id: sunTile; StatCard {
                    label: weather.isDay ? "Sunset" : "Sunrise"
                    theme: shell._theme
                    Layout.fillWidth: true

                    Text {
                        Layout.fillWidth: true
                        visible: !weather.ready
                        text: "Fetching…"
                        color: _fg(0.35)
                        font.pixelSize: 12
                        font.italic: true
                    }

                    Text {
                        visible: weather.ready
                        text:  weather.isDay ? weather.sunsetStr : weather.sunriseStr
                        color: _fg()
                        font.pixelSize: 26
                        font.weight: Font.Light
                    }

                    SunArc {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 84
                        Layout.topMargin: 2
                        visible:  weather.ready
                        sunrise:  weather.sunriseDate
                        sunset:   weather.sunsetDate
                        now:      weather.now
                        arcColor:  _fg(0.22)
                        lineColor: _fg(0.13)
                        sunColor:  theme.accent
                    }

                    Text {
                        visible: weather.ready
                        text:  (weather.isDay ? "Sunrise: " : "Sunset: ")
                               + (weather.isDay ? weather.sunriseStr : weather.sunsetStr)
                        color: _fg(0.5)
                        font.pixelSize: 11
                    }
                } }

                // ── FOCUS (pomodoro timer) ──────────────────────────
                Component { id: focusTile; StatCard {
                    id: focusCard
                    label: "Focus"
                    theme: shell._theme
                    Layout.fillWidth: true

                    // Label-row controls - a chime toggle (bell) and the
                    // settings cog. Both appear only while the pointer is
                    // over the Focus tile.
                    headerAccessory: Component {
                        Row {
                            spacing: 9

                            // ── Chime on/off ──
                            Item {
                                implicitWidth: 13; implicitHeight: 13
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: (focusCard.hovered || bellArea.containsMouse) ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                Image {
                                    id: bellImg
                                    anchors.fill: parent
                                    source: Qt.resolvedUrl(shell.focusSound ? "assets/bell.svg" : "assets/bell-off.svg")
                                    sourceSize: Qt.size(26, 26)
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: bellImg
                                    source: bellImg
                                    color: bellArea.containsMouse ? _fg(0.95)
                                         : _fg(shell.focusSound ? 0.55 : 0.35)
                                }
                                MouseArea {
                                    id: bellArea
                                    anchors { fill: parent; margins: -6 }
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: shell.saveFocusSound(!shell.focusSound)
                                }
                            }

                            // ── Settings cog ──
                            Item {
                                implicitWidth: 13; implicitHeight: 13
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: (focusCard.hovered || cogArea.containsMouse) ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                Image {
                                    id: cogImg
                                    anchors.fill: parent
                                    source: Qt.resolvedUrl("assets/cog.svg")
                                    sourceSize: Qt.size(26, 26)
                                    fillMode: Image.PreserveAspectFit
                                    visible: false
                                }
                                ColorOverlay {
                                    anchors.fill: cogImg
                                    source: cogImg
                                    color: cogArea.containsMouse ? _fg(0.95) : _fg(0.4)
                                }
                                MouseArea {
                                    id: cogArea
                                    anchors { fill: parent; margins: -6 }
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: reorderModal.open("focus")
                                }
                            }
                        }
                    }

                    property int  mode: 0            // 0 = work, 1 = break
                    property bool running: false
                    property int  remaining: shell.focusWorkMinutes * 60

                    function _lenFor(m) {
                        return (m === 0 ? shell.focusWorkMinutes : shell.focusBreakMinutes) * 60
                    }
                    function _advance() {
                        focusCard.mode = focusCard.mode === 0 ? 1 : 0
                        focusCard.remaining = focusCard._lenFor(focusCard.mode)
                    }
                    function _reset() {
                        focusCard.running = false
                        focusCard.mode = 0
                        focusCard.remaining = focusCard._lenFor(0)
                    }
                    // Omarchy-style desktop notification when a period runs out
                    // (bell glyph U+F088C, same as `omarchy reminder`).
                    function _notifyEnd() {
                        var finishedWork = focusCard.mode === 0
                        notifyProc.command = [
                            "omarchy-notification-send", "-u", "normal",
                            "-g", String.fromCodePoint(0xF088C),
                            finishedWork ? "Break time" : "Back to work",
                            finishedWork
                                ? (shell.focusWorkMinutes + "-min focus session done - take a "
                                   + shell.focusBreakMinutes + "-min break.")
                                : (shell.focusBreakMinutes + "-min break over - starting a "
                                   + shell.focusWorkMinutes + "-min session.")
                        ]
                        notifyProc.running = true
                    }
                    Process { id: notifyProc; running: false }

                    // Chime when a period ends, if enabled. The freedesktop
                    // "complete" sound at 80% (paplay volume is 0-65536).
                    Process { id: chimeProc; running: false }
                    function _chime() {
                        if (!shell.focusSound) return
                        chimeProc.running = false
                        chimeProc.command = ["paplay", "--volume=52429",
                            "/usr/share/sounds/freedesktop/stereo/complete.oga"]
                        chimeProc.running = true
                    }

                    // Pick up length changes from the settings modal when the
                    // matching period is idle and untouched.
                    Connections {
                        target: shell
                        function onFocusWorkMinutesChanged() {
                            if (!focusCard.running && focusCard.mode === 0)
                                focusCard.remaining = focusCard._lenFor(0)
                        }
                        function onFocusBreakMinutesChanged() {
                            if (!focusCard.running && focusCard.mode === 1)
                                focusCard.remaining = focusCard._lenFor(1)
                        }
                    }

                    Timer {
                        interval: 1000
                        repeat: true
                        running: focusCard.running
                        onTriggered: {
                            focusCard.remaining -= 1
                            if (focusCard.remaining <= 0) {
                                focusCard._chime()
                                focusCard._notifyEnd()
                                focusCard._advance()
                            }
                        }
                    }

                    // Timer readout - click to start/pause.
                    Text {
                        text:  shell._fmtClock(focusCard.remaining)
                        color: _fg()
                        font.pixelSize: 32
                        font.weight: Font.Medium
                        MouseArea {
                            anchors { fill: parent; margins: -8 }
                            cursorShape: Qt.PointingHandCursor
                            onClicked: focusCard.running = !focusCard.running
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: focusCard.mode === 0 ? "WORK SESSION" : "BREAK"
                        color: _fg(0.5)
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }

                    // ── Timer controls ──────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 8

                        Rectangle {
                            Layout.preferredWidth: 78
                            Layout.preferredHeight: 26
                            radius: 8
                            color: startArea.containsMouse
                                   ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.82)
                                   : theme.accent
                            Text {
                                anchors.centerIn: parent
                                text: focusCard.running ? "PAUSE" : "START"
                                color: shell._onAccent()
                                font.pixelSize: 10
                                font.letterSpacing: 1.5
                                font.weight: Font.Bold
                            }
                            MouseArea {
                                id: startArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: focusCard.running = !focusCard.running
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 26
                            radius: 8
                            color: resetArea.containsMouse ? _fg(0.13) : _fg(0.06)
                            border.width: 1
                            border.color: _fg(0.12)
                            Text {
                                anchors.centerIn: parent
                                text: "RESET"
                                color: _fg(0.7)
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                            MouseArea {
                                id: resetArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: focusCard._reset()
                            }
                        }
                        Rectangle {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 26
                            radius: 8
                            color: skipArea.containsMouse ? _fg(0.13) : _fg(0.06)
                            border.width: 1
                            border.color: _fg(0.12)
                            Text {
                                anchors.centerIn: parent
                                text: "SKIP"
                                color: _fg(0.7)
                                font.pixelSize: 9
                                font.letterSpacing: 1
                            }
                            MouseArea {
                                id: skipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: focusCard._advance()
                            }
                        }
                        Item { Layout.fillWidth: true }
                    }
                } }

                // ── SYSTEM (neofetch-style host info) ─────────────────
                Component { id: systemTile; StatCard {
                    label: "System"
                    theme: shell._theme
                    Layout.fillWidth: true

                    SysInfoWidget {
                        Layout.fillWidth: true
                        ramInfo: metrics.ramTotalGB.toFixed(0) + " GB"
                        gpuInfo: metrics.gpuName || "-"
                        accentColor: theme.accent
                        textColor: theme.foreground
                    }
                } }

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
        versionName: shell.verName
        versionSubject: shell.verSubject
        versionDate: shell.verDate
        repoWeb: shell._repoWeb
        onPlacementEdited: (o, p) => shell.savePlacement(o, p)
        onScreenEdited: name => shell.saveScreenName(name)
        onBlurEdited: pct => shell.saveBlurPercent(pct)
        onBorderEdited: on => shell.saveTileBorder(on)
        onWeatherLocationEdited: name => shell.setWeatherLocation(name)
        onFocusTimersEdited: (work, brk) => shell.saveFocusTimers(work, brk)
        onFocusSoundEdited: on => shell.saveFocusSound(on)
        onUpdateCheckRequested: shell.checkForUpdate()
        onUpdateRunRequested: shell.runUpdate()
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
