import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell.Io

Item {
    id: root
    implicitHeight: col.implicitHeight

    // Passed from parent for live RAM/GPU reading and theming
    property string ramInfo:    "— GB"
    property string gpuInfo:    "—"
    property color  accentColor: "#1793D1"   // default = Arch blue
    property color  textColor:   "white"

    // ── Dynamic state ──────────────────────────────────────────
    property string _hostname: ""
    property string _kernel:   ""
    property string _cpu:      ""
    property string _uptime:   ""
    property string _theme: "—"

    // Reads theme immediately then watches for changes via inotifywait
    Process {
        id: themeWatcher
        command: ["sh", "-c",
            "cat ~/.local/state/omarchy/current/theme.name 2>/dev/null; " +
            "inotifywait --monitor --quiet -e close_write " +
            "~/.local/state/omarchy/current/theme.name 2>/dev/null | " +
            "while read -r _; do cat ~/.local/state/omarchy/current/theme.name; done"
        ]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const raw = data.trim()
                if (raw !== "")
                    root._theme = raw.replace(/-/g, " ")
                        .replace(/\b\w/g, c => c.toUpperCase())
            }
        }
    }

    // Fetch static info in one shot
    Process {
        id: infoProc
        command: ["sh", "-c",
            "echo HOST:$(hostname); " +
            "uname -r | sed 's/^/KERNEL:/'; " +
            "grep -m1 '^model name' /proc/cpuinfo | sed 's/model name.*: /CPU:/'"
        ]
        running: true
        stdout: StdioCollector {
            id: infoOut
            onStreamFinished: {
                const lines = infoOut.text.trim().split("\n")
                for (const l of lines) {
                    if (l.startsWith("HOST:"))   root._hostname = l.substring(5).trim()
                    if (l.startsWith("KERNEL:")) root._kernel   = l.substring(7).trim()
                    if (l.startsWith("CPU:"))    root._cpu      = l.substring(4)
                        .replace(/\(R\)/g,"").replace(/\(TM\)/g,"")
                        .replace(/\s+/g," ").trim()
                }
            }
        }
    }

    // Uptime (refresh every 60 s)
    Process {
        id: uptimeProc
        command: ["sh", "-c",
            "awk '{s=int($1); d=int(s/86400); h=int((s%86400)/3600); m=int((s%3600)/60); " +
            "if(d>=1) printf \"%dd %dh %dm\",d,h,m; " +
            "else if(h>=1) printf \"%dh %dm\",h,m; " +
            "else printf \"%dm\",m}' /proc/uptime"
        ]
        running: true
        stdout: StdioCollector {
            id: uptimeOut
            onStreamFinished: root._uptime = uptimeOut.text.trim()
        }
    }

    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: { if (!uptimeProc.running) uptimeProc.running = true }
    }

    // ── Layout ─────────────────────────────────────────────────
    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right }
        spacing: 12

        // ── Header ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // Omarchy logo — recolored to the active theme's accent
            Item {
                width: 72; height: 72

                Image {
                    id: omarchyLogo
                    anchors.fill: parent
                    source: "file:///usr/share/omarchy/icon.png"
                    fillMode: Image.PreserveAspectFit
                    sourceSize: Qt.size(72, 72)
                    visible: false
                }
                ColorOverlay {
                    anchors.fill: omarchyLogo
                    source: omarchyLogo
                    color: root.accentColor
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    text: root._hostname || "—"
                    color: root.textColor
                    font.pixelSize: 20
                    font.weight: Font.SemiBold ?? 63
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    text: "arch@" + (root._hostname || "—")
                    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.35)
                    font.pixelSize: 10
                }

            }
        }

        // Separator
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.08)
        }

        // ── Info grid ────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 6
            columnSpacing: 10

            // Row helper: label uses Arch blue, value uses white
            // Listed in classic neofetch order

            Text { text: "OS";         color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text { text: "Arch Linux"; color: root.textColor;   font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }

            Text { text: "Kernel";     color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text { text: root._kernel || "—"; color: root.textColor; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }

            Text { text: "Uptime";     color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text { text: root._uptime || "—"; color: root.textColor; font.pixelSize: 11; Layout.fillWidth: true }

            Text { text: "WM";         color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text { text: "Hyprland";   color: root.textColor;   font.pixelSize: 11 }

            Text { text: "Theme";      color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text { text: root._theme;  color: root.textColor;   font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }

            Text { text: "CPU";        color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text {
                text: root._cpu || "—"
                color: root.textColor; font.pixelSize: 11
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Text { text: "GPU";        color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text { text: root.gpuInfo; color: root.textColor; font.pixelSize: 11; Layout.fillWidth: true; elide: Text.ElideRight }

            Text { text: "Memory";     color: accentColor; font.pixelSize: 11; font.weight: Font.Medium }
            Text { text: root.ramInfo; color: root.textColor;   font.pixelSize: 11; Layout.fillWidth: true }
        }
    }
}
