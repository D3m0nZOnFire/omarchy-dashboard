import QtQuick
import Quickshell.Io

// Resolves the current Omarchy theme palette (via `omarchy-theme-color --all`)
// and keeps it live-updated: watches ~/.local/state/omarchy/current for the
// directory swap that `omarchy-theme-set` does on every theme change, and
// re-resolves the palette whenever that happens. No restart needed.
Item {
    id: root

    property string mode: "dark"

    property color accent:  "#3478F6"
    property color red:     "#FF453A"
    property color orange:  "#FF9F0A"
    property color yellow:  "#FF9F0A"
    property color green:   "#30D158"
    property color cyan:    "#64D2FF"
    property color blue:    "#3478F6"
    property color magenta: "#BF5AF2"

    property color brightCyan:    cyan
    property color brightMagenta: magenta

    function _apply(map) {
        if (!map.accent) return   // incomplete read (e.g. mid theme-swap) — ignore
        mode          = map.mode          || mode
        accent        = map.accent        || accent
        red           = map.red           || red
        orange        = map.orange        || orange
        yellow        = map.yellow        || yellow
        green         = map.green         || green
        cyan          = map.cyan          || cyan
        blue          = map.blue          || blue
        magenta       = map.magenta       || magenta
        brightCyan    = map.bright_cyan    || cyan
        brightMagenta = map.bright_magenta || magenta
    }

    function _parse(text) {
        const map = {}
        const lines = text.split("\n")
        for (const line of lines) {
            const tab = line.indexOf("\t")
            if (tab < 0) continue
            map[line.substring(0, tab)] = line.substring(tab + 1).trim()
        }
        _apply(map)
    }

    // Emits the resolved palette once immediately, then again every time the
    // active theme directory is swapped in.
    Process {
        command: ["sh", "-c",
            "omarchy-theme-color --all; printf '\\n___THEME_EOF___\\n'; " +
            "inotifywait --monitor --quiet -e close_write -e moved_to -e create -e delete " +
            "\"$HOME/.local/state/omarchy/current\" 2>/dev/null | " +
            "while read -r _; do omarchy-theme-color --all; printf '\\n___THEME_EOF___\\n'; done"
        ]
        running: true
        stdout: SplitParser {
            splitMarker: "___THEME_EOF___\n"
            onRead: data => root._parse(data)
        }
    }
}
