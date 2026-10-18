import QtQuick
import QtQuick.Layouts
import ".."

// System (Neofetch-Style Host Info) tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell
    readonly property var metrics: shell ? shell._metrics : null

    label: "System"
    theme: shell._theme
    Layout.fillWidth: true

    SysInfoWidget {
        Layout.fillWidth: true
        ramInfo: metrics.ramTotalGB.toFixed(0) + " GB"
        gpuInfo: metrics.gpuName || "-"
        accentColor: theme.accent
        textColor: theme.foreground
    }
}
