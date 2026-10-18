import QtQuick
import QtQuick.Layouts
import ".."

// Ping tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var metrics: shell ? shell._metrics : null
    readonly property var config: shell ? shell._config : null

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
                color: metrics.pingMs < 0   ? shell._fg(0.35)
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
            maxValue:  shell._pingMax()
            lineColor: metrics.pingMs < 0   ? theme.red
                     : metrics.pingMs < 30  ? theme.accent
                     : metrics.pingMs < 100 ? theme.orange : theme.red
        }
    }
}
