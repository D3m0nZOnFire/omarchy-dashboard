import QtQuick
import QtQuick.Layouts
import ".."

// Cpu tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var metrics: shell ? shell._metrics : null

    label: "CPU" + (metrics.cpuModel ? " · " + metrics.cpuModel : "")
    theme: shell._theme
    Layout.fillWidth: true

    // Main row: ring + stats + sparkline
    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        RingChart {
            textColor: theme.foreground
            trackColor: shell._fg(0.08)
            value:     metrics.cpuPercent
            fillColor: metrics.cpuPercent > 95 ? theme.red
                     : metrics.cpuPercent > 80 ? theme.orange : theme.blue
            subText:   metrics.cpuPackageTemp > 0 ? metrics.cpuPackageTemp.toFixed(0) + "°C" : ""
            Layout.preferredWidth: 72; Layout.preferredHeight: 72
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                text:           Math.round(metrics.cpuPercent) + "%"
                color:          shell._fg()
                font.pixelSize: 20
                font.weight:    Font.Light
            }
            Text {
                text:           "Max core: " + metrics.cpuMaxCoreTemp.toFixed(0) + "°C"
                color:          shell._fg(0.35)
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
        property var cores: metrics.corePercents
        // Bound (not read directly in onPaint) so the canvas
        // repaints automatically when the theme changes.
        property color colorLow:  theme.blue
        property color colorMid:  theme.orange
        property color colorHigh: theme.red
        property color colorTrack: shell._fg(0.07)
        onCoresChanged:     requestPaint()
        onWidthChanged:      requestPaint()
        onColorLowChanged:   requestPaint()
        onColorMidChanged:   requestPaint()
        onColorHighChanged:  requestPaint()
        onColorTrackChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
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
