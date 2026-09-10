import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Small overlay for setting the Focus tile's work / break lengths. Opened by
// the cog on the Focus tile. Same glass-card / mask / Esc pattern as
// TileReorderModal; changes apply live (each +/- emits `saved`).
PanelWindow {
    id: modal

    property var theme: null
    property int workMinutes: 25
    property int breakMinutes: 5

    // Emitted on every change - the shell persists it and feeds the new
    // values back in through workMinutes / breakMinutes.
    signal saved(int work, int brk)

    function open()  { opened = true }
    function close() { opened = false }

    property bool opened: false
    visible: opened

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell:dashboard"
    WlrLayershell.keyboardFocus:  modal.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region { item: card }

    readonly property int _workMin: 1
    readonly property int _workMax: 180
    readonly property int _breakMin: 1
    readonly property int _breakMax: 60

    function _fg(a) {
        if (!modal.theme) return Qt.rgba(1, 1, 1, a === undefined ? 1 : a)
        return Qt.rgba(modal.theme.foreground.r, modal.theme.foreground.g, modal.theme.foreground.b, a === undefined ? 1 : a)
    }
    function _onAccent() {
        if (!modal.theme) return Qt.rgba(1, 1, 1, 1)
        function lum(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
        var a = lum(modal.theme.accent), f = lum(modal.theme.foreground), b = lum(modal.theme.background)
        return Math.abs(f - a) >= Math.abs(b - a) ? modal.theme.foreground : modal.theme.background
    }

    Item {
        anchors.fill: parent
        focus: modal.opened
        Keys.onEscapePressed: modal.close()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: content.implicitWidth + 40
        height: content.implicitHeight + 40
        radius: 16
        color: modal.theme
               ? Qt.rgba(modal.theme.background.r, modal.theme.background.g, modal.theme.background.b, Math.max(0.6, modal.theme.glassAlpha))
               : Qt.rgba(0.08, 0.08, 0.10, 0.6)
        border.width: 1
        border.color: modal._fg(0.12)

        ColumnLayout {
            id: content
            anchors { top: parent.top; left: parent.left; margins: 20 }
            spacing: 14

            Text {
                text: "Focus Timer"
                color: modal._fg()
                font.pixelSize: 16
                font.weight: Font.Medium
            }

            Repeater {
                model: [
                    { key: "work",  label: "WORK" },
                    { key: "break", label: "BREAK" },
                ]
                delegate: RowLayout {
                    id: row
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 7

                    readonly property bool isWork: modelData.key === "work"
                    readonly property int value: isWork ? modal.workMinutes : modal.breakMinutes
                    readonly property int lo: isWork ? modal._workMin : modal._breakMin
                    readonly property int hi: isWork ? modal._workMax : modal._breakMax

                    // Clamp + commit a new minute count (NaN / no-change ignored).
                    function _set(v) {
                        var c = Math.max(lo, Math.min(hi, Math.round(v)))
                        if (isNaN(c) || c === value) return
                        if (isWork) modal.saved(c, modal.breakMinutes)
                        else modal.saved(modal.workMinutes, c)
                    }

                    Text {
                        text: row.modelData.label
                        color: modal._fg(0.4)
                        font.pixelSize: 10
                        font.letterSpacing: 1.5
                        Layout.preferredWidth: 52
                    }

                    Rectangle {
                        width: 26; height: 30; radius: 8
                        color: minusArea.containsMouse ? modal._fg(0.14) : modal._fg(0.06)
                        border.width: 1; border.color: modal._fg(0.12)
                        Text { anchors.centerIn: parent; text: "−"; color: modal._fg(0.85); font.pixelSize: 15 }
                        MouseArea {
                            id: minusArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._set(row.value - 1)
                        }
                    }

                    // Type the value directly.
                    Rectangle {
                        Layout.preferredWidth: 54
                        height: 30
                        radius: 8
                        color: modal._fg(0.06)
                        border.width: 1
                        border.color: minsInput.activeFocus
                                      ? (modal.theme ? modal.theme.accent : "#3478F6")
                                      : modal._fg(0.12)

                        TextInput {
                            id: minsInput
                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            color: modal._fg(0.95)
                            font.pixelSize: 14
                            selectByMouse: true
                            selectionColor: modal.theme ? modal.theme.accent : "#3478F6"
                            inputMethodHints: Qt.ImhDigitsOnly
                            maximumLength: 3
                            text: row.value.toString()

                            function _commit() {
                                row._set(parseInt(minsInput.text))
                                minsInput.text = Qt.binding(function() { return row.value.toString() })
                            }
                            onActiveFocusChanged: activeFocus ? selectAll() : _commit()
                            Keys.onReturnPressed: { _commit(); focus = false }
                            Keys.onEnterPressed:  { _commit(); focus = false }
                            Keys.onEscapePressed: { text = Qt.binding(function() { return row.value.toString() }); focus = false }
                        }
                    }

                    Rectangle {
                        width: 26; height: 30; radius: 8
                        color: plusArea.containsMouse ? modal._fg(0.14) : modal._fg(0.06)
                        border.width: 1; border.color: modal._fg(0.12)
                        Text { anchors.centerIn: parent; text: "+"; color: modal._fg(0.85); font.pixelSize: 15 }
                        MouseArea {
                            id: plusArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row._set(row.value + 1)
                        }
                    }

                    Text {
                        text: "min"
                        color: modal._fg(0.4)
                        font.pixelSize: 11
                    }

                    Item { Layout.fillWidth: true }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignRight
                implicitWidth: doneLabel.implicitWidth + 28
                implicitHeight: doneLabel.implicitHeight + 14
                radius: 9
                color: modal.theme ? modal.theme.accent : "#3478F6"
                Text {
                    id: doneLabel
                    anchors.centerIn: parent
                    text: "Done"
                    color: modal._onAccent()
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: modal.close()
                }
            }
        }
    }
}
