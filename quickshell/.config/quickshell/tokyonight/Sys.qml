// Sys.qml — GPU, CPU and RAM in ONE pill (they were three).
//
// Each stat keeps the colour it had on its own pill — purple / cyan / green —
// so this uses Module's `fragments` (coloured spans in a row) rather than its
// single-colour `text`. Each span is "icon + number": a GB figure where the
// kernel gives us one (VRAM, RAM), the utilization where it does not (the CPU).
//
// The dials live in the flyout (SysFlyout.qml), and there is no hover
// tooltip: the pill answers "how much" and the click answers "how much and of
// what", which is the same split Net.qml makes.
import QtQuick

Module {
    id: root

    /// SysFlyout to toggle (created in Bar.qml)
    property var flyoutHost: null

    // Plain properties, not readonly: the Poll handlers below write them.
    property real gpuUtil: 0        // %
    property real gpuVram: 0        // GiB allocated
    property real gpuVramTotal: 0   // GiB total
    property real cpuUtil: 0        // %
    property real cpuGhz: 0         // current clock
    property real ramUsed: 0        // GB
    property real ramTotal: 0       // GB
    property real ramPct: 0         // %

    // disk: free space on / plus the throughput over it. The rates are the
    // difference between consecutive diskstats samples — see disk.sh for why
    // the subtraction happens here and not in the script.
    property real diskFree: 0       // GB
    property real diskTotal: 0      // GB
    property real diskPct: 0        // % used
    property real diskRead: 0       // bytes/s
    property real diskWrite: 0      // bytes/s

    // The heaviest processes right now, one row per pid, sorted by the script.
    // Reassigned (never mutated) on every poll: the Repeater in SysFlyout.qml
    // rebuilds its delegates on write, so a list that was mutated in place
    // would keep the same objects and lose the per-row kill state.
    property var procs: []

    // gpu.sh prints " n/a" on a card with no amdgpu counters, and gpuVram stays
    // 0 there — so the same expression that prints the VRAM figure falls back
    // to the utilization on its own, no second code path.
    fragments: [
        {
            text: "\ue266 " + (root.gpuVram > 0
                  ? root.gpuVram + "GB"
                  : Math.round(root.gpuUtil) + "%"),
            color: Tokyo.purple,
        },
        {
            text: "\uf2db " + Math.round(root.cpuUtil) + "%",
            color: Tokyo.cyan,
        },
        {
            text: "\uefc5 " + Math.round(root.ramUsed) + "GB",
            color: Tokyo.green,
        },
    ]

    // No hover tooltip. Module shows nothing for an empty one, and the dials are
    // one click away — the same reasoning as Net.qml.
    tooltip: ""

    // ---------- flyout ----------
    onClicked: button => {
        if (button === Qt.LeftButton && root.flyoutHost)
            root.flyoutHost.toggleFor(root)
    }

    /// the flyout's sample is a second old by the time the panel is up
    function refresh() {
        gpuPoll.refresh()
        cpuPoll.refresh()
        memPoll.refresh()
        diskPoll.refresh()
        procsPoll.refresh()
    }

    // ---------- parsers ----------
    /// gpu.sh: " 26% 1/24GiB" (leading space, no trailing newline)
    function applyGpu(out) {
        const parts = String(out).trim().split(/\s+/)
        const util = parseFloat(parts[0])
        if (!isNaN(util)) root.gpuUtil = util
        const vram = String(parts[1] || "").match(/^([\d.]+)\/([\d.]+)/)
        if (vram !== null) {
            root.gpuVram = parseFloat(vram[1])
            root.gpuVramTotal = parseFloat(vram[2])
        }
    }

    /// cpu.sh: pill | "CPU: N%" | "4.50 GHz" | per-core grid rows | legend.
    /// Only the first three are read; the grid has no home now that the pill
    /// has no tooltip (see the header).
    function applyCpu(out) {
        const parts = String(out).split("|")
        const util = parseFloat(String(parts[0]).replace(/[^\d.]/g, ""))
        if (!isNaN(util)) root.cpuUtil = util
        const ghz = parseFloat(parts[2])
        if (!isNaN(ghz)) root.cpuGhz = ghz
    }

    /// mem.sh: pill | "used/total GB (N%)" | top-10 process rows. The header is
    /// all that is read; the rows have no home now that the pill has no tooltip.
    function applyMem(out) {
        const parts = String(out).split("|")
        const head = String(parts[1] || parts[0]).trim()
        const m = head.match(/([\d.]+)\/([\d.]+)\s*GB\s*\((\d+)%\)/)
        if (m !== null) {
            root.ramUsed = parseFloat(m[1])
            root.ramTotal = parseFloat(m[2])
            root.ramPct = parseFloat(m[3])
        }
    }

    /// disk.sh: "718.4|841.1|15|41431857|27052588" — free GB, total GB, used %,
    /// cumulative sectors read, cumulative sectors written. The rates are the
    /// difference between the last two samples over the wall time between them,
    /// so the `refresh()` on open (which is not on the poll boundary) still
    /// shows the true MB/s instead of a spike or a stall.
    function applyDisk(out) {
        const p = String(out).split("|")
        const free = parseFloat(p[0])
        if (!isNaN(free)) root.diskFree = free
        const total = parseFloat(p[1])
        if (!isNaN(total)) root.diskTotal = total
        const pct = parseFloat(p[2])
        if (!isNaN(pct)) root.diskPct = pct

        const sr = parseFloat(p[3])
        const sw = parseFloat(p[4])
        const now = Date.now()
        if (!isNaN(sr) && !isNaN(sw) && root.diskLastSec > 0) {
            // 512-byte sectors (the diskstats unit, fixed by the kernel ABI),
            // kept in bytes/s so the flyout can pick its own unit the same way
            // network-monitor.sh does for the link rates.
            const dt = (now - root.diskLastSec) / 1000
            if (dt > 0) {
                root.diskRead = Math.max(0, (sr - root.diskLastR) * 512 / dt)
                root.diskWrite = Math.max(0, (sw - root.diskLastW) * 512 / dt)
            }
        }
        root.diskLastR = sr
        root.diskLastW = sw
        root.diskLastSec = now
    }

    /// procs.sh: "TOP 12|pid|name|cpuPct|ramMB|..." — the count first, then rows
    /// of four. Two bail-outs, both keeping the list that is already on screen:
    /// a header that is not `TOP <n>` (script died before printing anything) and
    /// a header with no complete row behind it (died part-way through one). A
    /// blank list reads as "nothing is running", which is a lie; the previous
    /// list reads as slightly stale, which is true.
    function applyProcs(out) {
        const p = String(out).split("|")
        if (!/^TOP \d+$/.test(p[0].trim())) return
        const rows = []
        for (let i = 1; i + 3 < p.length; i += 4) {
            const pid = parseInt(p[i], 10)
            if (isNaN(pid) || pid <= 0) continue
            const cpu = parseFloat(p[i + 2])
            const ram = parseFloat(p[i + 3])
            rows.push({
                pid: pid,
                name: p[i + 1],
                cpu: isNaN(cpu) ? 0 : cpu,
                ram: isNaN(ram) ? 0 : ram,
            })
        }
        if (rows.length === 0) return
        root.procs = rows
    }

    property real diskLastR: 0
    property real diskLastW: 0
    property real diskLastSec: 0

    Poll {
        id: gpuPoll
        command: [Tokyo.scriptDir + "/gpu.sh"]
        interval: 1000
        onResult: output => root.applyGpu(output)
    }
    Poll {
        id: cpuPoll
        command: [Tokyo.scriptDir + "/cpu.sh"]
        interval: 1000
        onResult: output => root.applyCpu(output)
    }
    Poll {
        id: memPoll
        command: [Tokyo.scriptDir + "/mem.sh"]
        interval: 1000
        onResult: output => root.applyMem(output)
    }
    Poll {
        id: diskPoll
        command: [Tokyo.scriptDir + "/disk.sh"]
        interval: 1000
        onResult: output => root.applyDisk(output)
    }
    Poll {
        id: procsPoll
        command: [Tokyo.scriptDir + "/procs.sh"]
        interval: 1000
        onResult: output => root.applyProcs(output)
    }
}
