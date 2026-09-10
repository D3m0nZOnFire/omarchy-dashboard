.pragma library

// Perceived brightness of a color (0..1), Rec. 601 weights.
function luminance(c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
}

// Readable text/icon color for content sitting on `accent` - returns
// whichever of foreground / background contrasts more with the accent,
// since accent lightness varies a lot from theme to theme.
function onAccent(theme, fallback) {
    if (!theme) return fallback === undefined ? Qt.rgba(1, 1, 1, 1) : fallback
    var a = luminance(theme.accent)
    var f = luminance(theme.foreground)
    var b = luminance(theme.background)
    return Math.abs(f - a) >= Math.abs(b - a) ? theme.foreground : theme.background
}

// Theme foreground at a given alpha, with a white fallback when no theme
// is set yet.
function fg(theme, a) {
    var alpha = a === undefined ? 1 : a
    if (!theme) return Qt.rgba(1, 1, 1, alpha)
    return Qt.rgba(theme.foreground.r, theme.foreground.g, theme.foreground.b, alpha)
}

// Theme accent at a given alpha (used for selected-state tints).
function accent(theme, a) {
    var alpha = a === undefined ? 1 : a
    if (!theme) return Qt.rgba(0.20, 0.47, 0.96, alpha)
    return Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, alpha)
}
