import QtQuick
import QtQuick.Layouts
import "ColorUtil.js" as C

// A selectable list row: bold primary line, optional dim secondary line,
// a check mark when `selected`. Emits `clicked()`.
Rectangle {
    id: root

    property var theme: null
    property string primary: ""
    property string secondary: ""
    property bool selected: false

    signal clicked()

    implicitHeight: 44
    radius: theme ? theme.radiusM : 10

    color: selected ? C.accent(theme, 0.16) : C.fg(theme, 0.06)
    border.width: 1
    border.color: selected ? (theme ? theme.accent : "#3478F6") : C.fg(theme, 0.1)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: root.primary
                color: C.fg(root.theme, 0.9)
                font.pixelSize: root.theme ? root.theme.fontBody : 12
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                visible: root.secondary !== ""
                text: root.secondary
                color: C.fg(root.theme, 0.4)
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Text {
            visible: root.selected
            text: "✓"
            color: root.theme ? root.theme.accent : "#3478F6"
            font.pixelSize: 13
            font.weight: Font.Bold
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
