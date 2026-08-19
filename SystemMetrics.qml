import QtQuick
import Quickshell.Io

Item {
    id: root

    // ── CPU ──────────────────────────────────────
    property real cpuPercent:     0
    property var  corePercents:   []
    property var  cpuHistory:     []
    property real cpuPackageTemp: 0
    property real cpuMaxCoreTemp: 0

    // ── Memory ───────────────────────────────────
    property real ramUsedGB:  0
    property real ramTotalGB: 0
    property real ramPercent: 0
    property var  ramHistory: []

    // ── GPU ──────────────────────────────────────
    property string gpuName:   ""
    property int  gpuPercent:  0
    property int  vramUsedMB:  0
    property int  vramTotalMB: 0
    property int  gpuTempC:    0
    property real gpuPowerW:   0
    property var  gpuHistory:  []

    // ── Network ──────────────────────────────────
    property real netRxKBs:     0
    property real netTxKBs:     0
    property var  netRxHistory: []
    property var  netTxHistory: []

    // ── Disk ─────────────────────────────────────
    property real diskUsedGB:  0
    property real diskTotalGB: 0
    property real diskPercent: 0

    // ── Ping ─────────────────────────────────────
    property string pingHost:  "1.1.1.1"
    property real pingMs:      -1   // -1 = no reply
    property var  pingHistory: []

    // ── Private state ─────────────────────────────
    property real _prevCpuBusy:   0
    property real _prevCpuTotal:  0
    property var  _prevCoreBusy:  []
    property var  _prevCoreTotal: []
    property real _prevRxBytes:   -1
    property real _prevTxBytes:   -1
    property real _prevNetTime:   0

    readonly property int _maxHistory: 60

    // ── Processes ─────────────────────────────────

    // CPU + RAM (all cpu lines + meminfo)
    Process {
        id: cpuProc
        command: ["sh", "-c",
                  "grep '^cpu' /proc/stat && grep -E '^(MemTotal|MemAvailable)' /proc/meminfo"]
        running: false
        stdout: StdioCollector {
            id: cpuOut
            onStreamFinished: root._parseCpuMem(cpuOut.text)
        }
    }

    // GPU (util + vram + temp + power)
    // NVIDIA only. On AMD/Intel, replace this with e.g. `radeontop` or
    // sysfs reads and adjust _parseGpu() accordingly.
    Process {
        id: gpuProc
        command: ["nvidia-smi",
                  "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw",
                  "--format=csv,noheader,nounits"]
        running: false
        stdout: StdioCollector {
            id: gpuOut
            onStreamFinished: root._parseGpu(gpuOut.text)
        }
    }

    // Network counters
    Process {
        id: netProc
        command: ["cat", "/proc/net/dev"]
        running: false
        stdout: StdioCollector {
            id: netOut
            onStreamFinished: root._parseNet(netOut.text)
        }
    }

    // CPU temperatures (sensors)
    Process {
        id: tempProc
        command: ["sh", "-c",
                  "sensors 2>/dev/null | grep -E '^(Package id [0-9]+|Core [0-9]+):'"]
        running: false
        stdout: StdioCollector {
            id: tempOut
            onStreamFinished: root._parseTemps(tempOut.text)
        }
    }

    // Ping
    Process {
        id: pingProc
        command: ["ping", "-c3", "-W2", "-q", root.pingHost]
        running: false
        stdout: StdioCollector {
            id: pingOut
            onStreamFinished: root._parsePing(pingOut.text)
        }
    }

    // Disk usage
    Process {
        id: diskProc
        command: ["df", "-k", "/"]
        running: false
        stdout: StdioCollector {
            id: diskOut
            onStreamFinished: root._parseDisk(diskOut.text)
        }
    }

    // ── Timers ────────────────────────────────────

    // 2s: CPU + GPU + Network
    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!cpuProc.running)  cpuProc.running  = true
            if (!gpuProc.running)  gpuProc.running  = true
            if (!netProc.running)  netProc.running  = true
        }
    }

    // 10s: temperatures + ping (ping does 3 packets ≈ 3s per run)
    Timer {
        interval: 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!tempProc.running) tempProc.running = true
            if (!pingProc.running) pingProc.running = true
        }
    }

    // 30s: disk
    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!diskProc.running) diskProc.running = true
        }
    }

    // ── Helpers ───────────────────────────────────

    function _push(arr, val) {
        const r = arr.concat([val])
        return r.length > _maxHistory ? r.slice(r.length - _maxHistory) : r
    }

    // ── Parsers ───────────────────────────────────

    function _parseCpuMem(text) {
        const lines = text.trim().split("\n")
        const newCoreBusy  = root._prevCoreBusy.slice()
        const newCoreTotal = root._prevCoreTotal.slice()
        const newPercents  = []

        for (const line of lines) {
            const parts = line.trim().split(/\s+/)
            const label = parts[0]

            if (label === "MemTotal" || label === "MemAvailable") {
                // handled below in mem block
                continue
            }

            if (!label.startsWith("cpu")) continue

            const user    = parseInt(parts[1]) || 0
            const nice    = parseInt(parts[2]) || 0
            const system  = parseInt(parts[3]) || 0
            const idle    = parseInt(parts[4]) || 0
            const iowait  = parseInt(parts[5]) || 0
            const irq     = parseInt(parts[6]) || 0
            const softirq = parseInt(parts[7]) || 0
            const steal   = parseInt(parts[8]) || 0
            const total   = user + nice + system + idle + iowait + irq + softirq + steal
            const busy    = total - idle - iowait

            if (label === "cpu") {
                // Overall CPU
                if (root._prevCpuTotal > 0) {
                    const dTotal = total - root._prevCpuTotal
                    const dBusy  = busy  - root._prevCpuBusy
                    if (dTotal > 0)
                        root.cpuPercent = Math.min(100, Math.round(dBusy / dTotal * 100))
                }
                root._prevCpuTotal = total
                root._prevCpuBusy  = busy
                root.cpuHistory = _push(root.cpuHistory, root.cpuPercent)
            } else {
                // Per-core: label = "cpu0", "cpu1", ...
                const idx = parseInt(label.substring(3))
                if (isNaN(idx)) continue

                // Grow arrays if needed
                while (newCoreBusy.length  <= idx) newCoreBusy.push(0)
                while (newCoreTotal.length <= idx) newCoreTotal.push(0)

                const prevBusy  = newCoreBusy[idx]
                const prevTotal = newCoreTotal[idx]
                let pct = 0
                if (prevTotal > 0) {
                    const dTotal = total - prevTotal
                    const dBusy  = busy  - prevBusy
                    if (dTotal > 0)
                        pct = Math.min(100, Math.round(dBusy / dTotal * 100))
                }
                newCoreBusy[idx]  = busy
                newCoreTotal[idx] = total

                // Fill sparse core numbering (e.g. Arrow Lake has non-contiguous IDs)
                while (newPercents.length <= idx) newPercents.push(0)
                newPercents[idx] = pct
            }
        }

        // Compact: remove trailing zeros caused by non-contiguous IDs
        // Actually keep all so indices stay stable; just filter out unused slots
        // (slots that never had data remain 0 which is fine visually)
        root._prevCoreBusy  = newCoreBusy
        root._prevCoreTotal = newCoreTotal
        // Trim to the last non-zero index so we don't show phantom cores
        let lastReal = newPercents.length - 1
        while (lastReal > 0 && newCoreTotal[lastReal] === 0) lastReal--
        root.corePercents = newPercents.slice(0, lastReal + 1)

        // Memory lines
        let memTotal = 0, memAvail = 0
        for (const line of lines) {
            const m = line.match(/^(\w+):\s+(\d+)/)
            if (!m) continue
            if (m[1] === "MemTotal")     memTotal = parseInt(m[2])
            if (m[1] === "MemAvailable") memAvail = parseInt(m[2])
        }
        if (memTotal > 0) {
            root.ramTotalGB = Math.round(memTotal / 1048576 * 10) / 10
            root.ramUsedGB  = Math.round((memTotal - memAvail) / 1048576 * 10) / 10
            root.ramPercent = Math.round((memTotal - memAvail) / memTotal * 100)
            root.ramHistory = _push(root.ramHistory, root.ramPercent)
        }
    }

    function _parseGpu(text) {
        // "NVIDIA GeForce RTX 5070, 0, 119, 8151, 44, 4.31"
        const parts = text.trim().split(",").map(s => s.trim())
        if (parts.length >= 6 && !isNaN(parseInt(parts[1]))) {
            root.gpuName     = parts[0].replace(/NVIDIA /i, "").replace(/GeForce /i, "")
            root.gpuPercent  = parseInt(parts[1])
            root.vramUsedMB  = parseInt(parts[2])
            root.vramTotalMB = parseInt(parts[3])
            root.gpuTempC    = parseInt(parts[4])
            root.gpuPowerW   = parseFloat(parts[5])
            root.gpuHistory  = _push(root.gpuHistory, root.gpuPercent)
        }
    }

    function _parseNet(text) {
        const lines = text.split("\n")
        let rx = 0, tx = 0
        let found = false
        for (const line of lines) {
            const trimmed = line.trim()
            const colon   = trimmed.indexOf(":")
            if (colon < 0) continue
            const iface = trimmed.substring(0, colon).trim()
            if (iface === "lo") continue
            if (iface.startsWith("virbr")     || iface.startsWith("docker") ||
                iface.startsWith("veth")      || iface.startsWith("br-")    ||
                iface.startsWith("tun")       || iface.startsWith("tap")    ||
                iface.startsWith("tailscale")) continue
            const fields = trimmed.substring(colon + 1).trim().split(/\s+/)
            if (fields.length >= 9) {
                rx += parseFloat(fields[0])
                tx += parseFloat(fields[8])
                found = true
            }
        }
        if (!found) return
        const now = Date.now() / 1000
        if (root._prevRxBytes >= 0 && root._prevNetTime > 0) {
            const elapsed = now - root._prevNetTime
            if (elapsed > 0) {
                root.netRxKBs = Math.max(0, (rx - root._prevRxBytes) / elapsed / 1024)
                root.netTxKBs = Math.max(0, (tx - root._prevTxBytes) / elapsed / 1024)
            }
        }
        root._prevRxBytes = rx; root._prevTxBytes = tx; root._prevNetTime = now
        root.netRxHistory = _push(root.netRxHistory, root.netRxKBs)
        root.netTxHistory = _push(root.netTxHistory, root.netTxKBs)
    }

    function _parseTemps(text) {
        const lines = text.trim().split("\n")
        let pkgTemp  = 0
        let maxCore  = 0
        for (const line of lines) {
            const m = line.match(/\+(\d+\.\d+)°C/)
            if (!m) continue
            const t = parseFloat(m[1])
            if (line.startsWith("Package id")) {
                pkgTemp = t
            } else if (line.startsWith("Core")) {
                if (t > maxCore) maxCore = t
            }
        }
        if (pkgTemp > 0) root.cpuPackageTemp = pkgTemp
        if (maxCore > 0) root.cpuMaxCoreTemp = maxCore
    }

    function _parsePing(text) {
        // rtt min/avg/max/mdev = 14.x/60.x/100.x/y ms  — use avg (2nd value)
        const m = text.match(/rtt[^=]*=\s*[\d.]+\/([\d.]+)/)
        root.pingMs = m ? parseFloat(m[1]) : -1
        root.pingHistory = _push(root.pingHistory, root.pingMs < 0 ? 0 : root.pingMs)
    }

    function _parseDisk(text) {
        const lines = text.trim().split("\n").filter(l => l.trim().length > 0)
        if (lines.length < 2) return
        const parts    = lines[lines.length - 1].trim().split(/\s+/)
        let totalIdx, usedIdx
        if (parts.length >= 6) { totalIdx = 1; usedIdx = 2 }
        else if (parts.length >= 5) { totalIdx = 0; usedIdx = 1 }
        else return
        const total1k = parseInt(parts[totalIdx])
        const used1k  = parseInt(parts[usedIdx])
        if (!isNaN(total1k) && total1k > 0) {
            root.diskTotalGB = Math.round(total1k / 1048576 * 10) / 10
            root.diskUsedGB  = Math.round(used1k  / 1048576 * 10) / 10
            root.diskPercent = Math.round(used1k / total1k * 100)
        }
    }

}
