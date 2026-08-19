import QtQuick

Canvas {
    id: root

    property real value: 0          // 0–100
    property color fillColor: "#3478F6"
    property color trackColor: Qt.rgba(1, 1, 1, 0.08)
    property real lineWidth: 8
    property string centerText: Math.round(value) + "%"
    property string subText: ""    // optional second line (e.g. "44°C")

    width: 80
    height: 80

    onValueChanged:     requestPaint()
    onFillColorChanged: requestPaint()
    onSubTextChanged:   requestPaint()
    onCenterTextChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        const cx  = width  / 2
        const cy  = height / 2
        const r   = Math.min(cx, cy) - root.lineWidth / 2 - 2
        const tau = 2 * Math.PI
        const start = -Math.PI / 2   // 12 o'clock

        // Track (full circle)
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, tau)
        ctx.strokeStyle = root.trackColor
        ctx.lineWidth   = root.lineWidth
        ctx.lineCap     = "butt"
        ctx.stroke()

        // Value arc
        if (root.value > 0.5) {
            ctx.beginPath()
            ctx.arc(cx, cy, r, start, start + (root.value / 100) * tau)
            ctx.strokeStyle = root.fillColor
            ctx.lineWidth   = root.lineWidth
            ctx.lineCap     = "round"
            ctx.stroke()
        }

        // Center text
        const hasSubText = root.subText.length > 0
        ctx.textAlign    = "center"
        ctx.textBaseline = "middle"
        ctx.fillStyle    = "white"
        ctx.font         = "600 14px sans-serif"
        ctx.fillText(root.centerText, cx, cy + (hasSubText ? -7 : 0))

        if (hasSubText) {
            ctx.font      = "10px sans-serif"
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.5)
            ctx.fillText(root.subText, cx, cy + 9)
        }
    }
}
