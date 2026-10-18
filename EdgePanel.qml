import QtQuick
import Quickshell
import Quickshell.Wayland

// One screen edge of the dashboard: the tiles placed on that edge
// (Settings → Layout), stacked top-to-bottom. shell.qml creates one for
// the left edge and one for the right; a panel is shown only while at
// least one tile is on its edge.
PanelWindow { // qmllint disable uncreatable-type
    id: panel

    property var shell
    property string edge: "left"     // "left" | "right"
    property var tiles: []           // tile ids, in order
    readonly property bool _right: edge === "right"

    visible:         tiles.length > 0
    screen:          shell ? shell._mainScreen : null
    anchors {        top: true; bottom: true; left: !panel._right; right: panel._right }
    implicitWidth:   tileFlow.width + 16   // 8 px margin on each side

    WlrLayershell.layer:         WlrLayer.Bottom
    WlrLayershell.namespace:     "quickshell:dashboard"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode:               ExclusionMode.Ignore
    color:                       "transparent"

    // Compositor-native blur via the ext-background-effect-v1 Wayland
    // protocol, requested straight from QML - no layer_rule needed.
    // panelBlurRegion is an empty container; _rebuildBlur fills its
    // `regions` list with each tile's own Region (see the Repeater below),
    // so only the card rectangles blur, not the gaps between them or the
    // panel's own margins. Hyprland still needs decoration.blur.enabled on
    // for the render pass itself - see shell._syncCompositorBlur.
    BackgroundEffect.blurRegion: shell && shell.blurPercent > 0 ? panelBlurRegion : null
    Region { id: panelBlurRegion }

    // One tile's wrapper. blurRegion is exposed so _rebuildBlur can collect
    // just this tile's own rectangle into the panel's blur region.
    component TileSlot: Item {
        property Region blurRegion
    }

    // Re-run whenever the tile count changes (tile added/removed/hidden/
    // moved to the other edge).
    function _rebuildBlur() {
        var arr = []
        for (var i = 0; i < tileRepeater.count; i++) {
            const slot = tileRepeater.itemAt(i) as TileSlot
            if (slot && slot.blurRegion) arr.push(slot.blurRegion)
        }
        panelBlurRegion.regions = arr
    }

    // ── Tile columns ──────────────────────────────────────────────
    // Column count is dynamic: tiles stack top-to-bottom until the
    // next one wouldn't fit the screen's height, then a new column
    // starts. Screen height is read live from `screen`, so this reflows
    // if the dashboard ever moves to a different monitor. No scrolling,
    // no clipped/unreachable tiles.
    Flow {
        id: tileFlow
        anchors {
            top: parent.top;     topMargin:   40
            left:  panel._right ? undefined : parent.left;  leftMargin:  8
            right: panel._right ? parent.right : undefined; rightMargin: 8
        }
        // stock Quickshell 0.3.2's type info lacks ShellScreen.height
        // qmllint disable missing-property
        height: Math.max(1, (panel.screen ? panel.screen.height : 1000) - 40 - 8)
        // qmllint enable missing-property
        flow: Flow.TopToBottom
        spacing: 12
        // On the right edge, mirror the layout direction so the first
        // column hugs the screen edge (like the left panel) and extra
        // columns grow inward. Only the Flow itself is mirrored, not tile
        // content.
        LayoutMirroring.enabled: panel._right
        LayoutMirroring.childrenInherit: false

        Repeater {
            id: tileRepeater
            model: panel.tiles
            onCountChanged: Qt.callLater(panel._rebuildBlur)
            delegate: TileSlot {
                id: tileWrap
                width: 296
                height: tileLoader.height
                blurRegion: tileBlurRegion
                Region { id: tileBlurRegion; item: tileWrap; radius: 16 }

                // Double-click the tile itself (not the empty panel
                // around it) to open Settings. Sits behind the loaded
                // card's own content, so any interactive control inside
                // it (e.g. the media tile's playback buttons) still
                // takes priority.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton
                    onDoubleClicked: panel.shell._reorderModal.open()
                }

                Loader {
                    id: tileLoader
                    width: parent.width
                    sourceComponent: panel.shell.tileMap[modelData]
                }
            }
        }
    }
}
