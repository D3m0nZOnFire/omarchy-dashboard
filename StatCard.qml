import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property string label: ""
    // Live Theme instance (see Theme.qml), shared from shell.qml — colors
    // the glass fill and label from the active Omarchy theme when set,
    // otherwise falls back to a neutral dark-glass default.
    property var theme: null
    default property alias content: contentArea.data

    implicitWidth: 296
    implicitHeight: contentArea.y + contentArea.implicitHeight + 12

    // Glass background — tinted from the theme's own background color so
    // it reads as "whitish glass" on light themes and "blackish glass" on
    // dark ones, instead of always being a flat dark tint.
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.theme
               ? Qt.rgba(root.theme.background.r, root.theme.background.g, root.theme.background.b, 0.5)
               : Qt.rgba(0.08, 0.08, 0.10, 0.5)
        border.color: root.theme
               ? Qt.rgba(root.theme.foreground.r, root.theme.foreground.g, root.theme.foreground.b, 0.12)
               : Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
    }

    // Card label
    Text {
        id: cardLabel
        anchors { top: parent.top; left: parent.left; topMargin: 12; leftMargin: 14 }
        text: root.label.toUpperCase()
        color: root.theme
               ? Qt.rgba(root.theme.foreground.r, root.theme.foreground.g, root.theme.foreground.b, 0.55)
               : Qt.rgba(1, 1, 1, 0.45)
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
