import QtQuick
import QtQuick.Layouts
import ".."

// Sun (Sunrise / Sunset Arc) tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var weather: shell ? shell._weather : null

    label: weather.isDay ? "Sunset" : "Sunrise"
    theme: shell._theme
    Layout.fillWidth: true

    Text {
        Layout.fillWidth: true
        visible: !weather.ready
        text: "Fetching…"
        color: shell._fg(0.35)
        font.pixelSize: 12
        font.italic: true
    }

    Text {
        visible: weather.ready
        text:  weather.isDay ? weather.sunsetStr : weather.sunriseStr
        color: shell._fg()
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
        arcColor:  shell._fg(0.22)
        lineColor: shell._fg(0.13)
        sunColor:  theme.accent
    }

    Text {
        visible: weather.ready
        text:  (weather.isDay ? "Sunrise: " : "Sunset: ")
               + (weather.isDay ? weather.sunriseStr : weather.sunsetStr)
        color: shell._fg(0.5)
        font.pixelSize: 11
    }
}
