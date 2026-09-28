// Brightness.qml — shared DDC/CI brightness service for the bar.
//
// One instance lives in shell.qml next to NetworkMonitor, so the three bar
// windows share one view of the hardware instead of each probing I2C.
//
// ddcutil is slow over I2C (~0.4 s for a read, ~0.5 s for a write) and a
// `ddcutil detect` costs seconds, so this service is built around not paying
// that on every interaction:
//   * the Hyprland-monitor-name -> ddcutil-display-number map is built once,
//     lazily on first use, and cached (it only changes on replug),
//   * the last known level per monitor is kept and updated optimistically, so
//     the slider follows the pointer instantly instead of stalling on I2C,
//   * a drag is coalesced by a debounce timer into a single write, which is
//     then re-read once to confirm the monitor really accepted the value.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    /// Hyprland monitor name -> ddcutil display number, or null when that
    /// monitor exposes no DDC/CI luminance control.
    property var ddcMap: ({})
    property bool mapReady: false

    /// Hyprland monitor name -> last known level (0-100)
    property var levels: ({})
    /// Hyprland monitor name -> that monitor's own maximum (0-100)
    property var maxes: ({})

    /// A drag emits a value per mouse move; wait this long for it to settle
    /// before spending an I2C write. 180 ms stays below the ~250 ms at which a
    /// stepped drag starts to feel laggy, and collapses a sweep of the slider
    /// into one or two writes.
    readonly property int writeDelay: 180
    /// Settle time between a write landing and re-reading the real level.
    readonly property int confirmDelay: 700

    readonly property string script: Tokyo.scriptDir + "/brightness.sh"

    /// monitors still waiting to be read — `readProc` handles one at a time
    property var readQueue: []
    /// the monitor `readProc` is currently asking about
    property string readTarget: ""
    /// raw stdout of the in-flight read, parsed on exit
    property string readOut: ""
    /// raw stdout of the in-flight map build, parsed on exit
    property string mapOut: ""

    // ---------------- map ----------------

    /// ddcutil display number for a Hyprland monitor name, or -1 when the
    /// monitor is unsupported or the map is not built yet. Pure: safe to call
    /// from a binding.
    function ddcFor(monitorName) {
        if (!root.mapReady) return -1
        const num = root.ddcMap[monitorName]
        return (num === undefined || num === null) ? -1 : num
    }

    /// Start the one-time map build if it has not run yet. Callers use this
    /// before asking for a read/write so the request survives the wait.
    function ensureMap() {
        if (!root.mapReady) root.refreshMap()
    }

    function refreshMap() {
        if (mapProc.running) return
        run(mapProc, [root.script, "map"])
    }

    function applyMap() {
        try {
            const parsed = JSON.parse(String(root.mapOut).trim())
            if (parsed && typeof parsed === "object") {
                root.ddcMap = parsed
                root.mapReady = true
            }
        } catch (e) {
            // Detection failed (no permission, no I2C access). Leave mapReady
            // false so the next interaction retries instead of caching a
            // permanently broken mapping.
        }
        root.mapOut = ""
        // Reads queued while the map was still building can only be answered
        // now — ddcFor() returned -1 for them until this moment.
        root.pumpReads()
    }

    // ---------------- reads ----------------

    /// Last known level for a monitor, or `fallback` if never read.
    function level(monitorName, fallback) {
        const v = root.levels[monitorName]
        return (v === undefined || v === null) ? fallback : v
    }

    /// That monitor's own DDC maximum, which is not always 100.
    function max(monitorName, fallback) {
        const v = root.maxes[monitorName]
        return (v === undefined || v === null) ? fallback : v
    }

    /// Queue a read of the monitor's real level.
    function read(monitorName) {
        root.ensureMap()
        if (root.readQueue.indexOf(monitorName) === -1)
            root.readQueue.push(monitorName)
        root.pumpReads()
    }

    function pumpReads() {
        if (readProc.running || root.readQueue.length === 0) return

        if (!root.mapReady) {
            // Wait for the map rather than dropping the request; applyMap()
            // calls back into here once it lands.
            root.ensureMap()
            return
        }

        const name = root.readQueue[0]
        const ddc = root.ddcFor(name)
        if (ddc < 0) {
            // Genuinely unsupported monitor: drop it, it will never resolve.
            root.readQueue.shift()
            return root.pumpReads()
        }

        root.readTarget = name
        root.readOut = ""
        run(readProc, [root.script, "get", String(ddc)])
    }

    function applyRead() {
        const name = root.readTarget
        if (!name) return

        // "<value> <max>", e.g. "79 100"
        const parts = String(root.readOut).trim().split(/\s+/)
        const value = parseInt(parts[0], 10)
        if (!isNaN(value)) {
            const levels = Object.assign({}, root.levels)
            levels[name] = value
            root.levels = levels

            const maxValue = parseInt(parts[1], 10)
            if (!isNaN(maxValue) && maxValue > 0) {
                const maxes = Object.assign({}, root.maxes)
                maxes[name] = maxValue
                root.maxes = maxes
            }
        }
        root.readOut = ""
    }

    // ---------------- writes ----------------

    /// Ask for a level. The UI already shows the new value; this only records
    /// it and (re)starts the debounce so a drag becomes a single write.
    function request(monitorName, value) {
        root.ensureMap()
        const ddc = root.ddcFor(monitorName)
        if (ddc < 0) return

        const clamped = Math.max(0,
            Math.min(root.max(monitorName, 100), Math.round(value)))

        // Optimistic: the slider and pill follow the pointer, the hardware
        // catches up when the debounce fires.
        const levels = Object.assign({}, root.levels)
        levels[monitorName] = clamped
        root.levels = levels

        pendingMonitor = monitorName
        pendingDdc = ddc
        pendingValue = clamped
        writeTimer.restart()
    }

    /// Nudge by a delta — the scroll-wheel gesture on a workspace pill.
    function nudge(monitorName, delta) {
        if (root.ddcFor(monitorName) < 0) return
        root.request(monitorName,
            root.level(monitorName, root.max(monitorName, 100)) + delta)
    }

    property string pendingMonitor: ""
    property int pendingDdc: -1
    property int pendingValue: -1

    function flushWrite() {
        if (root.pendingDdc < 0) return
        // Fire and forget: the write takes ~0.5 s, longer than a drag lasts,
        // so waiting for it would only add latency. The confirm read below is
        // what reports the hardware's real answer.
        Quickshell.execDetached([
            root.script, "set",
            String(root.pendingDdc), String(root.pendingValue),
            String(root.max(root.pendingMonitor, 100))
        ])
        confirmTimer.restart()
    }

    // ---------------- processes ----------------

    // Same runner as Poll.qml: quote the argv for sh and append a settle delay
    // so the tail of the output is read before the child exits (one-shot
    // scripts need no trailing newline).
    function run(proc, argv) {
        const parts = []
        for (let i = 0; i < argv.length; i++) {
            const a = String(argv[i])
            parts.push("'" + a.replace(/'/g, "'\\''") + "'")
        }
        proc.command = ["sh", "-c", "(" + parts.join(" ") + ") ; sleep 0.1"]
        proc.running = true
    }

    // Completion is detected through `running` flipping to false rather than
    // `onExited`: Process.exited is overloaded (int / QProcess::ExitStatus) and
    // the second overload's enum type is not resolvable from QML.
    Process {
        id: mapProc
        stdout: SplitParser {
            onRead: msg => root.mapOut = String(msg).trim()
        }
        onRunningChanged: {
            if (mapProc.running) return
            root.applyMap()
        }
    }

    Process {
        id: readProc
        stdout: SplitParser {
            onRead: msg => root.readOut = String(msg).trim()
        }
        onRunningChanged: {
            if (readProc.running) return
            root.applyRead()
            root.readTarget = ""
            if (root.readQueue.length > 0) root.readQueue.shift()
            root.pumpReads()
        }
    }

    Timer {
        id: writeTimer
        interval: root.writeDelay
        onTriggered: root.flushWrite()
    }

    Timer {
        id: confirmTimer
        interval: root.confirmDelay
        onTriggered: {
            if (root.pendingMonitor) root.read(root.pendingMonitor)
        }
    }
}
