import QtQuick

// Sunrise/sunset curve for the Sun tile. A 24h window centred on solar noon:
// the day hump sits in the middle, above the horizon, with half of the night
// dipping below on each side (pre-dawn on the left, evening on the right).
// The glowing dot tracks the sun's real position.
Canvas {
    id: root

    property var sunrise: null   // Date (today's sunrise)
    property var sunset:  null   // Date (today's sunset)
    property var now:     null   // Date

    property color arcColor:  Qt.rgba(1, 1, 1, 0.22)
    property color lineColor: Qt.rgba(1, 1, 1, 0.13)
    property color sunColor:  "#F5B841"

    implicitHeight: 84

    onSunriseChanged:   requestPaint()
    onSunsetChanged:    requestPaint()
    onNowChanged:       requestPaint()
    onArcColorChanged:  requestPaint()
    onLineColorChanged: requestPaint()
    onSunColorChanged:  requestPaint()
    onWidthChanged:     requestPaint()
    onHeightChanged:    requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        var w = width, h = height
        var horizon = h * 0.48
        var amp = h * 0.34

        // Horizon line
        ctx.beginPath()
        ctx.moveTo(0, horizon)
        ctx.lineTo(w, horizon)
        ctx.strokeStyle = root.lineColor
        ctx.lineWidth = 1
        ctx.stroke()

        if (!root.sunrise || !root.sunset || !root.now) return
        var sr = root.sunrise.getTime()
        var ss = root.sunset.getTime()
        var dayMs = ss - sr
        var DAY = 24 * 3600 * 1000
        if (!(dayMs > 0) || dayMs >= DAY) return
        var nightMs = DAY - dayMs
        var noonMs = (sr + ss) / 2
        var halfDay = dayMs / 2

        // x-fraction 0..1 spans (noon - 12h) .. (noon + 12h). `dt` is ms from
        // solar noon. Solar angle: PI/2 at noon (peak), 0 at sunrise, PI at
        // sunset, and -PI/2 / 3PI/2 (trough) at the two edges = solar midnight.
        function angleForDt(dt) {
            if (dt >= -halfDay && dt <= halfDay)
                return Math.PI / 2 + Math.PI * dt / dayMs
            if (dt > halfDay)
                return Math.PI + Math.PI * (dt - halfDay) / nightMs
            return -Math.PI * (-halfDay - dt) / nightMs
        }
        function curveY(xf) {
            return horizon - Math.sin(angleForDt((xf - 0.5) * DAY)) * amp
        }

        // The curve
        ctx.beginPath()
        var steps = 120
        for (var i = 0; i <= steps; i++) {
            var xf = i / steps
            var x = xf * w
            var y = curveY(xf)
            if (i === 0) ctx.moveTo(x, y)
            else ctx.lineTo(x, y)
        }
        ctx.strokeStyle = root.arcColor
        ctx.lineWidth = 2
        ctx.stroke()

        // Sun: time from solar noon, wrapped into the -12h..+12h window.
        var dtNow = ((root.now.getTime() - noonMs) % DAY + DAY + DAY / 2) % DAY - DAY / 2
        var sunXf = 0.5 + dtNow / DAY
        var sx = sunXf * w
        var sy = curveY(sunXf)
        var down = sy > horizon + 0.5

        // Glow (dimmer once the sun is below the horizon)
        var glowR = down ? 11 : 15
        var g = ctx.createRadialGradient(sx, sy, 0, sx, sy, glowR)
        g.addColorStop(0, Qt.rgba(root.sunColor.r, root.sunColor.g, root.sunColor.b, down ? 0.16 : 0.5))
        g.addColorStop(1, Qt.rgba(root.sunColor.r, root.sunColor.g, root.sunColor.b, 0))
        ctx.fillStyle = g
        ctx.beginPath()
        ctx.arc(sx, sy, glowR, 0, 2 * Math.PI)
        ctx.fill()

        // Sun disc (smaller and faded when it's down)
        ctx.fillStyle = down
            ? Qt.rgba(root.sunColor.r, root.sunColor.g, root.sunColor.b, 0.55)
            : root.sunColor
        ctx.beginPath()
        ctx.arc(sx, sy, down ? 3.5 : 5, 0, 2 * Math.PI)
        ctx.fill()
    }
}
