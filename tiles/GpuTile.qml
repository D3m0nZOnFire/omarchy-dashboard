import QtQuick
import QtQuick.Layouts
import ".."

// Gpu tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var metrics: shell ? shell._metrics : null

    label: "GPU" + (metrics.gpuName ? " · " + metrics.gpuName : "")
    theme: shell._theme
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        RingChart {
            textColor: theme.foreground
            trackColor: shell._fg(0.08)
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
                color:          shell._fg()
                font.pixelSize: 20
                font.weight:    Font.Light
            }
            Text {
                text:           metrics.vramUsedMB + " / " + metrics.vramTotalMB + " MB"
                color:          shell._fg(0.35)
                font.pixelSize: 9
            }
            Text {
                text:           metrics.gpuPowerW.toFixed(0) + " W"
                color:          shell._fg(0.5)
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
