import QtQuick
import Quickshell
import Quickshell.Io

// Shared weather data source for the Weather and Sun tiles. Mirrors what the
// Omarchy bar weather widget does so the numbers and icon stay in sync:
//
//  - location from ~/.local/state/omarchy/settings/weather.json (same file)
//  - with coordinates set, current conditions come from Open-Meteo (exactly
//    what the bar uses); the weather-code icon is the same Nerd Font glyph
//  - wttr.in still supplies the area name and today's sunrise/sunset, and is
//    the fallback for current conditions when no coordinates are stored
Item {
    id: root

    // ── Public state ──────────────────────────────
    property bool   ready:           false
    property string tempC:           ""
    property string feelsC:          ""
    property string humidity:        ""
    property string windKmph:        ""
    property string desc:            ""
    property int    weatherCode:     113
    property string displayLocation: ""
    property string sunriseStr:      ""
    property string sunsetStr:       ""
    property var    sunriseDate:     null
    property var    sunsetDate:      null

    // Configured location name (echoed to the settings modal). "" = auto.
    property string locName: ""
    property var _lat: null
    property var _lon: null

    readonly property bool _hasCoords: _lat !== null && _lon !== null && !isNaN(_lat) && !isNaN(_lon)
    // Open-Meteo state (preferred when coordinates are configured).
    property bool _usesOpenMeteo: false
    property int  _omCode: 0
    property var  _omIsDay: null

    // Weather-code icon as an Omarchy-style Nerd Font glyph (same mapping the
    // bar uses). Render it with Theme.monoFamily.
    readonly property string iconGlyph: {
        var night = (_omIsDay !== null) ? (_omIsDay === 0) : !isDay
        return _usesOpenMeteo ? root._glyphForOpenMeteo(_omCode, night)
                              : root._glyphForWttr(weatherCode, night)
    }

    // Ticks once a minute so the sun position / day-night state stay current
    // without a fresh network fetch.
    property date now: new Date()

    readonly property bool isDay: {
        if (!sunriseDate || !sunsetDate) return true
        var t = now.getTime()
        return t >= sunriseDate.getTime() && t < sunsetDate.getTime()
    }

    // wttr.in path segment: coordinates when known, else the encoded name,
    // else empty (server-side IP auto-detect).
    readonly property string wttrQuery: {
        if (_hasCoords) return _lat + "," + _lon
        if (locName !== "") return encodeURIComponent(locName)
        return ""
    }
    onWttrQueryChanged: {
        // New location: drop the old source preference so stale data can't stick.
        root._usesOpenMeteo = false
        root._omIsDay = null
        Qt.callLater(refresh)
    }

    property int _retries: 0

    // ── Location file (shared with the Omarchy weather widget) ─────
    FileView {
        id: locFile
        path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
        watchChanges: true
        printErrors: false
        onLoaded:      root._parseLocation(locFile.text())
        onLoadFailed:  root._parseLocation("")
        onFileChanged: locFile.reload()
    }

    // The first read can race shell startup; one delayed reload self-corrects
    // and is a no-op if the first read was already fine.
    Timer {
        interval: 1500
        running: true
        onTriggered: locFile.reload()
    }

    function _parseLocation(txt) {
        var name = "", lat = null, lon = null
        try {
            var o = JSON.parse(txt)
            if (o && typeof o.name === "string") name = o.name
            if (o && o.latitude !== undefined && o.longitude !== undefined) {
                lat = parseFloat(o.latitude)
                lon = parseFloat(o.longitude)
            }
        } catch (e) {}
        root.locName = name
        root._lat = lat
        root._lon = lon
    }

    // ── Fetch ─────────────────────────────────────
    function refresh() {
        root._retries = 0
        if (!wttrProc.running) wttrProc.running = true
        if (root._hasCoords && !omProc.running) omProc.running = true
    }

    // wttr.in - area name, sunrise/sunset, and fallback conditions.
    Process {
        id: wttrProc
        running: false
        command: ["curl", "-fsS", "--max-time", "10",
                  "https://wttr.in/" + root.wttrQuery + "?format=j1"]
        stdout: StdioCollector {
            id: wttrOut
            onStreamFinished: root._parseWeather(wttrOut.text)
        }
    }

    // Open-Meteo - current conditions, exactly what the Omarchy bar shows.
    Process {
        id: omProc
        running: false
        command: ["curl", "-fsS", "--max-time", "8",
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + root._lat + "&longitude=" + root._lon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
            + "&timezone=auto"]
        stdout: StdioCollector {
            id: omOut
            onStreamFinished: root._parseOpenMeteo(omOut.text)
        }
    }

    function _parseWeather(txt) {
        var raw = String(txt || "").trim()
        if (!raw) { root._scheduleRetry(); return }
        try {
            var d = JSON.parse(raw)
            var cur = d.current_condition && d.current_condition[0]
            if (!cur) { root._scheduleRetry(); return }

            // Only fill conditions from wttr until Open-Meteo answers (or if
            // there are no coordinates, in which case wttr is the source).
            if (!root._usesOpenMeteo) {
                root.tempC       = String(parseInt(cur.temp_C))
                root.feelsC      = String(parseInt(cur.FeelsLikeC))
                root.humidity    = String(parseInt(cur.humidity))
                root.windKmph    = String(parseInt(cur.windspeedKmph))
                root.weatherCode = parseInt(cur.weatherCode) || 0
            }
            root.desc = (cur.weatherDesc && cur.weatherDesc[0] && cur.weatherDesc[0].value) || ""

            var area = d.nearest_area && d.nearest_area[0]
            var areaName = area && area.areaName && area.areaName[0] ? area.areaName[0].value : ""
            root.displayLocation = root.locName || areaName

            var astro = d.weather && d.weather[0] && d.weather[0].astronomy && d.weather[0].astronomy[0]
            if (astro) {
                root.sunriseDate = root._parseClock(astro.sunrise)
                root.sunsetDate  = root._parseClock(astro.sunset)
                root.sunriseStr  = root._fmt24(root.sunriseDate) || astro.sunrise || ""
                root.sunsetStr   = root._fmt24(root.sunsetDate)  || astro.sunset  || ""
            }

            root._retries = 0
            root.ready = true
        } catch (e) {
            root._scheduleRetry()
        }
    }

    function _parseOpenMeteo(txt) {
        var raw = String(txt || "").trim()
        if (!raw) return
        try {
            var d = JSON.parse(raw)
            var c = d.current
            if (!c || c.temperature_2m === undefined || c.temperature_2m === null) return

            root.tempC    = String(Math.round(c.temperature_2m))
            root.feelsC   = String(Math.round(c.apparent_temperature))
            root.humidity = String(Math.round(c.relative_humidity_2m))
            root.windKmph = String(Math.round(c.wind_speed_10m))
            root._omCode  = parseInt(c.weather_code) || 0
            root._omIsDay = Number(c.is_day)
            root._usesOpenMeteo = true
            root.ready = true
        } catch (e) {}
    }

    function _scheduleRetry() {
        if (root._retries >= 3) return
        root._retries++
        retryTimer.restart()
    }

    // wttr.in code -> Nerd Font weather glyph (Omarchy Model.js iconForCode).
    function _glyphForWttr(code, night) {
        switch (parseInt(code) || 0) {
        case 113: return night ? "\ue32b" : "\ue30d"
        case 116: return night ? "\ue32e" : "\ue302"
        case 119: case 122: return "\ue33d"
        case 143: case 248: case 260: return night ? "\ue346" : "\ue313"
        case 176: case 263: case 353: return night ? "\ue333" : "\ue308"
        case 179: case 227: case 230: case 323: case 326: case 368: return night ? "\ue327" : "\ue30a"
        case 182: case 185: case 281: case 284: case 311: case 314:
        case 317: case 320: case 350: case 362: case 365: case 374: case 377: return "\ue3ad"
        case 200: case 386: case 389: case 392: case 395: return "\ue31d"
        case 266: case 293: case 296: case 299: case 302: case 305: case 308: case 356: case 359: return "\ue318"
        case 329: case 332: case 335: case 338: case 371: return "\ue31a"
        default: return "\ue33d"
        }
    }
    // Open-Meteo WMO code -> the same glyphs (Omarchy Model.js iconForOpenMeteoCode).
    function _glyphForOpenMeteo(code, night) {
        var c = parseInt(code) || 0
        if (c === 0) return _glyphForWttr(113, night)
        if (c === 1 || c === 2) return _glyphForWttr(116, night)
        if (c === 3) return _glyphForWttr(119, night)
        if (c === 45 || c === 48) return _glyphForWttr(143, night)
        if (c === 51 || c === 53 || c === 55 || c === 56 || c === 57 || c === 61) return _glyphForWttr(266, night)
        if (c === 63 || c === 65 || c === 66 || c === 67 || c === 80 || c === 81 || c === 82) return _glyphForWttr(308, night)
        if (c === 71 || c === 73 || c === 75 || c === 77 || c === 85 || c === 86) return _glyphForWttr(338, night)
        if (c === 95 || c === 96 || c === 99) return _glyphForWttr(389, night)
        return _glyphForWttr(119, night)
    }

    // Date → "19:54" (24-hour, zero-padded).
    function _fmt24(d) {
        if (!d) return ""
        return ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2)
    }

    // "07:03 AM" → a Date for today at that local time.
    function _parseClock(s) {
        if (!s) return null
        var m = String(s).trim().match(/^(\d{1,2}):(\d{2})\s*([AP]M)?$/i)
        if (!m) return null
        var h = parseInt(m[1])
        var min = parseInt(m[2])
        var ap = (m[3] || "").toUpperCase()
        if (ap === "PM" && h < 12) h += 12
        if (ap === "AM" && h === 12) h = 0
        var d = new Date()
        d.setHours(h, min, 0, 0)
        return d
    }

    Timer {
        id: retryTimer
        interval: 2500
        onTriggered: if (!wttrProc.running) wttrProc.running = true
    }

    // Periodic refresh.
    Timer {
        interval: 15 * 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Minute clock for the sun position.
    Timer {
        interval: 60 * 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }
}
