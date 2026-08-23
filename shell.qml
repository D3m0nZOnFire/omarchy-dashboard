import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.UPower
import Quickshell.Services.Mpris

Scope {
    id: shell

    // Machine-specific settings — see Config.qml
    Config { id: config }

    // Shared screen reference — which output to put the panels on.
    // 1. Explicit override (Config.screenName), if set.
    // 2. Auto-detect: prefer a laptop panel (name starting with "eDP").
    // 3. Fall back to the first screen.
    readonly property var _mainScreen: {
        if (config.screenName !== "") {
            for (var i = 0; i < Quickshell.screens.length; i++) {
                if (Quickshell.screens[i].name === config.screenName) return Quickshell.screens[i]
            }
        }
        for (var j = 0; j < Quickshell.screens.length; j++) {
            if (Quickshell.screens[j].name.startsWith("eDP")) return Quickshell.screens[j]
        }
        return Quickshell.screens[0]
    }

    // Shared metrics (accessible from both panels by id)
    SystemMetrics { id: metrics; pingHost: config.pingHost }

    // Live Omarchy theme palette (accessible from both panels by id)
    Theme { id: theme }
    // Unshadowed alias — inside a Component {} block (see the per-tile
    // Components below), a bare `theme: theme` binding on an object with
    // its own `theme` property resolves to itself (null) instead of this
    // id, since the Component root shadows outer ids of the same name.
    // Use `shell._theme` there instead.
    readonly property Item _theme: theme

    // ── Tile order — which stat tiles show, and in what order ──────
    // Persisted to disk so a drag-reorder (via double-click → modal)
    // survives restarts.
    readonly property var defaultTileOrder: ["cpu", "memory", "gpu", "battery", "disk", "network", "ping", "media"]
    readonly property var tileLabels: ({
        cpu:     "CPU",
        memory:  "Memory",
        gpu:     "GPU",
        battery: "Battery",
        disk:    "Disk",
        network: "Network",
        ping:    "Ping",
        media:   "Media",
    })
    property var tileOrder: defaultTileOrder
    property var hiddenTiles: []
    // What the left panel actually renders — tileOrder minus hidden tiles.
    readonly property var visibleTileOrder: shell.tileOrder.filter(function(id) {
        return shell.hiddenTiles.indexOf(id) === -1
    })

    // Reconciles the saved order against the known tile ids — drops
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
        }
    }

    // ── Helpers (at Scope level so all children can resolve them) ─
    // Theme foreground at a given alpha (defaults to fully opaque) — use
    // this instead of hardcoding white/rgba(1,1,1,x) so text follows the
    // active Omarchy theme.
    function _fg(a) {
        return Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, a === undefined ? 1 : a)
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
    //  LEFT PANEL — System Stats
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
                cpu:     cpuTile,
                memory:  memoryTile,
                gpu:     gpuTile,
                battery: batteryTile,
                disk:    diskTile,
                network: networkTile,
                ping:    pingTile,
                media:   mediaTile,
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
                    label: "CPU"
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
                                    if (!UPower.displayDevice) return "—"
                                    const st = UPower.displayDevice.state
                                    if (st === UPowerDeviceState.FullyCharged) return "Full"
                                    if (st === UPowerDeviceState.Charging)     return "Charging"
                                    if (st === UPowerDeviceState.Discharging)  return "Discharging"
                                    return "—"
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
                    // state changes, to force activePlayer to re-pick — see
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
                    // playersChanged signal) — a player appearing/disappearing
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
                                text: mediaCard.activePlayer ? (mediaCard.activePlayer.trackTitle || "—") : ""
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
                            // Drawn instead of using the "⏸" glyph — that
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
        }

        // ── Left panel helpers ────────────────────────────────────────

        TileReorderModal {
            id: reorderModal
            screen: shell._mainScreen
            theme: theme
            tileLabels: shell.tileLabels
            order: shell.tileOrder
            hiddenTiles: shell.hiddenTiles
            onOrderEdited: newOrder => shell.saveTileOrder(newOrder)
            onVisibilityEdited: newHidden => shell.saveHiddenTiles(newHidden)
        }
    }

    // ════════════════════════════════════════════════════════════
    //  RIGHT PANEL — System Info (neofetch style)
    // ════════════════════════════════════════════════════════════
    PanelWindow {
        id: rightPanel

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

            StatCard {
                id: sysCard
                label: "System"
                theme: theme
                anchors { left: parent.left; right: parent.right }

                SysInfoWidget {
                    Layout.fillWidth: true
                    ramInfo: metrics.ramTotalGB.toFixed(0) + " GB"
                    gpuInfo: metrics.gpuName || "—"
                    accentColor: theme.accent
                    textColor: theme.foreground
                }
            }
        }
    }
}
