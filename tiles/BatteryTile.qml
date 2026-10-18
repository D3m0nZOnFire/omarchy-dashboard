import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import ".."

// Battery tile, loaded through shell.qml's tileMap.
StatCard {
    property var shell

    label: "Battery"
    theme: shell._theme
    Layout.fillWidth: true
    visible: UPower.displayDevice !== null

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        RingChart {
            textColor: theme.foreground
            trackColor: shell._fg(0.08)
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
            Layout.preferredWidth: 72; Layout.preferredHeight: 72
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: {
                    if (!UPower.displayDevice) return "-"
                    const st = UPower.displayDevice.state
                    if (st === UPowerDeviceState.FullyCharged) return "Full"
                    if (st === UPowerDeviceState.Charging)     return "Charging"
                    if (st === UPowerDeviceState.Discharging)  return "Discharging"
                    return "-"
                }
                color: {
                    if (!UPower.displayDevice) return shell._fg(0.65)
                    const st = UPower.displayDevice.state
                    if (st === UPowerDeviceState.FullyCharged ||
                        st === UPowerDeviceState.Charging) return theme.accent
                    return shell._fg()
                }
                font.pixelSize: 13
                font.weight:    Font.Medium
            }

            Text {
                visible: UPower.displayDevice !== null && shell._batTimeText() !== ""
                text:    shell._batTimeText()
                color:   shell._fg(0.5)
                font.pixelSize: 10
            }

            Text {
                visible: UPower.displayDevice !== null &&
                         UPower.displayDevice.changeRate > 0
                text:    (UPower.displayDevice
                          ? UPower.displayDevice.changeRate : 0).toFixed(1) + " W"
                color:   shell._fg(0.35)
                font.pixelSize: 9
            }
        }
    }
}
