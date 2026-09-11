import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "ColorUtil.js" as C

// "Dashboard Settings" - a categorised settings window. A left rail of
// pages (Layout / Appearance / Display / Weather / Focus Timer) with the
// selected page's controls in the pane on the right. Opened by
// double-clicking any tile. Full-screen overlay with an input mask over just
// the card (so clicks outside it fall through), and its own BackgroundEffect
// blur region over that same card.
PanelWindow {
    id: modal

    // ── Inputs (owned by shell.qml, fed back after every edit) ──
    property var theme: null
    property var tileLabels: ({})
    property var order: []
    property var placement: ({})          // tileId -> "left" | "right" | "hidden"
    property var defaultPlacement: ({})   // fallback zone per tile when unplaced
    property var screens: []
    property string overrideScreenName: ""
    property string activeScreenName: ""
    property int blurPercent: 50
    property bool borderEnabled: false
    property string weatherLocation: ""
    property int workMinutes: 25
    property int breakMinutes: 5
    property bool focusSoundEnabled: true
    property string versionName: ""      // installed release, e.g. "v1.0.0"
    property string versionSubject: ""
    property string versionDate: ""
    property string repoWeb: ""
    property string latestVersion: ""    // newest release tag on GitHub, when an update is available

    // ── Outputs ──
    signal placementEdited(var newOrder, var newPlacement)
    signal screenEdited(string name)
    signal blurEdited(int pct)
    signal borderEdited(bool on)
    signal weatherLocationEdited(string name)
    signal focusTimersEdited(int work, int brk)
    signal focusSoundEdited(bool on)
    signal updateCheckRequested()
    signal updateRunRequested()

    property string page: "layout"
    property bool opened: false

    // About-page update flow. `updateState` is driven by shell.qml:
    //   idle | checking | uptodate | available | dirty | error | launching
    property string updateState: "idle"
    property int commitsBehind: 0
    property var incomingLog: []      // subjects of the commits we're behind
    property var dirtyFiles: []       // tracked files with local edits
    property string updateError: ""

    function open(p) {
        if (p !== undefined && p !== "") modal.page = p
        modal.opened = true
    }
    function close() { modal.opened = false }

    visible: opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell:dashboard"
    WlrLayershell.keyboardFocus:  modal.opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region { item: card }
    // Its own compositor blur region, scoped to just the card - see
    // shell.qml's panels for the same ext-background-effect-v1 pattern.
    BackgroundEffect.blurRegion: modal.blurPercent > 0 ? cardBlurRegion : null
    Region { id: cardBlurRegion; item: card }

    function _fg(a) { return C.fg(modal.theme, a) }

    readonly property var _pages: [
        { key: "layout",     label: "Layout" },
        { key: "appearance", label: "Appearance" },
        { key: "display",    label: "Display" },
        { key: "weather",    label: "Weather" },
        { key: "focus",      label: "Focus Timer" },
        { key: "about",      label: "About" },
    ]

    // One row per output for the Display page.
    readonly property var _screenChoices: {
        var out = []
        for (var i = 0; i < modal.screens.length; i++) {
            var s = modal.screens[i]
            var sub = s.model || ""
            if (s.width && s.height) sub += (sub ? "  ·  " : "") + s.width + "×" + s.height
            out.push({ name: s.name, primary: s.name, secondary: sub })
        }
        return out
    }

    // ══ Layout board model ══════════════════════════════════════════
    // { tileId, zone } per known tile, in the persisted order. Never
    // mutated during a drag - rebuilt from `order` / `placement` (which
    // the shell feeds back after each committed drop). `boardRev` bumps
    // on every rebuild so chip positions recompute.
    ListModel { id: board }
    property int boardRev: 0

    function _zoneOf(id) {
        var z = modal.placement ? modal.placement[id] : undefined
        if (z === "left" || z === "right" || z === "hidden") return z
        var d = modal.defaultPlacement ? modal.defaultPlacement[id] : undefined
        return (d === "left" || d === "right" || d === "hidden") ? d : "left"
    }
    // Desired board contents: known tiles, grouped left -> right -> hidden,
    // each group keeping the persisted order. A committed drop always
    // produces exactly this shape, so it doubles as the "already in sync"
    // check below.
    function _desiredList() {
        var ord = (modal.order && modal.order.length) ? modal.order : Object.keys(modal.tileLabels)
        var g = { left: [], right: [], hidden: [] }
        for (var i = 0; i < ord.length; i++) {
            var id = ord[i]
            if (modal.tileLabels[id] === undefined) continue
            g[modal._zoneOf(id)].push(id)
        }
        // any known tile missing from `order` (stale file) lands in its default zone
        for (var k in modal.tileLabels) {
            if (g.left.indexOf(k) === -1 && g.right.indexOf(k) === -1 && g.hidden.indexOf(k) === -1)
                g[modal._zoneOf(k)].push(k)
        }
        return g.left.concat(g.right).concat(g.hidden)
    }
    function _boardMatches() {
        var want = modal._desiredList()
        if (want.length !== board.count) return false
        for (var i = 0; i < board.count; i++) {
            var e = board.get(i)
            if (e.tileId !== want[i] || e.zone !== modal._zoneOf(e.tileId)) return false
        }
        return true
    }
    function _syncBoard() {
        if (_boardMatches()) return
        board.clear()
        var want = modal._desiredList()
        for (var i = 0; i < want.length; i++)
            board.append({ tileId: want[i], zone: modal._zoneOf(want[i]) })
        modal.boardRev++
    }
    function _localIndex(idx) {
        var row = board.get(idx)
        if (!row) return 0            // stale delegate mid-rebuild
        var n = 0
        for (var i = 0; i < idx; i++) if (board.get(i).zone === row.zone) n++
        return n
    }
    function _zoneCount(z) {
        var n = 0
        for (var i = 0; i < board.count; i++) if (board.get(i).zone === z) n++
        return n
    }
    function _zoneCountExcl(z, exclId) {
        var n = 0
        for (var i = 0; i < board.count; i++) {
            var e = board.get(i)
            if (e.zone === z && e.tileId !== exclId) n++
        }
        return n
    }
    // Per-zone id lists as they should look mid-drag: `dragId` pulled out of
    // its zone and a "__ph__" marker inserted at (pZone, pLocal). With no
    // drag (dragId ""), just the current per-zone lists. Chips read their
    // display slot from this, so the board reflows live without the model
    // being touched.
    function _previewZones(dragId, pZone, pLocal) {
        var z = { left: [], right: [], hidden: [] }
        for (var i = 0; i < board.count; i++) {
            var e = board.get(i)
            if (dragId !== "" && e.tileId === dragId) continue
            z[e.zone].push(e.tileId)
        }
        if (dragId !== "" && pZone !== "") {
            var arr = z[pZone]
            arr.splice(Math.max(0, Math.min(arr.length, pLocal)), 0, "__ph__")
        }
        return z
    }
    // Drop `tileId` into `newZone` at position `newLocal`, then emit the
    // rebuilt order + placement for the shell to persist.
    function _commitDrag(tileId, newZone, newLocal) {
        var zones = { left: [], right: [], hidden: [] }
        for (var i = 0; i < board.count; i++) {
            var e = board.get(i)
            if (e.tileId === tileId) continue
            zones[e.zone].push(e.tileId)
        }
        var arr = zones[newZone]
        arr.splice(Math.max(0, Math.min(arr.length, newLocal)), 0, tileId)

        var names = ["left", "right", "hidden"]
        var newOrder = zones.left.concat(zones.right).concat(zones.hidden)
        var pl = {}
        for (var n = 0; n < names.length; n++)
            for (var j = 0; j < zones[names[n]].length; j++)
                pl[zones[names[n]][j]] = names[n]
        modal.placementEdited(newOrder, pl)
    }

    onOpenedChanged: {
        if (opened) {
            _syncBoard()
            if (page === "about" && updateState === "idle") updateCheckRequested()
        } else {
            updateState = "idle"   // forget a stale result so reopening re-checks
        }
    }
    onPageChanged: if (opened && page === "about" && updateState === "idle") updateCheckRequested()
    onOrderChanged: _syncBoard()
    onPlacementChanged: _syncBoard()
    Component.onCompleted: _syncBoard()

    // Esc closes. (No click-outside - the mask only covers the card.)
    Item {
        anchors.fill: parent
        focus: modal.opened
        Keys.onEscapePressed: modal.close()
    }

    // Card position - centred until the header is dragged.
    property real cardX: -1
    property real cardY: -1

    Rectangle {
        id: card
        width: 800
        height: 640
        x: modal.cardX >= 0 ? modal.cardX : (parent.width - width) / 2
        y: modal.cardY >= 0 ? modal.cardY : (parent.height - height) / 2
        radius: modal.theme ? modal.theme.radiusL : 16
        color: modal.theme
               ? Qt.rgba(modal.theme.background.r, modal.theme.background.g, modal.theme.background.b, Math.max(0.72, modal.theme.glassAlpha))
               : Qt.rgba(0.08, 0.08, 0.10, 0.8)
        border.width: 1
        border.color: modal._fg(0.12)

        // Grab the header strip to move the window.
        MouseArea {
            x: 0; y: 0
            width: card.width
            height: 56
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

        // ── Header ──────────────────────────────────────────────────
        Text {
            anchors { top: parent.top; left: parent.left; topMargin: 20; leftMargin: 22 }
            text: "Dashboard Settings"
            color: modal._fg()
            font.pixelSize: modal.theme ? modal.theme.fontTitle : 16
            font.weight: Font.Medium
        }
        Rectangle {
            anchors { top: parent.top; right: parent.right; topMargin: 15; rightMargin: 15 }
            width: 26; height: 26; radius: 13
            color: closeArea.containsMouse ? modal._fg(0.12) : "transparent"
            Text { anchors.centerIn: parent; text: "✕"; color: modal._fg(0.6); font.pixelSize: 12 }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: modal.close()
            }
        }
        Rectangle {
            id: headerRule
            anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 56 }
            height: 1
            color: modal._fg(0.1)
        }

        // ── Footer ──────────────────────────────────────────────────
        Item {
            id: footer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: 16 }
            height: 30
            Rectangle {
                anchors { right: parent.right; rightMargin: 22; verticalCenter: parent.verticalCenter }
                width: doneLabel.implicitWidth + 30
                height: 30
                radius: modal.theme ? modal.theme.radiusS + 1 : 9
                color: modal.theme ? modal.theme.accent : "#3478F6"
                Text {
                    id: doneLabel
                    anchors.centerIn: parent
                    text: "Done"
                    color: C.onAccent(modal.theme)
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
        Rectangle {
            id: footerRule
            anchors { bottom: footer.top; left: parent.left; right: parent.right; bottomMargin: 10 }
            height: 1
            color: modal._fg(0.1)
        }

        // ── Sidebar ─────────────────────────────────────────────────
        Column {
            id: sidebar
            anchors { top: headerRule.bottom; left: parent.left; bottom: footerRule.top; margins: 14 }
            width: 158
            spacing: 4

            Repeater {
                model: modal._pages
                delegate: Rectangle {
                    id: navRow
                    required property var modelData
                    width: sidebar.width
                    height: 34
                    radius: modal.theme ? modal.theme.radiusS : 8
                    readonly property bool sel: modal.page === modelData.key
                    color: sel ? C.accent(modal.theme, 0.16)
                               : (navArea.containsMouse ? modal._fg(0.06) : "transparent")

                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 3; height: 18; radius: 1.5
                        visible: navRow.sel
                        color: modal.theme ? modal.theme.accent : "#3478F6"
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                        text: navRow.modelData.label
                        color: navRow.sel ? modal._fg(0.95) : modal._fg(0.6)
                        font.pixelSize: modal.theme ? modal.theme.fontBody : 12
                        font.weight: navRow.sel ? Font.Medium : Font.Normal
                    }
                    MouseArea {
                        id: navArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: modal.page = navRow.modelData.key
                    }
                }
            }
        }
        Rectangle {
            id: sideRule
            anchors { top: headerRule.bottom; bottom: footerRule.top; left: sidebar.right; leftMargin: 6 }
            width: 1
            color: modal._fg(0.1)
        }

        // ── Content pane ────────────────────────────────────────────
        Item {
            id: contentArea
            anchors {
                top: headerRule.bottom;   topMargin: 20
                left: sideRule.right;     leftMargin: 18
                right: parent.right;      rightMargin: 22
                bottom: footerRule.top;   bottomMargin: 16
            }

            // ===== LAYOUT (screen-shaped drag board) =================
            Item {
                anchors.fill: parent
                visible: modal.page === "layout"

                Text {
                    id: layoutHint
                    width: parent.width
                    text: "Drag tiles between the screen edges. Drop one in Hidden to put it away."
                    color: modal._fg(0.5)
                    font.pixelSize: modal.theme ? modal.theme.fontSmall : 11
                    wrapMode: Text.WordWrap
                }

                Item {
                    id: boardArea
                    anchors {
                        top: layoutHint.bottom; topMargin: 14
                        left: parent.left; right: parent.right; bottom: parent.bottom
                    }

                    readonly property int colGap: 18
                    readonly property int colW: Math.floor((width - colGap) / 2)
                    readonly property int labelPad: 28
                    // Inset of every chip from its zone's edges - the single
                    // knob that keeps chips centred in all three zones.
                    readonly property int chipMargin: 12
                    readonly property int hidPerRow: 4
                    readonly property int hidGap: 8
                    readonly property int hidSlot: 30
                    readonly property real hidChipW: (width - 2 * chipMargin - (hidPerRow - 1) * hidGap) / hidPerRow
                    readonly property int trayH: {
                        // Grows to fit a chip being previewed into Hidden; never
                        // shrinks mid-drag (avoids the board jittering).
                        var n = Math.max(modal._zoneCount("hidden"), previewZones.hidden.length)
                        var rows = Math.max(1, Math.ceil(Math.max(1, n) / hidPerRow))
                        return labelPad + rows * hidSlot + 8
                    }
                    readonly property int colH: height - trayH - 14
                    readonly property int slot: Math.max(22, Math.min(34, Math.floor((colH - labelPad) / 12)))
                    readonly property int chipH: slot - 5
                    readonly property int hiddenTop: colH + 14

                    // Live drag state. `dragId` is the tile being dragged
                    // ("" = no drag); `dragZone` / `previewLocal` are where it
                    // would land right now. The board reflows around this
                    // without the model being touched (see previewZones).
                    property string dragId: ""
                    property string dragZone: ""
                    property int previewLocal: 0
                    readonly property var previewZones: {
                        modal.boardRev
                        return modal._previewZones(dragId, dragZone, previewLocal)
                    }

                    function zoneAt(px, py) {
                        if (py >= hiddenTop) return "hidden"
                        return px < (colW + colGap / 2) ? "left" : "right"
                    }
                    function localAt(zone, px, py) {
                        if (zone === "hidden") {
                            var col = Math.round((px - chipMargin) / (hidChipW + hidGap))
                            var row = Math.round((py - hiddenTop - labelPad) / hidSlot)
                            return Math.max(0, row * hidPerRow + Math.max(0, Math.min(hidPerRow - 1, col)))
                        }
                        return Math.max(0, Math.round((py - labelPad) / slot))
                    }

                    // Zone backgrounds + labels.
                    Repeater {
                        model: [
                            { z: "left",   label: "LEFT EDGE" },
                            { z: "right",  label: "RIGHT EDGE" },
                            { z: "hidden", label: "HIDDEN" },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool hot: boardArea.dragZone === modelData.z
                            x: modelData.z === "right" ? boardArea.colW + boardArea.colGap : 0
                            y: modelData.z === "hidden" ? boardArea.hiddenTop : 0
                            width: modelData.z === "hidden" ? boardArea.width : boardArea.colW
                            height: modelData.z === "hidden" ? (boardArea.height - boardArea.hiddenTop) : boardArea.colH
                            radius: modal.theme ? modal.theme.radiusM : 10
                            color: hot ? C.accent(modal.theme, 0.10) : modal._fg(0.04)
                            border.width: 1
                            border.color: hot ? (modal.theme ? modal.theme.accent : "#3478F6") : modal._fg(0.09)
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text {
                                // Left-aligned with the chip label text below
                                // (chip inset chipMargin + chip text margin 12).
                                anchors {
                                    top: parent.top; left: parent.left
                                    topMargin: 9; leftMargin: boardArea.chipMargin + 12
                                }
                                text: parent.modelData.label
                                color: modal._fg(0.35)
                                font.pixelSize: modal.theme ? modal.theme.fontCaption : 9
                                font.letterSpacing: 1
                            }
                        }
                    }

                    // Drop placeholder - a faded slot that opens up wherever
                    // the dragged chip would land. Sits behind the chips.
                    Rectangle {
                        id: placeholder
                        visible: boardArea.dragId !== "" && boardArea.dragZone !== ""
                        z: 0
                        readonly property string pz: boardArea.dragZone
                        readonly property int pl: {
                            if (!visible) return 0
                            var arr = pz === "hidden" ? boardArea.previewZones.hidden
                                    : pz === "right"  ? boardArea.previewZones.right
                                                      : boardArea.previewZones.left
                            var i = arr.indexOf("__ph__")
                            return i >= 0 ? i : 0
                        }
                        width: pz === "hidden" ? boardArea.hidChipW
                                               : boardArea.colW - 2 * boardArea.chipMargin
                        height: pz === "hidden" ? (boardArea.hidSlot - 5) : boardArea.chipH
                        x: {
                            var m = boardArea.chipMargin
                            if (pz === "left")  return m
                            if (pz === "right") return boardArea.colW + boardArea.colGap + m
                            return m + (pl % boardArea.hidPerRow) * (boardArea.hidChipW + boardArea.hidGap)
                        }
                        y: pz === "hidden"
                           ? boardArea.hiddenTop + boardArea.labelPad
                             + Math.floor(pl / boardArea.hidPerRow) * boardArea.hidSlot
                           : boardArea.labelPad + pl * boardArea.slot
                        radius: modal.theme ? modal.theme.radiusM : 10
                        color: C.accent(modal.theme, 0.12)
                        border.width: 1
                        border.color: C.accent(modal.theme, 0.45)
                        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }

                    // Draggable tile chips.
                    Repeater {
                        model: board
                        delegate: Rectangle {
                            id: chip
                            required property int index
                            required property string tileId
                            required property string zone

                            readonly property int rev: modal.boardRev
                            readonly property int local: { rev; modal._localIndex(index) }

                            readonly property bool isDragged: boardArea.dragId === chip.tileId
                            // Where this chip currently belongs on screen -
                            // its model zone/slot, or the live preview slot
                            // while something is being dragged.
                            readonly property string effZone:
                                (isDragged && boardArea.dragZone !== "") ? boardArea.dragZone : chip.zone
                            readonly property int effLocal: {
                                if (isDragged) return boardArea.previewLocal
                                var arr = chip.zone === "hidden" ? boardArea.previewZones.hidden
                                        : chip.zone === "right"  ? boardArea.previewZones.right
                                                                 : boardArea.previewZones.left
                                var i = arr.indexOf(chip.tileId)
                                return i >= 0 ? i : chip.local
                            }

                            width: effZone === "hidden"
                                   ? boardArea.hidChipW
                                   : boardArea.colW - 2 * boardArea.chipMargin
                            height: effZone === "hidden" ? (boardArea.hidSlot - 5) : boardArea.chipH
                            radius: modal.theme ? modal.theme.radiusM : 10
                            z: dragMA.drag.active ? 20 : 1
                            opacity: dragMA.drag.active ? 0.9 : 1

                            readonly property real homeX: {
                                var m = boardArea.chipMargin
                                if (effZone === "left")  return m
                                if (effZone === "right") return boardArea.colW + boardArea.colGap + m
                                return m + (effLocal % boardArea.hidPerRow) * (boardArea.hidChipW + boardArea.hidGap)
                            }
                            readonly property real homeY: {
                                if (effZone === "hidden")
                                    return boardArea.hiddenTop + boardArea.labelPad
                                           + Math.floor(effLocal / boardArea.hidPerRow) * boardArea.hidSlot
                                return boardArea.labelPad + effLocal * boardArea.slot
                            }
                            x: homeX
                            y: homeY
                            Behavior on x { enabled: !dragMA.drag.active; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on y { enabled: !dragMA.drag.active; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            color: dragMA.drag.active ? C.accent(modal.theme, 0.20) : modal._fg(0.08)
                            border.width: 1
                            border.color: dragMA.drag.active
                                          ? (modal.theme ? modal.theme.accent : "#3478F6")
                                          : modal._fg(0.12)

                            Text {
                                anchors {
                                    left: parent.left; leftMargin: 12
                                    right: grip.left; rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: modal.tileLabels[chip.tileId] || chip.tileId
                                color: modal._fg(0.9)
                                font.pixelSize: modal.theme ? modal.theme.fontBody : 12
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            // Drag handle - drawn as a 2x3 dot grid rather
                            // than a glyph, so it sits exactly centred.
                            Grid {
                                id: grip
                                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                                columns: 2
                                rowSpacing: 2
                                columnSpacing: 2
                                Repeater {
                                    model: 6
                                    delegate: Rectangle {
                                        width: 2.5; height: 2.5; radius: 1.25
                                        color: modal._fg(0.35)
                                    }
                                }
                            }

                            MouseArea {
                                id: dragMA
                                anchors.fill: parent
                                cursorShape: Qt.SizeAllCursor
                                drag.target: chip
                                drag.axis: Drag.XAndYAxis

                                function _restoreBindings() {
                                    chip.x = Qt.binding(function() { return chip.homeX })
                                    chip.y = Qt.binding(function() { return chip.homeY })
                                }
                                onPositionChanged: {
                                    if (!drag.active) return
                                    if (boardArea.dragId !== chip.tileId) {
                                        boardArea.dragId = chip.tileId
                                        boardArea.dragZone = chip.zone
                                        boardArea.previewLocal = chip.local
                                    }
                                    var tz = boardArea.zoneAt(chip.x + chip.width / 2, chip.y + chip.height / 2)
                                    var tl = boardArea.localAt(tz, chip.x, chip.y + chip.height / 2)
                                    boardArea.dragZone = tz
                                    boardArea.previewLocal =
                                        Math.max(0, Math.min(modal._zoneCountExcl(tz, chip.tileId), tl))
                                }
                                onReleased: {
                                    if (boardArea.dragId !== chip.tileId) return
                                    var id = chip.tileId
                                    var tz = boardArea.dragZone
                                    var tl = boardArea.previewLocal
                                    // Restore bindings so the chip glides into the
                                    // previewed slot, then commit + clear next tick.
                                    _restoreBindings()
                                    Qt.callLater(function() {
                                        modal._commitDrag(id, tz, tl)
                                        boardArea.dragId = ""
                                        boardArea.dragZone = ""
                                    })
                                }
                                onCanceled: {
                                    if (boardArea.dragId !== chip.tileId) return
                                    _restoreBindings()
                                    boardArea.dragId = ""
                                    boardArea.dragZone = ""
                                }
                            }
                        }
                    }
                }
            }

            // ===== APPEARANCE =======================================
            Column {
                anchors.fill: parent
                visible: modal.page === "appearance"
                spacing: 24

                Column {
                    width: parent.width
                    spacing: 8
                    Text {
                        text: "GLASS OPACITY"
                        color: modal._fg(0.35)
                        font.pixelSize: 9; font.letterSpacing: 1
                    }
                    UiSegmented {
                        width: parent.width
                        theme: modal.theme
                        currentValue: modal.blurPercent
                        model: [
                            { value: 0,   label: "Transparent" },
                            { value: 25,  label: "Light" },
                            { value: 50,  label: "Medium" },
                            { value: 75,  label: "Frosted" },
                            { value: 100, label: "Opaque" },
                        ]
                        onPicked: v => modal.blurEdited(v)
                    }
                    Text {
                        width: parent.width
                        text: "Opacity of every glass card. \"Transparent\" also turns off the blur behind them."
                        color: modal._fg(0.35)
                        font.pixelSize: 10; wrapMode: Text.WordWrap
                    }
                }

                Row {
                    width: parent.width
                    spacing: 14
                    UiToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        theme: modal.theme
                        checked: modal.borderEnabled
                        onToggled: on => modal.borderEdited(on)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { text: "Hairline border on cards"; color: modal._fg(0.9); font.pixelSize: 12 }
                        Text { text: "A thin outline around every tile."; color: modal._fg(0.35); font.pixelSize: 10 }
                    }
                }
            }

            // ===== DISPLAY ==========================================
            Column {
                anchors.fill: parent
                visible: modal.page === "display"
                spacing: 8
                Text {
                    text: "SHOW THE DASHBOARD ON"
                    color: modal._fg(0.35)
                    font.pixelSize: 9; font.letterSpacing: 1
                }
                Repeater {
                    model: modal._screenChoices
                    delegate: UiChoiceRow {
                        required property var modelData
                        width: parent.width
                        theme: modal.theme
                        primary: modelData.primary
                        secondary: modelData.secondary
                        selected: modal.overrideScreenName !== ""
                                  ? modelData.name === modal.overrideScreenName
                                  : modelData.name === modal.activeScreenName
                        onClicked: modal.screenEdited(modelData.name)
                    }
                }
                Text {
                    width: parent.width
                    text: "With none chosen, the dashboard uses your first screen."
                    color: modal._fg(0.35)
                    font.pixelSize: 10; wrapMode: Text.WordWrap
                }
            }

            // ===== WEATHER ==========================================
            Column {
                anchors.fill: parent
                visible: modal.page === "weather"
                spacing: 8
                Text {
                    text: "WEATHER LOCATION"
                    color: modal._fg(0.35)
                    font.pixelSize: 9; font.letterSpacing: 1
                }
                Rectangle {
                    width: parent.width
                    height: 38
                    radius: modal.theme ? modal.theme.radiusM : 10
                    color: modal._fg(0.06)
                    border.width: 1
                    border.color: locInput.activeFocus
                                  ? (modal.theme ? modal.theme.accent : "#3478F6")
                                  : modal._fg(0.1)
                    TextInput {
                        id: locInput
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        color: modal._fg(0.9)
                        font.pixelSize: 12
                        clip: true
                        selectByMouse: true
                        selectionColor: modal.theme ? modal.theme.accent : "#3478F6"
                        function _commit() { modal.weatherLocationEdited(text.trim()); focus = false }
                        Keys.onReturnPressed: _commit()
                        Keys.onEnterPressed: _commit()
                        Keys.onEscapePressed: { text = ""; focus = false }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: locInput.text === "" && !locInput.activeFocus
                            text: modal.weatherLocation !== "" ? modal.weatherLocation : "Auto-detect (IP)"
                            color: modal._fg(0.4)
                            font.pixelSize: 12
                        }
                    }
                }
                Row {
                    spacing: 10
                    Text { text: "Type a city, press Enter to save."; color: modal._fg(0.3); font.pixelSize: 9 }
                    Text {
                        visible: modal.weatherLocation !== ""
                        text: "· use auto-detect"
                        color: modal.theme ? modal.theme.accent : "#3478F6"
                        font.pixelSize: 9
                        MouseArea {
                            anchors { fill: parent; margins: -4 }
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { locInput.text = ""; modal.weatherLocationEdited("") }
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: "Shared with the Omarchy bar. Sets the city for the Weather and Sun tiles."
                    color: modal._fg(0.35)
                    font.pixelSize: 10; wrapMode: Text.WordWrap
                }
            }

            // ===== FOCUS TIMER =====================================
            Column {
                anchors.fill: parent
                visible: modal.page === "focus"
                spacing: 14
                Text {
                    text: "FOCUS TIMER"
                    color: modal._fg(0.35)
                    font.pixelSize: 9; font.letterSpacing: 1
                }
                Row {
                    spacing: 10
                    Text {
                        text: "Work"; width: 46
                        anchors.verticalCenter: parent.verticalCenter
                        color: modal._fg(0.5); font.pixelSize: 11
                    }
                    UiStepper {
                        theme: modal.theme
                        value: modal.workMinutes
                        from: 1; to: 180
                        onCommitted: v => modal.focusTimersEdited(v, modal.breakMinutes)
                    }
                }
                Row {
                    spacing: 10
                    Text {
                        text: "Break"; width: 46
                        anchors.verticalCenter: parent.verticalCenter
                        color: modal._fg(0.5); font.pixelSize: 11
                    }
                    UiStepper {
                        theme: modal.theme
                        value: modal.breakMinutes
                        from: 1; to: 60
                        onCommitted: v => modal.focusTimersEdited(modal.workMinutes, v)
                    }
                }
                Text {
                    width: parent.width
                    text: "Length of each work and break period in the Focus tile."
                    color: modal._fg(0.35)
                    font.pixelSize: 10; wrapMode: Text.WordWrap
                }

                Item { width: 1; height: 6 }

                Row {
                    spacing: 14
                    UiToggle {
                        anchors.verticalCenter: parent.verticalCenter
                        theme: modal.theme
                        checked: modal.focusSoundEnabled
                        onToggled: on => modal.focusSoundEdited(on)
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { text: "Chime when a period ends"; color: modal._fg(0.9); font.pixelSize: 12 }
                        Text { text: "A short sound alongside the desktop notification."; color: modal._fg(0.35); font.pixelSize: 10 }
                    }
                }
            }

            // ===== ABOUT (version + updater) ========================
            Column {
                anchors.fill: parent
                visible: modal.page === "about"
                spacing: 20

                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: "VERSION"
                        color: modal._fg(0.35)
                        font.pixelSize: 9; font.letterSpacing: 1
                    }
                    Text {
                        text: modal.versionName === "" ? "…" : modal.versionName
                        color: modal._fg(0.95)
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    Text {
                        width: parent.width
                        visible: modal.versionSubject !== ""
                        text: modal.versionSubject
                              + (modal.versionDate ? "  ·  " + modal.versionDate : "")
                        color: modal._fg(0.4)
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                Rectangle { width: parent.width; height: 1; color: modal._fg(0.1) }

                Column {
                    width: parent.width
                    spacing: 10
                    Text {
                        text: "UPDATES"
                        color: modal._fg(0.35)
                        font.pixelSize: 9; font.letterSpacing: 1
                    }

                    Row {
                        spacing: 10

                        // "Check for updates" - accent outline pill.
                        Rectangle {
                            width: checkLabel.implicitWidth + 26
                            height: 30
                            radius: modal.theme ? modal.theme.radiusS + 1 : 9
                            color: checkArea.containsMouse ? C.accent(modal.theme, 0.12) : "transparent"
                            border.width: 1
                            border.color: C.accent(modal.theme, 0.55)
                            Text {
                                id: checkLabel
                                anchors.centerIn: parent
                                text: modal.updateState === "checking" ? "Checking…" : "Check for updates"
                                color: modal.theme ? modal.theme.accent : "#3478F6"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            MouseArea {
                                id: checkArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: modal.updateState !== "checking" && modal.updateState !== "launching"
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modal.updateCheckRequested()
                            }
                        }

                        // "Update now" - filled accent, emphasised when an
                        // update is waiting.
                        Rectangle {
                            width: updLabel.implicitWidth + 30
                            height: 30
                            radius: modal.theme ? modal.theme.radiusS + 1 : 9
                            opacity: (modal.updateState === "launching" || modal.updateState === "checking") ? 0.5 : 1
                            color: modal.updateState === "available"
                                   ? (modal.theme ? modal.theme.accent : "#3478F6")
                                   : C.accent(modal.theme, 0.16)
                            Text {
                                id: updLabel
                                anchors.centerIn: parent
                                text: "Update now"
                                color: modal.updateState === "available"
                                       ? C.onAccent(modal.theme)
                                       : (modal.theme ? modal.theme.accent : "#3478F6")
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: modal.updateState !== "launching" && modal.updateState !== "checking"
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modal.updateRunRequested()
                            }
                        }
                    }

                    // Status line - varies with updateState.
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: 11
                        visible: text !== ""
                        color: modal.updateState === "error" || modal.updateState === "dirty"
                               ? Qt.rgba(0.93, 0.42, 0.42, 1)
                               : (modal.updateState === "available" ? modal._fg(0.9) : modal._fg(0.5))
                        text: {
                            switch (modal.updateState) {
                            case "checking":  return "Checking GitHub…"
                            case "uptodate":  return "You're on the latest release."
                            case "available": return (modal.latestVersion || "A new release")
                                                     + " is available"
                                                     + (modal.commitsBehind > 0
                                                        ? " (" + modal.commitsBehind
                                                          + (modal.commitsBehind === 1 ? " change)." : " changes).")
                                                        : ".")
                            case "dirty":     return "Local changes block the update. Commit or discard them, then retry:"
                            case "error":     return modal.updateError
                            case "launching": return "Updating in a terminal - the dashboard reloads itself when it's done."
                            default:          return ""
                            }
                        }
                    }

                    // Incoming commit subjects (when behind) or dirty file
                    // list (when blocked).
                    Column {
                        width: parent.width
                        spacing: 2
                        visible: (modal.updateState === "available" && modal.incomingLog.length > 0)
                                 || (modal.updateState === "dirty" && modal.dirtyFiles.length > 0)
                        Repeater {
                            model: modal.updateState === "dirty"
                                   ? modal.dirtyFiles
                                   : modal.incomingLog.slice(0, 6)
                            delegate: Text {
                                required property var modelData
                                width: parent.width
                                text: "• " + modelData
                                color: modal._fg(0.5)
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            visible: modal.updateState === "available" && modal.incomingLog.length > 6
                            text: "• …and " + (modal.incomingLog.length - 6) + " more"
                            color: modal._fg(0.35)
                            font.pixelSize: 10
                        }
                    }

                    // Read the release notes on GitHub before updating.
                    Text {
                        visible: modal.updateState === "available"
                                 && modal.repoWeb !== "" && modal.latestVersion !== ""
                        text: "Read the release notes ↗"
                        color: modal.theme ? modal.theme.accent : "#3478F6"
                        font.pixelSize: 11
                        MouseArea {
                            anchors { fill: parent; margins: -4 }
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally(
                                modal.repoWeb + "/releases/tag/" + modal.latestVersion)
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Updates to the newest tagged release of "
                          + "github.com/D3m0nZOnFire/omarchy-dashboard, installs any new dependencies "
                          + "and re-syncs the post-boot autostart hook. A terminal opens for "
                          + "the steps that need your password. Refused if you have local edits to "
                          + "tracked files."
                    color: modal._fg(0.35)
                    font.pixelSize: 10
                }
            }
        }
    }
}
