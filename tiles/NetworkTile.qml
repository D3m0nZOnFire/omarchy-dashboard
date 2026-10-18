import QtQuick
import QtQuick.Layouts
import ".."

// Network tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var metrics: shell ? shell._metrics : null

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
                Text { text:"↓  RX"; color:shell._fg(0.35); font.pixelSize:9 }
                Text {
                    text:           shell._fmtNet(metrics.netRxKBs)
                    color:          theme.blue
                    font.pixelSize: 14
                    font.weight:    Font.Medium
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text { text:"↑  TX"; color:shell._fg(0.35); font.pixelSize:9 }
                Text {
                    text:           shell._fmtNet(metrics.netTxKBs)
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
            maxValue:   shell._netMax()
            lineColor:  theme.blue
            lineColor2: theme.orange
        }
    }
}
