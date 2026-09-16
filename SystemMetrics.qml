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
    property string cpuModel:     ""

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

    // ── Visibility / power gating ──────────────────
    // Set from shell.qml: each *Enabled flag tracks whether the tile that
    // consumes this data is actually placed on an edge (not hidden), so we
    // don't fork subprocesses for tiles nobody sees. onBattery slows every
    // timer down when unplugged. gpuAvailable/sensorsAvailable are detected
    // once at startup so we stop trying forever on hardware that doesn't
    // have it, instead of failing every cycle.
    property bool cpuEnabled:  true
    property bool gpuEnabled:  true
    property bool netEnabled:  true
    property bool pingEnabled: true
    property bool diskEnabled: true
    property bool onBattery:   false
    property bool gpuAvailable:     true
    property bool sensorsAvailable: true

    // Re-poll immediately when a tile is un-hidden, instead of waiting for
    // the next timer tick and showing stale/zero data in the meantime.
    onCpuEnabledChanged:  if (cpuEnabled && !cpuProc.running) cpuProc.running = true
    onGpuEnabledChanged:  if (gpuEnabled && gpuAvailable && !gpuProc.running) gpuProc.running = true
    onNetEnabledChanged:  if (netEnabled && !netProc.running) netProc.running = true
    onPingEnabledChanged: if (pingEnabled && !pingProc.running) pingProc.running = true
    onDiskEnabledChanged: if (diskEnabled && !diskProc.running) diskProc.running = true
    // Same, but for a hardware recheck finding a GPU/sensors that wasn't
    // there at startup (see recheckHardware() below).
    onGpuAvailableChanged:      if (gpuEnabled && gpuAvailable && !gpuProc.running) gpuProc.running = true
    onSensorsAvailableChanged:  if (cpuEnabled && sensorsAvailable && !tempProc.running) tempProc.running = true

    // Re-runs the one-shot presence checks below - exposed to the Settings
    // modal's Performance page "Recheck" button, for after installing GPU
    // drivers or running sensors-detect without restarting the shell.
    function recheckHardware() {
        if (!gpuCheckProc.running)      gpuCheckProc.running      = true
        if (!sensorsCheckProc.running)  sensorsCheckProc.running  = true
    }

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

    // CPU model name (read once)
    Process {
        id: cpuModelProc
        command: ["sh", "-c", "grep -m1 '^model name' /proc/cpuinfo | cut -d: -f2"]
        running: true
        stdout: StdioCollector {
            id: cpuModelOut
            onStreamFinished: root._parseCpuModel(cpuModelOut.text)
        }
    }

    // Detected once at startup so gpuProc/tempProc stop being scheduled
    // forever on machines that don't have the binary, instead of forking
    // and failing every cycle.
    Process {
        id: gpuCheckProc
        running: true
        command: ["sh", "-c", "command -v nvidia-smi"]
        stdout: StdioCollector {
            id: gpuCheckOut
            onStreamFinished: root.gpuAvailable = gpuCheckOut.text.trim().length > 0
        }
    }
    Process {
        id: sensorsCheckProc
        running: true
        command: ["sh", "-c", "command -v sensors"]
        stdout: StdioCollector {
            id: sensorsCheckOut
            onStreamFinished: root.sensorsAvailable = sensorsCheckOut.text.trim().length > 0
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

    // Ping - fewer/shorter packets on battery, since each run is a real
    // blocking subprocess with active network I/O, not just a timer tick.
    Process {
        id: pingProc
        command: root.onBattery
                 ? ["ping", "-c2", "-W1", "-q", root.pingHost]
                 : ["ping", "-c3", "-W2", "-q", root.pingHost]
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

    // 2s (4s on battery): CPU + GPU + Network - skipped per-metric when its
    // tile is hidden, and gpuProc is skipped entirely on machines with no
    // nvidia-smi.
    Timer {
        interval: root.onBattery ? 4000 : 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.cpuEnabled && !cpuProc.running) cpuProc.running = true
            if (root.gpuEnabled && root.gpuAvailable && !gpuProc.running) gpuProc.running = true
            if (root.netEnabled && !netProc.running) netProc.running = true
        }
    }

    // 10s (20s on battery): temperatures + ping (ping does 3 packets ≈ 3s
    // per run, less on battery - see pingProc above).
    Timer {
        interval: root.onBattery ? 20000 : 10000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.cpuEnabled && root.sensorsAvailable && !tempProc.running) tempProc.running = true
            if (root.pingEnabled && !pingProc.running) pingProc.running = true
        }
    }

    // 30s (60s on battery): disk
    Timer {
        interval: root.onBattery ? 60000 : 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (root.diskEnabled && !diskProc.running) diskProc.running = true
        }
    }

    // ── Helpers ───────────────────────────────────

    function _push(arr, val) {
        const r = arr.concat([val])
        return r.length > _maxHistory ? r.slice(r.length - _maxHistory) : r
    }

    // ── Parsers ───────────────────────────────────

    function _parseCpuModel(text) {
        let s = (text || "").trim()
        if (!s) return
        // Strip marketing cruft: (R), (TM), clock suffix, "CPU"/"Processor" filler.
        s = s.replace(/\((R|TM|tm|r)\)/g, "")
             .replace(/\s*@.*$/, "")
             .replace(/\b(CPU|Processor)\b/g, "")
             .replace(/\d+-Core.*$/i, "")
             .replace(/\s+/g, " ")
             .trim()
        root.cpuModel = s
    }

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
        // rtt min/avg/max/mdev = 14.x/60.x/100.x/y ms  - use avg (2nd value)
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
