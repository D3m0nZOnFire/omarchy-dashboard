import QtQuick

// Everything you need to edit for your own machine lives here.
Item {
    // Primary monitor resolution — used to pick which screen the panels
    // attach to when you have more than one. Change to your own display's
    // resolution, or ignore it (see shell.qml _mainScreen) if you only
    // have a single monitor.
    property int screenWidth: 1600
    property int screenHeight: 1000

    // Host pinged for the network latency tile.
    property string pingHost: "1.1.1.1"
}
