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

    // ── Tile order - which stat tiles show, and in what order ──────
    // Persisted to disk so a drag-reorder (via double-click → modal)
    // survives restarts.
    readonly property var defaultTileOrder: ["weather", "sun", "cpu", "memory", "gpu", "battery", "disk", "network", "ping", "media", "focus"]
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
    })
    property var tileOrder: defaultTileOrder
    property var hiddenTiles: []
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
            case 0:   return 0.0    // fully transparent (below Hyprland ignore_alpha=0.2, so no blur either)
            case 25:  return 0.3
            case 75:  return 0.75
            case 100: return 1.0
            default:  return 0.5    // Medium / unknown
        }
    }
    // Whether the glass cards draw a hairline outline. Chosen in the
    // modal's BORDER toggle; off by default.
    property bool tileBorder: false
    property bool showRightPanel: true
    // Focus tile work/break lengths (minutes), edited via the cog on the tile.
    property int focusWorkMinutes: 25
    property int focusBreakMinutes: 5
    // What the left panel actually renders - tileOrder minus hidden tiles.
    readonly property var visibleTileOrder: shell.tileOrder.filter(function(id) {
        return shell.hiddenTiles.indexOf(id) === -1
    })

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
        shell.hiddenTiles = (tileOrderAdapter.hidden || []).filter(function(id) {
            return shell.defaultTileOrder.indexOf(id) !== -1
        })
        shell.screenName = tileOrderAdapter.screenName || ""
        shell.blurPercent = [0, 25, 50, 75, 100].indexOf(tileOrderAdapter.blur) !== -1
                            ? tileOrderAdapter.blur : 50
        shell.tileBorder = tileOrderAdapter.border === true
        shell.showRightPanel = tileOrderAdapter.rightPanel !== false
        shell.focusWorkMinutes  = _clampInt(tileOrderAdapter.focusWork,  1, 180, 25)
        shell.focusBreakMinutes = _clampInt(tileOrderAdapter.focusBreak, 1, 60,  5)
    }
    function _clampInt(v, lo, hi, fallback) {
        var n = parseInt(v)
        return (!isNaN(n) && n >= lo && n <= hi) ? n : fallback
    }
    function saveTileOrder(newOrder) {
        shell.tileOrder = newOrder
        tileOrderAdapter.order = newOrder
        tileOrderFile.writeAdapter()
    }
    function saveHiddenTiles(newHidden) {
        shell.hiddenTiles = newHidden
        tileOrderAdapter.hidden = newHidden
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
    }
    function saveTileBorder(on) {
        shell.tileBorder = on
        tileOrderAdapter.border = on
        tileOrderFile.writeAdapter()
    }
    function saveShowRightPanel(on) {
        shell.showRightPanel = on
        tileOrderAdapter.rightPanel = on
        tileOrderFile.writeAdapter()
    }
    function saveFocusTimers(workMin, breakMin) {
        shell.focusWorkMinutes  = workMin
        shell.focusBreakMinutes = breakMin
        tileOrderAdapter.focusWork  = workMin
        tileOrderAdapter.focusBreak = breakMin
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
            property var hidden: []
            property string screenName: ""
            property int blur: 50
            property bool border: false
            property bool rightPanel: true
            property int focusWork: 25
            property int focusBreak: 5
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

        screen:          shell._mainScreen
        anchors {        top: true; left: true; bottom: true; right: false }
        implicitWidth:   tileFlow.width + 16   // 8 left + 8 right margins

        WlrLayershell.layer:         WlrLayer.Bottom
        WlrLayershell.namespace:     "quickshell:dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode:               ExclusionMode.Ignore
        color:                       "transparent"

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

            // Each tile is a Component, keyed by id, instantiated in
            // whatever order shell.tileOrder says (see Repeater below).
            property var tileMap: ({
                weather: weatherTile,
                sun:     sunTile,
                cpu:     cpuTile,
                memory:  memoryTile,
                gpu:     gpuTile,
                battery: batteryTile,
                disk:    diskTile,
                network: networkTile,
                ping:    pingTile,
                media:   mediaTile,
                focus:   focusTile,
            })

            Repeater {
                model: shell.visibleTileOrder
                delegate: Item {
                    width: 296
                    height: tileLoader.height

                    // Double-click the tile itself (not the empty panel
                    // around it) to reorder tiles. Sits behind the loaded
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
                        sourceComponent: tileFlow.tileMap[modelData]
                    }
                }
            }

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

                // ── FOCUS (pomodoro timer + now playing) ─────────────
                Component { id: focusTile; StatCard {
                    id: focusCard
                    label: "Focus"
                    theme: shell._theme
                    Layout.fillWidth: true

                    // Settings cog on the label row - opens the work/break editor.
                    headerAccessory: Component {
                        Item {
                            implicitWidth: 13; implicitHeight: 13
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
                                anchors { fill: parent; margins: -7 }
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: focusSettingsModal.open()
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
                                focusCard._notifyEnd()
                                focusCard._advance()
                            }
                        }
                    }

                    // MPRIS active-player pick - same pattern as the Media tile.
                    property int _mpTick: 0
                    property var activePlayer: {
                        _mpTick
                        const list = Mpris.players ? Mpris.players.values : []
                        for (var i = 0; i < list.length; i++) if (list[i].isPlaying) return list[i]
                        for (var j = 0; j < list.length; j++) if (list[j].trackTitle) return list[j]
                        return null
                    }
                    readonly property bool hasMedia: activePlayer !== null &&
                        (activePlayer.trackTitle !== "" || activePlayer.trackArtist !== "")

                    Instantiator {
                        model: Mpris.players
                        delegate: Connections {
                            required property var modelData
                            target: modelData
                            function onIsPlayingChanged() { if (focusCard) focusCard._mpTick++ }
                            Component.onCompleted:  { if (focusCard) focusCard._mpTick++ }
                            Component.onDestruction: { if (focusCard) focusCard._mpTick++ }
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
                        text: (focusCard.mode === 0 ? "WORK SESSION" : "BREAK")
                              + (focusCard.activePlayer && focusCard.activePlayer.isPlaying ? " · MUSIC ON" : "")
                        color: _fg(0.5)
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }

                    // Now playing
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        visible: focusCard.hasMedia
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text:  focusCard.activePlayer ? (focusCard.activePlayer.trackTitle || "-") : ""
                            color: _fg(0.8)
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text:  focusCard.activePlayer
                                   ? (focusCard.activePlayer.trackArtist || focusCard.activePlayer.identity || "")
                                   : ""
                            color: _fg(0.4)
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }

                    // Media transport (only when a player is active)
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        visible: focusCard.hasMedia
                        spacing: 20

                        Item { Layout.fillWidth: true }
                        Text {
                            text: "◀◀"
                            font.pixelSize: 12
                            color: focusCard.activePlayer && focusCard.activePlayer.canGoPrevious ? _fg(0.8) : _fg(0.2)
                            MouseArea {
                                anchors { fill: parent; margins: -6 }
                                enabled: focusCard.activePlayer && focusCard.activePlayer.canGoPrevious
                                cursorShape: Qt.PointingHandCursor
                                onClicked: focusCard.activePlayer.previous()
                            }
                        }
                        Item {
                            width: 15; height: 15
                            Text {
                                anchors.centerIn: parent
                                visible: !(focusCard.activePlayer && focusCard.activePlayer.isPlaying)
                                text: "▶"
                                font.pixelSize: 15
                                color: _fg(0.9)
                            }
                            Row {
                                anchors.centerIn: parent
                                visible: focusCard.activePlayer && focusCard.activePlayer.isPlaying
                                spacing: 3
                                Rectangle { width: 4; height: 13; radius: 1; color: _fg(0.9) }
                                Rectangle { width: 4; height: 13; radius: 1; color: _fg(0.9) }
                            }
                            MouseArea {
                                anchors { fill: parent; margins: -6 }
                                enabled: focusCard.activePlayer && focusCard.activePlayer.canTogglePlaying
                                cursorShape: Qt.PointingHandCursor
                                onClicked: focusCard.activePlayer.togglePlaying()
                            }
                        }
                        Text {
                            text: "▶▶"
                            font.pixelSize: 12
                            color: focusCard.activePlayer && focusCard.activePlayer.canGoNext ? _fg(0.8) : _fg(0.2)
                            MouseArea {
                                anchors { fill: parent; margins: -6 }
                                enabled: focusCard.activePlayer && focusCard.activePlayer.canGoNext
                                cursorShape: Qt.PointingHandCursor
                                onClicked: focusCard.activePlayer.next()
                            }
                        }
                        Item { Layout.fillWidth: true }
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
        }

        // ── Left panel helpers ────────────────────────────────────────

        TileReorderModal {
            id: reorderModal
            screen: shell._mainScreen
            theme: theme
            tileLabels: shell.tileLabels
            order: shell.tileOrder
            hiddenTiles: shell.hiddenTiles
            screens: Quickshell.screens
            overrideScreenName: shell.screenName
            activeScreenName: shell._mainScreen ? shell._mainScreen.name : ""
            blurPercent: shell.blurPercent
            borderEnabled: shell.tileBorder
            rightPanelEnabled: shell.showRightPanel
            weatherLocation: weather.locName
            onOrderEdited: newOrder => shell.saveTileOrder(newOrder)
            onVisibilityEdited: newHidden => shell.saveHiddenTiles(newHidden)
            onScreenEdited: name => shell.saveScreenName(name)
            onBlurEdited: pct => shell.saveBlurPercent(pct)
            onBorderEdited: on => shell.saveTileBorder(on)
            onRightPanelEdited: on => shell.saveShowRightPanel(on)
            onWeatherLocationEdited: name => shell.setWeatherLocation(name)
        }

        // Work/break editor for the Focus tile (opened by its cog).
        FocusSettingsModal {
            id: focusSettingsModal
            screen: shell._mainScreen
            theme: theme
            workMinutes: shell.focusWorkMinutes
            breakMinutes: shell.focusBreakMinutes
            onSaved: (work, brk) => shell.saveFocusTimers(work, brk)
        }
    }

    // ════════════════════════════════════════════════════════════
    //  RIGHT PANEL - System Info (neofetch style)
    // ════════════════════════════════════════════════════════════
    PanelWindow {
        id: rightPanel

        visible:         shell.showRightPanel
        screen:          shell._mainScreen
        anchors {        top: true; right: true }
        implicitWidth:   300

        WlrLayershell.layer:         WlrLayer.Bottom
        WlrLayershell.namespace:     "quickshell:dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode:               ExclusionMode.Ignore
        color:                       "transparent"

        // Height tracks card content
        implicitHeight: sysCard.implicitHeight + 40 + 8

        Item {
            anchors {
                top: parent.top; topMargin: 40
                right: parent.right; rightMargin: 8
            }
            width: 284   // 300 - 8 - 8
            height: sysCard.implicitHeight

            // Double-click the card to open the settings modal, same as
            // the left tiles. Sits behind the card's own content.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onDoubleClicked: reorderModal.open()
            }

            StatCard {
                id: sysCard
                label: "System"
                theme: theme
                anchors { left: parent.left; right: parent.right }

                SysInfoWidget {
                    Layout.fillWidth: true
                    ramInfo: metrics.ramTotalGB.toFixed(0) + " GB"
                    gpuInfo: metrics.gpuName || "-"
                    accentColor: theme.accent
                    textColor: theme.foreground
                }
            }
        }
    }
}
