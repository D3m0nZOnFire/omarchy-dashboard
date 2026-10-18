import QtQuick
import QtQuick.Layouts
import ".."

// Disk tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var metrics: shell ? shell._metrics : null

    label: "Disk  /"
    theme: shell._theme
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        RingChart {
            textColor: theme.foreground
            trackColor: shell._fg(0.08)
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
                color:          shell._fg()
                font.pixelSize: 20
                font.weight:    Font.Light
            }
            Text {
                text:           "of " + metrics.diskTotalGB.toFixed(0) + " GB · " + metrics.diskPercent + "%"
                color:          shell._fg(0.35)
                font.pixelSize: 9
            }
        }
    }
}
