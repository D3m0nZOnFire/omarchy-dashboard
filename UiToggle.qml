import QtQuick
import "ColorUtil.js" as C

// A small on/off switch. Stateless: it renders `checked` and emits
// `toggled(!checked)` on click - the parent owns the value.
Item {
    id: root

    property var theme: null
    property bool checked: false

    signal toggled(bool on)

    implicitWidth: 42
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked
               ? (root.theme ? root.theme.accent : "#3478F6")
               : C.fg(root.theme, 0.15)
        Behavior on color { ColorAnimation { duration: root.theme ? root.theme.animFast : 120 } }

        Rectangle {
            width: parent.height - 4
            height: parent.height - 4
            radius: height / 2
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: "#FFFFFF"
            Behavior on x {
                NumberAnimation { duration: root.theme ? root.theme.animFast : 120; easing.type: Easing.OutCubic }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled(!root.checked)
    }
}
