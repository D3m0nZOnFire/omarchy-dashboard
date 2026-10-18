import QtQuick
import QtQuick.Layouts
import ".."

// Memory tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var metrics: shell ? shell._metrics : null

    label: "Memory"
    theme: shell._theme
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        RingChart {
            textColor: theme.foreground
            trackColor: shell._fg(0.08)
            value:     metrics.ramPercent
            fillColor: metrics.ramPercent > 90 ? theme.red
                     : metrics.ramPercent > 75 ? theme.orange : theme.accent
            Layout.preferredWidth: 72; Layout.preferredHeight: 72
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                text:           metrics.ramUsedGB.toFixed(1) + " GB"
                color:          shell._fg()
                font.pixelSize: 20
                font.weight:    Font.Light
            }
            Text {
                text:           "of " + metrics.ramTotalGB.toFixed(0) + " GB"
                color:          shell._fg(0.35)
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
