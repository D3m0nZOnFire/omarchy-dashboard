import QtQuick

// Optional overrides — the dashboard works with no changes here on most
// setups. Only edit this if the defaults guess wrong for your machine.
Item {
    // Which output to attach the panels to, e.g. "eDP-1" (see `hyprctl
    // monitors`). Leave blank to auto-detect: a laptop panel (name starting
    // with "eDP") if one exists, otherwise the first screen. Only needed on
    // multi-monitor desktops with no laptop panel, where that guess is wrong.
    property string screenName: ""

    // Host pinged for the network latency tile.
    property string pingHost: "1.1.1.1"
}
