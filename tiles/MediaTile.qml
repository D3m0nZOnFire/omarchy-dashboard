import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris
import ".."

// Media (Mpris "Now Playing") tile, loaded through shell.qml's tileMap.
StatCard {
    id: mediaCard
    property var shell

    theme: shell._theme
    Layout.fillWidth: true

    // Bumped whenever the player list or a player's playing
    // state changes, to force activePlayer to re-pick - see
    // the Connections/Instantiator below. Per-track fields
    // (title, position, art, ...) update on their own via
    // normal property bindings once a player is selected.
    property int _mpTick: 0
    property var activePlayer: {
        _mpTick // qmllint disable confusing-expression-statement
        // stock Quickshell 0.3.2's type info lacks ObjectModel.values
        // qmllint disable missing-property
        const list = Mpris.players ? Mpris.players.values : []
        // qmllint enable missing-property
        for (var i = 0; i < list.length; i++) if (list[i].isPlaying) return list[i]
        for (var i = 0; i < list.length; i++) if (list[i].trackTitle) return list[i]
        return null
    }
    readonly property bool hasMedia: activePlayer !== null &&
        (activePlayer.trackTitle !== "" || activePlayer.trackArtist !== "")

    label: "Media" + (hasMedia && activePlayer.identity ? " · " + activePlayer.identity : "")

    // `Mpris.players` is a constant model reference (no
    // playersChanged signal) - a player appearing/disappearing
    // is instead caught by this delegate's own creation/
    // destruction, alongside isPlaying flips on existing ones.
    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onIsPlayingChanged() { if (mediaCard) mediaCard._mpTick++ }
            Component.onCompleted: { if (mediaCard) mediaCard._mpTick++ }
            // Guarded: if the whole tile is being torn down
            // (e.g. hidden via the reorder modal), mediaCard
            // may already be gone by the time this fires.
            Component.onDestruction: { if (mediaCard) mediaCard._mpTick++ }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: !mediaCard.hasMedia
        text: "Nothing playing"
        color: shell._fg(0.35)
        font.pixelSize: 12
        font.italic: true
    }

    RowLayout {
        Layout.fillWidth: true
        visible: mediaCard.hasMedia
        spacing: 10

        ClippingRectangle {
            Layout.preferredWidth: 56; Layout.preferredHeight: 56
            radius: 8
            color: shell._fg(0.06)

            Image {
                anchors.fill: parent
                source: mediaCard.activePlayer && mediaCard.activePlayer.trackArtUrl ? mediaCard.activePlayer.trackArtUrl : ""
                // Decode at ~2x the 56x56 display size instead of
                // whatever resolution the player's art actually is.
                sourceSize: Qt.size(112, 112)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: !(mediaCard.activePlayer && mediaCard.activePlayer.trackArtUrl)
                text: "♪"
                color: shell._fg(0.25)
                font.pixelSize: 22
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: mediaCard.activePlayer ? (mediaCard.activePlayer.trackTitle || "-") : ""
                color: shell._fg()
                font.pixelSize: 13
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                Layout.fillWidth: true
                text: mediaCard.activePlayer ? (mediaCard.activePlayer.trackArtist || "") : ""
                color: shell._fg(0.5)
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Item {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.preferredHeight: 3
                Rectangle { anchors.fill: parent; radius: 1.5; color: shell._fg(0.1) }
                Rectangle {
                    readonly property real ratio: mediaCard.activePlayer && mediaCard.activePlayer.length > 0
                        ? mediaCard.activePlayer.position / mediaCard.activePlayer.length : 0
                    width: parent.width * Math.max(0, Math.min(1, ratio))
                    height: parent.height
                    radius: 1.5
                    color: theme.accent
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: mediaCard.activePlayer ? shell._fmtDuration(mediaCard.activePlayer.position) : ""
                    color: shell._fg(0.35)
                    font.pixelSize: 9
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: mediaCard.activePlayer && mediaCard.activePlayer.length > 0 ? shell._fmtDuration(mediaCard.activePlayer.length) : ""
                    color: shell._fg(0.35)
                    font.pixelSize: 9
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: mediaCard.hasMedia
        spacing: 20

        Item { Layout.fillWidth: true }

        Text {
            text: "◀◀"
            font.pixelSize: 12
            color: mediaCard.activePlayer && mediaCard.activePlayer.canGoPrevious ? shell._fg(0.8) : shell._fg(0.2)
            MouseArea {
                anchors { fill: parent; margins: -6 }
                enabled: mediaCard.activePlayer && mediaCard.activePlayer.canGoPrevious
                cursorShape: Qt.PointingHandCursor
                onClicked: mediaCard.activePlayer.previous()
            }
        }
        Item {
            // Drawn instead of using the "⏸" glyph - that
            // codepoint defaults to colored emoji presentation
            // on most systems, clashing with the plain-text
            // triangles used everywhere else on this tile.
            Layout.preferredWidth: 15; Layout.preferredHeight: 15
            Text {
                anchors.centerIn: parent
                visible: !(mediaCard.activePlayer && mediaCard.activePlayer.isPlaying)
                text: "▶"
                font.pixelSize: 15
                color: shell._fg(0.9)
            }
            Row {
                anchors.centerIn: parent
                visible: mediaCard.activePlayer && mediaCard.activePlayer.isPlaying
                spacing: 3
                Rectangle { width: 4; height: 13; radius: 1; color: shell._fg(0.9) }
                Rectangle { width: 4; height: 13; radius: 1; color: shell._fg(0.9) }
            }
            MouseArea {
                anchors { fill: parent; margins: -6 }
                enabled: mediaCard.activePlayer && mediaCard.activePlayer.canTogglePlaying
                cursorShape: Qt.PointingHandCursor
                onClicked: mediaCard.activePlayer.togglePlaying()
            }
        }
        Text {
            text: "▶▶"
            font.pixelSize: 12
            color: mediaCard.activePlayer && mediaCard.activePlayer.canGoNext ? shell._fg(0.8) : shell._fg(0.2)
            MouseArea {
                anchors { fill: parent; margins: -6 }
                enabled: mediaCard.activePlayer && mediaCard.activePlayer.canGoNext
                cursorShape: Qt.PointingHandCursor
                onClicked: mediaCard.activePlayer.next()
            }
        }

        Item { Layout.fillWidth: true }
    }
}
