import QtQuick

// Optional overrides — the dashboard works with no changes here on most
// setups. Only edit this if the defaults guess wrong for your machine.
Item {
    // Which output to attach the panels to, e.g. "eDP-1" (see `hyprctl
    // monitors`). Usually leave blank: pick the output in the dashboard's
    // Display picker instead (double-click the dashboard → DISPLAY), which
    // is remembered automatically. This is just a fallback for when that
    // picker is set to "Automatic": blank auto-detects (a laptop "eDP"
    // panel if present, else the first screen); set it to force an output.
    property string screenName: ""

    // Host pinged for the network latency tile.
    property string pingHost: "1.1.1.1"
}
