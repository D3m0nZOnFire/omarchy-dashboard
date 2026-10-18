import QtQuick
import QtQuick.Layouts
import ".."

// Weather (Wttr.In - Shares Omarchy'S Location) tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var weather: shell ? shell._weather : null

    label: "Weather"
    theme: shell._theme
    Layout.fillWidth: true

    Text {
        Layout.fillWidth: true
        visible: !weather.ready
        text: "Fetching weather…"
        color: shell._fg(0.35)
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
                color:       shell._fg()
                font.pixelSize: 32
                font.weight: Font.Light
            }
            Text {
                Layout.fillWidth: true
                text:  weather.displayLocation.toUpperCase()
                color: shell._fg(0.5)
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
        color: shell._fg(0.1)
    }

    // FEELS / WIND / HUMID - same labels and formats as the bar.
    RowLayout {
        Layout.fillWidth: true
        visible: weather.ready
        Text { text: "FEELS"; color: shell._fg(0.4); font.pixelSize: 9; font.letterSpacing: 1 }
        Item { Layout.fillWidth: true }
        Text { text: weather.feelsC + "°"; color: shell._fg(); font.pixelSize: 11 }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: weather.ready
        Text { text: "WIND"; color: shell._fg(0.4); font.pixelSize: 9; font.letterSpacing: 1 }
        Item { Layout.fillWidth: true }
        Text { text: weather.windKmph + " km/h"; color: shell._fg(); font.pixelSize: 11 }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: weather.ready
        Text { text: "HUMID"; color: shell._fg(0.4); font.pixelSize: 9; font.letterSpacing: 1 }
        Item { Layout.fillWidth: true }
        Text { text: weather.humidity + "%"; color: shell._fg(); font.pixelSize: 11 }
    }
}
