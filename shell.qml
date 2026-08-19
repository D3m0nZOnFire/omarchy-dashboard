import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower

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
        implicitWidth:   312

        WlrLayershell.layer:         WlrLayer.Bottom
        WlrLayershell.namespace:     "quickshell:dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode:               ExclusionMode.Ignore
        color:                       "transparent"

        // ── Two-column layout ─────────────────────────────────────────
        RowLayout {
            anchors {
                top: parent.top;    topMargin:    40
                left: parent.left;  leftMargin:   8
                bottom: parent.bottom; bottomMargin: 8
            }
            width: 296   // 312 - 8 left - 8 right
            spacing: 12

            // ════════════════════════════════════════════════════════
            //  COLUMN 1 — System Stats
            // ════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.preferredWidth: 296
                Layout.fillHeight: true
                spacing: 10

                // ── CPU ──────────────────────────────────────────────
                StatCard {
                    label: "CPU"
                    theme: theme
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
                }

                // ── MEMORY ───────────────────────────────────────────
                StatCard {
                    label: "Memory"
                    theme: theme
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
                }

                // ── GPU ──────────────────────────────────────────────
                StatCard {
                    label: "GPU" + (metrics.gpuName ? " · " + metrics.gpuName : "")
                    theme: theme
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
                }

                // ── BATTERY ──────────────────────────────────────────
                StatCard {
                    label: "Battery"
                    theme: theme
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
                }

                // ── DISK ─────────────────────────────────────────────
                StatCard {
                    label: "Disk  /"
                    theme: theme
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
                }

                // ── NETWORK ──────────────────────────────────────────
                StatCard {
                    label: "Network"
                    theme: theme
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
                }

                // ── PING ─────────────────────────────────────────────
                StatCard {
                    label: "Ping · " + config.pingHost
                    theme: theme
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
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ── Left panel helpers ────────────────────────────────────────

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
