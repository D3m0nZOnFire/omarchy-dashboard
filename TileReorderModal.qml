import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Full-screen overlay opened by double-clicking the dashboard. Shown tiles
// sit in a column on the left, hidden ones in a column on the right — drag
// a tile across the gap to hide/show it, drag within a column to reorder.
// Each zone is always exactly one column (it never wraps into more), so
// the modal's width is fixed and only its height adapts to whichever
// column currently has more tiles.
PanelWindow {
    id: modal

    property var theme: null
    property var tileLabels: ({})
    // Seed order/hidden set, read once each time the modal opens.
    property var order: []
    property var hiddenTiles: []

    // Display picker: list of Quickshell.screens, the user's persisted
    // override ("" = Automatic), and the output actually in use right now.
    property var screens: []
    property string overrideScreenName: ""
    property string activeScreenName: ""

    signal orderEdited(var newOrder)
    signal visibilityEdited(var newHidden)
    // "" clears the override and returns to auto-detect.
    signal screenEdited(string newScreenName)

    function open()  { opened = true }
    function close() { opened = false }

    property bool opened: false
    visible: opened

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer:         WlrLayer.Overlay
    // Same namespace as the dashboard panels (shell.qml) — Hyprland's
    // frosted-glass blur rule (~/.config/hypr/looknfeel.lua) is scoped to
    // this exact namespace, so reusing it is what gives the card the same
    // blurred-glass look as the tiles instead of a flat fill.
    WlrLayershell.namespace:     "quickshell:dashboard"
    // OnDemand (not Exclusive) so this doesn't steal keyboard input away
    // from whatever else is running while it's open.
    WlrLayershell.keyboardFocus: modal.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Restricts the surface's clickable/input area to just the card —
    // this surface still spans the whole screen (so it can center the
    // card), but without this, it would swallow every click on the
    // screen, blocking interaction with whatever's underneath even where
    // the modal is fully transparent.
    mask: Region { item: card }

    function _fg(a) {
        if (!modal.theme) return Qt.rgba(1, 1, 1, a === undefined ? 1 : a)
        return Qt.rgba(modal.theme.foreground.r, modal.theme.foreground.g, modal.theme.foreground.b, a === undefined ? 1 : a)
    }
    function _luminance(c) {
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }
    // Text color for content sitting on theme.accent (e.g. the Done button)
    // — picks whichever of the theme's foreground/background contrasts more
    // with accent, since accent's own lightness varies a lot theme to theme.
    function _onAccent() {
        if (!modal.theme) return Qt.rgba(1, 1, 1, 1)
        var accentLum = modal._luminance(modal.theme.accent)
        var fgLum     = modal._luminance(modal.theme.foreground)
        var bgLum     = modal._luminance(modal.theme.background)
        return Math.abs(fgLum - accentLum) >= Math.abs(bgLum - accentLum)
             ? modal.theme.foreground : modal.theme.background
    }

    // Rows for the Display picker: "Automatic" first, then one per output.
    readonly property var _screenChoices: {
        var out = [{
            name: "",
            primary: "Automatic",
            secondary: modal.overrideScreenName === "" && modal.activeScreenName !== ""
                       ? "currently " + modal.activeScreenName
                       : "laptop screen, else first output"
        }]
        for (var i = 0; i < modal.screens.length; i++) {
            var s = modal.screens[i]
            var sub = s.model || ""
            if (s.width && s.height) sub += (sub ? "  ·  " : "") + s.width + "×" + s.height
            out.push({ name: s.name, primary: s.name, secondary: sub })
        }
        return out
    }

    // Working copy, rebuilt from `order`/`hiddenTiles` every time the modal
    // opens: shown tiles form a prefix, hidden tiles a suffix. `list.shownCount`
    // is the authoritative split point.
    ListModel { id: tileModel }

    function _sync() {
        tileModel.clear()
        var visible = [], hiddenIds = []
        for (var i = 0; i < modal.order.length; i++) {
            var id = modal.order[i]
            if (modal.hiddenTiles.indexOf(id) !== -1) hiddenIds.push(id)
            else visible.push(id)
        }
        for (i = 0; i < visible.length; i++) tileModel.append({ tileId: visible[i] })
        for (i = 0; i < hiddenIds.length; i++) tileModel.append({ tileId: hiddenIds[i] })
        list.shownCount = visible.length
    }
    // A single drag can reorder, hide, or show a tile — always report both.
    function _commit() {
        var order = [], hidden = []
        for (var i = 0; i < tileModel.count; i++) {
            var id = tileModel.get(i).tileId
            order.push(id)
            if (i >= list.shownCount) hidden.push(id)
        }
        modal.orderEdited(order)
        modal.visibilityEdited(hidden)
    }
    onOpenedChanged: if (opened) _sync()

    // No click-outside-to-close: the input mask (see `mask:` above) only
    // covers the card, so clicks outside it go straight through to
    // whatever's underneath instead of reaching this surface at all.
    // Closing is Esc or the Done button.
    Item {
        anchors.fill: parent
        focus: modal.opened
        Keys.onEscapePressed: modal.close()
    }

    // Card position — starts centered; -1 means "not dragged yet", so it
    // keeps re-centering (e.g. on screen resize) until the user grabs the
    // header and moves it, after which it stays put for the rest of the
    // session (drag.target below overwrites these via onReleased).
    property real cardX: -1
    property real cardY: -1

    // ── Card ─────────────────────────────────────────────────────────
    Rectangle {
        id: card
        x: modal.cardX >= 0 ? modal.cardX : (parent.width - width) / 2
        y: modal.cardY >= 0 ? modal.cardY : (parent.height - height) / 2
        width: content.implicitWidth + 40
        height: content.implicitHeight + 40
        // Same glass fill as StatCard.qml — low-alpha theme background so
        // the blurred desktop shows through, tinted for light/dark themes.
        radius: 16
        color: modal.theme
               ? Qt.rgba(modal.theme.background.r, modal.theme.background.g, modal.theme.background.b, 0.5)
               : Qt.rgba(0.08, 0.08, 0.10, 0.5)
        border.width: 1
        border.color: modal._fg(0.12)
        Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // Grab the header to move the modal anywhere on screen.
        MouseArea {
            x: 0; y: 0
            width: card.width
            height: 20 + header.height + 10
            cursorShape: Qt.SizeAllCursor
            drag.target: card
            drag.minimumX: 0
            drag.maximumX: Math.max(0, card.parent.width - card.width)
            drag.minimumY: 0
            drag.maximumY: Math.max(0, card.parent.height - card.height)
            onReleased: {
                modal.cardX = card.x
                modal.cardY = card.y
                card.x = Qt.binding(function() { return modal.cardX >= 0 ? modal.cardX : (card.parent.width - card.width) / 2 })
                card.y = Qt.binding(function() { return modal.cardY >= 0 ? modal.cardY : (card.parent.height - card.height) / 2 })
            }
        }

        ColumnLayout {
            id: content
            anchors { top: parent.top; left: parent.left; margins: 20 }
            spacing: 10

            ColumnLayout {
                id: header
                Layout.fillWidth: true
                spacing: 2
                Text {
                    text: "Dashboard Settings"
                    color: modal._fg()
                    font.pixelSize: 16
                    font.weight: Font.Medium
                }
                Text {
                    text: "Drag to reorder · drag across to hide/show · Esc to close"
                    color: modal._fg(0.45)
                    font.pixelSize: 11
                }
            }

            // ── Display picker ──────────────────────────────────────
            // Which output the panels attach to. "Automatic" clears the
            // override and falls back to Config.screenName / auto-detect.
            // Plain Column with fixed-width rows (like the tile chips below)
            // rather than a nested Layout: a ColumnLayout here resolves its
            // width from `list.width`, which isn't laid out yet on first
            // pass, collapsing every row to zero width.
            Column {
                Layout.preferredWidth: list.hiddenX + list.colWidth
                spacing: 6

                Text {
                    text: "DISPLAY"
                    color: modal._fg(0.35)
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }

                Repeater {
                    model: modal._screenChoices
                    delegate: Rectangle {
                        id: choiceRow
                        required property var modelData
                        width: list.hiddenX + list.colWidth
                        height: 42
                        radius: 10

                        readonly property bool selected: modelData.name === modal.overrideScreenName
                        color: selected
                               ? (modal.theme
                                  ? Qt.rgba(modal.theme.accent.r, modal.theme.accent.g, modal.theme.accent.b, 0.16)
                                  : modal._fg(0.14))
                               : modal._fg(0.06)
                        border.width: 1
                        border.color: selected
                                      ? (modal.theme ? modal.theme.accent : "#3478F6")
                                      : modal._fg(0.1)

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
                                    text: choiceRow.modelData.primary
                                    color: modal._fg(0.9)
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: choiceRow.modelData.secondary !== ""
                                    text: choiceRow.modelData.secondary
                                    color: modal._fg(0.4)
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                visible: choiceRow.selected
                                text: "✓"
                                color: modal.theme ? modal.theme.accent : "#3478F6"
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: modal.screenEdited(choiceRow.modelData.name)
                        }
                    }
                }
            }

            // ── Zone labels ─────────────────────────────────────────
            Item {
                Layout.preferredWidth: list.width
                Layout.preferredHeight: 14
                Text {
                    x: 0; width: list.colWidth
                    text: "SHOWN"
                    color: modal._fg(0.35)
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
                Text {
                    x: list.hiddenX; width: list.colWidth
                    text: "HIDDEN"
                    color: modal._fg(0.35)
                    font.pixelSize: 9
                    font.letterSpacing: 1
                }
            }

            // ── Two fixed columns — width never changes, only height ──
            Item {
                id: list
                Layout.preferredWidth: hiddenX + colWidth
                Layout.preferredHeight: Math.max(1, Math.max(shownCount, hiddenCount)) * slot - rowSpacing

                readonly property int rowHeight: 40
                readonly property int rowSpacing: 6
                readonly property int slot: rowHeight + rowSpacing
                readonly property int colWidth: 200
                readonly property int zoneGap: 24
                readonly property int hiddenX: colWidth + zoneGap

                property int shownCount: 0
                readonly property int hiddenCount: tileModel.count - shownCount

                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                // Divider between the shown and hidden columns.
                Rectangle {
                    x: list.colWidth + list.zoneGap / 2
                    y: 0
                    width: 1
                    height: parent.height
                    color: modal._fg(0.1)
                }

                Repeater {
                    model: tileModel
                    delegate: Rectangle {
                        id: chip
                        width: list.colWidth
                        height: list.rowHeight
                        radius: 10
                        z: dragArea.drag.active ? 10 : 1

                        property int visualIndex: index
                        property string myTileId: tileId
                        property bool tileHidden: visualIndex >= list.shownCount
                        property int myRow: tileHidden ? visualIndex - list.shownCount : visualIndex

                        x: tileHidden ? list.hiddenX : 0
                        y: myRow * list.slot
                        Behavior on x { enabled: !dragArea.drag.active; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        Behavior on y { enabled: !dragArea.drag.active; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                        opacity: chip.tileHidden ? 0.5 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        color: dragArea.drag.active
                               ? modal._fg(0.14)
                               : (modal.theme
                                  ? Qt.rgba(modal.theme.foreground.r, modal.theme.foreground.g, modal.theme.foreground.b, 0.06)
                                  : Qt.rgba(1, 1, 1, 0.06))
                        border.width: 1
                        border.color: modal._fg(dragArea.drag.active ? 0.25 : 0.1)

                        Text {
                            anchors {
                                left: parent.left; leftMargin: 12
                                right: dragHandle.left; rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            text: modal.tileLabels[chip.myTileId] || chip.myTileId
                            color: modal._fg(0.9)
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            id: dragHandle
                            anchors {
                                right: parent.right; rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: "⠇⠇"
                            color: modal._fg(0.3)
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            drag.target: chip
                            cursorShape: Qt.SizeAllCursor

                            onPositionChanged: {
                                if (!drag.active) return
                                var willBeHidden = chip.x > (list.colWidth + list.zoneGap / 2)
                                var row = Math.max(0, Math.round(chip.y / list.slot))
                                var wasHidden = chip.tileHidden
                                // Shown-tile count excluding the dragged tile itself —
                                // the pivot both branches clamp against, regardless of
                                // which column it's headed to. (Depends only on wasHidden:
                                // removing an already-hidden tile never changes it.)
                                var othersShown = list.shownCount - (wasHidden ? 0 : 1)
                                var target
                                if (willBeHidden) {
                                    target = Math.max(othersShown, Math.min(tileModel.count - 1, othersShown + row))
                                } else {
                                    target = Math.max(0, Math.min(othersShown, row))
                                }
                                var moved = target !== chip.visualIndex
                                var zoneChanged = wasHidden !== willBeHidden
                                // Crossing the shown/hidden boundary can land a tile
                                // back at the exact index it started at — the zone
                                // still flipped even though nothing needs to move.
                                if (!moved && !zoneChanged) return
                                if (moved) tileModel.move(chip.visualIndex, target, 1)
                                if (zoneChanged) {
                                    if (wasHidden) list.shownCount += 1
                                    else list.shownCount -= 1
                                }
                                modal._commit()
                            }
                            onReleased: {
                                chip.x = Qt.binding(function() { return chip.tileHidden ? list.hiddenX : 0 })
                                chip.y = Qt.binding(function() { return chip.myRow * list.slot })
                            }
                        }
                    }
                }
            }

            Item {
                id: footer
                Layout.preferredWidth: list.width
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
}
