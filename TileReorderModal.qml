import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Full-screen overlay opened by double-clicking the dashboard. Lets you
// drag the stat tiles into whatever order you want; changes are reported
// live via orderEdited() so the caller can persist + re-apply them.
PanelWindow {
    id: modal

    property var theme: null
    property var tileLabels: ({})
    // Seed order, read once each time the modal opens.
    property var order: []

    signal orderEdited(var newOrder)

    function open()  { opened = true }
    function close() { opened = false }

    property bool opened: false
    visible: opened

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell:dashboard:reorder"
    WlrLayershell.keyboardFocus: modal.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function _fg(a) {
        if (!modal.theme) return Qt.rgba(1, 1, 1, a === undefined ? 1 : a)
        return Qt.rgba(modal.theme.foreground.r, modal.theme.foreground.g, modal.theme.foreground.b, a === undefined ? 1 : a)
    }

    // Working copy of the order, rebuilt from `order` every time the modal opens.
    ListModel { id: tileModel }

    function _sync() {
        tileModel.clear()
        for (var i = 0; i < modal.order.length; i++)
            tileModel.append({ tileId: modal.order[i] })
    }
    function _commit() {
        var arr = []
        for (var i = 0; i < tileModel.count; i++) arr.push(tileModel.get(i).tileId)
        modal.orderEdited(arr)
    }
    onOpenedChanged: if (opened) _sync()

    // ── Scrim ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)

        MouseArea {
            anchors.fill: parent
            onClicked: modal.close()
        }
    }

    Item {
        anchors.fill: parent
        focus: modal.opened
        Keys.onEscapePressed: modal.close()
    }

    // ── Card ─────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 340
        height: content.implicitHeight + 40
        radius: 18
        color: modal.theme
               ? Qt.rgba(modal.theme.background.r, modal.theme.background.g, modal.theme.background.b, 0.92)
               : Qt.rgba(0.1, 0.1, 0.12, 0.95)
        border.width: 1
        border.color: modal._fg(0.12)

        // Swallow clicks so they don't fall through to the scrim.
        MouseArea { anchors.fill: parent; onClicked: {} }

        ColumnLayout {
            id: content
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                margins: 20
            }
            spacing: 14

            ColumnLayout {
                id: header
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Reorder Tiles"
                    color: modal._fg()
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }
                Text {
                    text: "Drag to reorder · Esc to close"
                    color: modal._fg(0.45)
                    font.pixelSize: 11
                }
            }

            Item {
                id: list
                Layout.fillWidth: true
                readonly property int rowHeight: 44
                readonly property int rowSpacing: 8
                readonly property int slot: rowHeight + rowSpacing
                Layout.preferredHeight: tileModel.count * slot - rowSpacing

                Repeater {
                    model: tileModel
                    delegate: Rectangle {
                        id: chip
                        width: list.width
                        height: list.rowHeight
                        radius: 10
                        z: dragArea.drag.active ? 10 : 1

                        property int visualIndex: index
                        property string myTileId: tileId

                        y: chip.visualIndex * list.slot
                        Behavior on y {
                            enabled: !dragArea.drag.active
                            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                        }

                        color: dragArea.drag.active
                               ? modal._fg(0.14)
                               : (modal.theme
                                  ? Qt.rgba(modal.theme.foreground.r, modal.theme.foreground.g, modal.theme.foreground.b, 0.06)
                                  : Qt.rgba(1, 1, 1, 0.06))
                        border.width: 1
                        border.color: modal._fg(dragArea.drag.active ? 0.25 : 0.1)

                        Text {
                            anchors {
                                left: parent.left; leftMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: modal.tileLabels[chip.myTileId] || chip.myTileId
                            color: modal._fg(0.9)
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }

                        Text {
                            anchors {
                                right: parent.right; rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: "⠇⠇"
                            color: modal._fg(0.3)
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            drag.target: chip
                            drag.axis: Drag.YAxis
                            cursorShape: Qt.SizeVerCursor

                            onPositionChanged: {
                                if (!drag.active) return
                                var newIndex = Math.round(chip.y / list.slot)
                                newIndex = Math.max(0, Math.min(tileModel.count - 1, newIndex))
                                if (newIndex !== chip.visualIndex) {
                                    tileModel.move(chip.visualIndex, newIndex, 1)
                                    modal._commit()
                                }
                            }
                            onReleased: {
                                chip.y = Qt.binding(function() { return chip.visualIndex * list.slot })
                            }
                        }
                    }
                }
            }

            Item {
                id: footer
                Layout.fillWidth: true
                Layout.preferredHeight: doneButton.implicitHeight

                Rectangle {
                    id: doneButton
                    anchors.right: parent.right
                    implicitWidth: doneLabel.implicitWidth + 28
                    implicitHeight: doneLabel.implicitHeight + 14
                    radius: 9
                    color: modal.theme ? modal.theme.accent : "#3478F6"

                    Text {
                        id: doneLabel
                        anchors.centerIn: parent
                        text: "Done"
                        color: "#FFFFFF"
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
}
