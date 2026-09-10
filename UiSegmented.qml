import QtQuick
import QtQuick.Layouts
import "ColorUtil.js" as C

// A segmented row of buttons that splits its width evenly. `model` is a
// list of { value, label }; the button whose value equals `currentValue`
// is highlighted. Emits `picked(value)`.
Item {
    id: root

    property var theme: null
    property var model: []
    property var currentValue: undefined

    signal picked(var value)

    implicitHeight: 34

    RowLayout {
        anchors.fill: parent
        spacing: 6

        Repeater {
            model: root.model
            delegate: Rectangle {
                id: seg
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                radius: root.theme ? root.theme.radiusS : 8

                readonly property bool selected: modelData.value === root.currentValue
                color: selected ? C.accent(root.theme, 0.16) : C.fg(root.theme, 0.05)
                border.width: 1
                border.color: selected
                              ? (root.theme ? root.theme.accent : "#3478F6")
                              : C.fg(root.theme, 0.12)

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                    text: seg.modelData.label
                    color: seg.selected ? C.fg(root.theme, 0.95) : C.fg(root.theme, 0.6)
                    font.pixelSize: root.theme ? root.theme.fontSmall : 11
                    font.weight: seg.selected ? Font.Medium : Font.Normal
                    elide: Text.ElideRight
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(seg.modelData.value)
                }
            }
        }
    }
}
