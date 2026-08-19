import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string label: ""
    default property alias content: contentArea.data

    implicitWidth: 296
    implicitHeight: contentArea.y + contentArea.implicitHeight + 12

    // Glass background
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Qt.rgba(0.08, 0.08, 0.10, 0.5)
        border.color: Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
    }

    // Card label
    Text {
        id: cardLabel
        anchors { top: parent.top; left: parent.left; topMargin: 12; leftMargin: 14 }
        text: root.label.toUpperCase()
        color: Qt.rgba(1, 1, 1, 0.45)
        font.pixelSize: 10
        font.letterSpacing: 1.2
        font.weight: Font.Medium
    }

    // Content goes here (via default property)
    ColumnLayout {
        id: contentArea
        anchors {
            top: cardLabel.bottom; topMargin: 8
            left: parent.left; leftMargin: 14
            right: parent.right; rightMargin: 14
        }
        spacing: 6
    }
}
