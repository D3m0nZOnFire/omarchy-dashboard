import QtQuick

Canvas {
    id: root

    property var values: []         // primary data series
    property var values2: []        // optional secondary series
    property real maxValue: 100     // y-axis ceiling; set to 0 for auto
    property color lineColor:  "#3478F6"
    property color lineColor2: "#FF9F0A"
    property real lineThickness: 1.5

    height: 36

    onValuesChanged:    requestPaint()
    onValues2Changed:   requestPaint()
    onMaxValueChanged:  requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)

        const data = root.values
        if (!data || data.length < 2) return

        const maxV = root.maxValue > 0 ? root.maxValue : 1
        const pad  = 2
        const dw   = width  - pad * 2
        const dh   = height - pad * 2
        const n    = data.length

        function xAt(i)  { return pad + (i / (n - 1)) * dw }
        function yAt(v)  { return pad + dh - (Math.min(Math.max(v, 0), maxV) / maxV) * dh }

        // Filled area under primary line
        const gc = root.lineColor
        const grad = ctx.createLinearGradient(0, pad, 0, height - pad)
        grad.addColorStop(0, Qt.rgba(gc.r, gc.g, gc.b, 0.22))
        grad.addColorStop(1, Qt.rgba(gc.r, gc.g, gc.b, 0.02))

        ctx.beginPath()
        ctx.moveTo(xAt(0), height - pad)
        for (let i = 0; i < n; i++) ctx.lineTo(xAt(i), yAt(data[i]))
        ctx.lineTo(xAt(n - 1), height - pad)
        ctx.closePath()
        ctx.fillStyle = grad
        ctx.fill()

        // Primary line
        ctx.beginPath()
        ctx.moveTo(xAt(0), yAt(data[0]))
        for (let i = 1; i < n; i++) ctx.lineTo(xAt(i), yAt(data[i]))
        ctx.strokeStyle = root.lineColor
        ctx.lineWidth   = root.lineThickness
        ctx.lineJoin    = "round"
        ctx.lineCap     = "round"
        ctx.stroke()

        // Secondary line (optional, e.g. TX alongside RX)
        const d2 = root.values2
        if (d2 && d2.length >= 2) {
            const n2 = d2.length
            function x2(i) { return pad + (i / (n2 - 1)) * dw }
            function y2(v) { return pad + dh - (Math.min(Math.max(v, 0), maxV) / maxV) * dh }

            ctx.beginPath()
            ctx.moveTo(x2(0), y2(d2[0]))
            for (let i = 1; i < n2; i++) ctx.lineTo(x2(i), y2(d2[i]))
            ctx.strokeStyle = root.lineColor2
            ctx.lineWidth   = root.lineThickness
            ctx.lineJoin    = "round"
            ctx.lineCap     = "round"
            ctx.stroke()
        }
    }
}
