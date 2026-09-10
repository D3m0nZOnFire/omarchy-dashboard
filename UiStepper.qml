import QtQuick
import QtQuick.Layouts
import "ColorUtil.js" as C

// − [ 25 ] +  minute stepper. Renders `value`, clamps to [from, to], and
// emits `committed(v)` on every change (button or typed + Enter/blur).
RowLayout {
    id: root

    property var theme: null
    property int value: 0
    property int from: 1
    property int to: 999
    property string unit: "min"

    signal committed(int v)

    spacing: 7

    function _set(v) {
        var c = Math.max(root.from, Math.min(root.to, Math.round(v)))
        if (isNaN(c) || c === root.value) return
        root.committed(c)
    }

    component StepBtn: Rectangle {
        id: btn
        property string glyph: ""
        signal activated()
        width: 26; height: 30
        radius: root.theme ? root.theme.radiusS : 8
        color: area.containsMouse ? C.fg(root.theme, 0.14) : C.fg(root.theme, 0.06)
        border.width: 1
        border.color: C.fg(root.theme, 0.12)
        Text {
            anchors.centerIn: parent
            text: btn.glyph
            color: C.fg(root.theme, 0.85)
            font.pixelSize: 15
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.activated()
        }
    }

    StepBtn { glyph: "−"; onActivated: root._set(root.value - 1) }

    Rectangle {
        Layout.preferredWidth: 56
        Layout.preferredHeight: 30
        radius: root.theme ? root.theme.radiusS : 8
        color: C.fg(root.theme, 0.06)
        border.width: 1
        border.color: input.activeFocus
                      ? (root.theme ? root.theme.accent : "#3478F6")
                      : C.fg(root.theme, 0.12)

        TextInput {
            id: input
            anchors.fill: parent
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            color: C.fg(root.theme, 0.95)
            font.pixelSize: 14
            selectByMouse: true
            selectionColor: root.theme ? root.theme.accent : "#3478F6"
            inputMethodHints: Qt.ImhDigitsOnly
            maximumLength: 3
            text: root.value.toString()

            function _commit() {
                root._set(parseInt(input.text))
                input.text = Qt.binding(function() { return root.value.toString() })
            }
            onActiveFocusChanged: activeFocus ? selectAll() : _commit()
            Keys.onReturnPressed: { _commit(); focus = false }
            Keys.onEnterPressed:  { _commit(); focus = false }
            Keys.onEscapePressed: { text = Qt.binding(function() { return root.value.toString() }); focus = false }
        }
    }

    StepBtn { glyph: "+"; onActivated: root._set(root.value + 1) }

    Text {
        text: root.unit
        color: C.fg(root.theme, 0.4)
        font.pixelSize: 11
    }

    Item { Layout.fillWidth: true }
}
