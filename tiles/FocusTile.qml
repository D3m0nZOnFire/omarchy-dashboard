import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import ".."

// Focus (Pomodoro Timer) tile, loaded through shell.qml's tileMap.
StatCard {
    id: focusCard
    property var shell
    readonly property var reorderModal: shell ? shell._reorderModal : null

    label: "Focus"
    theme: shell._theme
    Layout.fillWidth: true

    // Label-row controls - a chime toggle (bell) and the
    // settings cog. Both appear only while the pointer is
    // over the Focus tile.
    headerAccessory: Component {
        Row {
            spacing: 9

            // ── Chime on/off ──
            Item {
                implicitWidth: 13; implicitHeight: 13
                anchors.verticalCenter: parent.verticalCenter
                opacity: (focusCard.hovered || bellArea.containsMouse) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Image {
                    id: bellImg
                    anchors.fill: parent
                    source: Qt.resolvedUrl(shell.focusSound ? "../assets/bell.svg" : "../assets/bell-off.svg")
                    sourceSize: Qt.size(26, 26)
                    fillMode: Image.PreserveAspectFit
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: bellImg
                    source: bellImg
                    color: bellArea.containsMouse ? shell._fg(0.95)
                         : shell._fg(shell.focusSound ? 0.55 : 0.35)
                }
                MouseArea {
                    id: bellArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: shell.saveFocusSound(!shell.focusSound)
                }
            }

            // ── Settings cog ──
            Item {
                implicitWidth: 13; implicitHeight: 13
                anchors.verticalCenter: parent.verticalCenter
                opacity: (focusCard.hovered || cogArea.containsMouse) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Image {
                    id: cogImg
                    anchors.fill: parent
                    source: Qt.resolvedUrl("../assets/cog.svg")
                    sourceSize: Qt.size(26, 26)
                    fillMode: Image.PreserveAspectFit
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: cogImg
                    source: cogImg
                    color: cogArea.containsMouse ? shell._fg(0.95) : shell._fg(0.4)
                }
                MouseArea {
                    id: cogArea
                    anchors { fill: parent; margins: -6 }
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: reorderModal.open("focus")
                }
            }
        }
    }

    property int  mode: 0            // 0 = work, 1 = break
    property bool running: false
    property int  remaining: shell.focusWorkMinutes * 60

    function _lenFor(m) {
        return (m === 0 ? shell.focusWorkMinutes : shell.focusBreakMinutes) * 60
    }
    function _advance() {
        focusCard.mode = focusCard.mode === 0 ? 1 : 0
        focusCard.remaining = focusCard._lenFor(focusCard.mode)
    }
    function _reset() {
        focusCard.running = false
        focusCard.mode = 0
        focusCard.remaining = focusCard._lenFor(0)
    }
    // Omarchy-style desktop notification when a period runs out
    // (bell glyph U+F088C, same as `omarchy reminder`).
    function _notifyEnd() {
        var finishedWork = focusCard.mode === 0
        notifyProc.command = [
            "omarchy-notification-send", "-u", "normal",
            "-g", String.fromCodePoint(0xF088C),
            finishedWork ? "Break time" : "Back to work",
            finishedWork
                ? (shell.focusWorkMinutes + "-min focus session done - take a "
                   + shell.focusBreakMinutes + "-min break.")
                : (shell.focusBreakMinutes + "-min break over - starting a "
                   + shell.focusWorkMinutes + "-min session.")
        ]
        notifyProc.running = true
    }
    Process { id: notifyProc; running: false }

    // Chime when a period ends, if enabled. The freedesktop
    // "complete" sound at 80% (paplay volume is 0-65536).
    Process { id: chimeProc; running: false }
    function _chime() {
        if (!shell.focusSound) return
        chimeProc.running = false
        chimeProc.command = ["paplay", "--volume=52429",
            "/usr/share/sounds/freedesktop/stereo/complete.oga"]
        chimeProc.running = true
    }

    // Pick up length changes from the settings modal when the
    // matching period is idle and untouched.
    Connections {
        target: shell
        function onFocusWorkMinutesChanged() {
            if (!focusCard.running && focusCard.mode === 0)
                focusCard.remaining = focusCard._lenFor(0)
        }
        function onFocusBreakMinutesChanged() {
            if (!focusCard.running && focusCard.mode === 1)
                focusCard.remaining = focusCard._lenFor(1)
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: focusCard.running
        onTriggered: {
            focusCard.remaining -= 1
            if (focusCard.remaining <= 0) {
                focusCard._chime()
                focusCard._notifyEnd()
                focusCard._advance()
            }
        }
    }

    // Timer readout - click to start/pause.
    Text {
        text:  shell._fmtClock(focusCard.remaining)
        color: shell._fg()
        font.pixelSize: 32
        font.weight: Font.Medium
        MouseArea {
            anchors { fill: parent; margins: -8 }
            cursorShape: Qt.PointingHandCursor
            onClicked: focusCard.running = !focusCard.running
        }
    }

    Text {
        Layout.fillWidth: true
        text: focusCard.mode === 0 ? "WORK SESSION" : "BREAK"
        color: shell._fg(0.5)
        font.pixelSize: 10
        font.letterSpacing: 1
        elide: Text.ElideRight
    }

    // ── Timer controls ──────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 8

        Rectangle {
            Layout.preferredWidth: 78
            Layout.preferredHeight: 26
            radius: 8
            color: startArea.containsMouse
                   ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.82)
                   : theme.accent
            Text {
                anchors.centerIn: parent
                text: focusCard.running ? "PAUSE" : "START"
                color: shell._onAccent()
                font.pixelSize: 10
                font.letterSpacing: 1.5
                font.weight: Font.Bold
            }
            MouseArea {
                id: startArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: focusCard.running = !focusCard.running
            }
        }
        Rectangle {
            Layout.preferredWidth: 56
            Layout.preferredHeight: 26
            radius: 8
            color: resetArea.containsMouse ? shell._fg(0.13) : shell._fg(0.06)
            border.width: 1
            border.color: shell._fg(0.12)
            Text {
                anchors.centerIn: parent
                text: "RESET"
                color: shell._fg(0.7)
                font.pixelSize: 9
                font.letterSpacing: 1
            }
            MouseArea {
                id: resetArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: focusCard._reset()
            }
        }
        Rectangle {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 26
            radius: 8
            color: skipArea.containsMouse ? shell._fg(0.13) : shell._fg(0.06)
            border.width: 1
            border.color: shell._fg(0.12)
            Text {
                anchors.centerIn: parent
                text: "SKIP"
                color: shell._fg(0.7)
                font.pixelSize: 9
                font.letterSpacing: 1
            }
            MouseArea {
                id: skipArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: focusCard._advance()
            }
        }
        Item { Layout.fillWidth: true }
    }
}
