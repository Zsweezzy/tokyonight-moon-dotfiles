// Poll.qml — repeatedly runs a one-shot script and emits the last line of its stdout.
// Waybar equivalent: custom module with `exec` + `interval`.
//
// The script is started immediately at component load ("interval" ms later for
// subsequent runs). `refresh()` can be called to run it right away — this is the
// replacement for waybar's RTMIN signal refresh.
//
// NOTE on quickshell 0.3.1: Process::onFinished calls streamEnded(stdoutBuffer)
// and then deleteLater()s the QProcess. If a fast one-shot script (e.g. gpu.sh,
// which uses printf without a trailing newline) exits before the final
// readyReadStandardOutput delivers the tail bytes, those bytes are still in the
// QProcess internal buffer and get dropped — intermittently losing the last
// chunk of output. Running through `sh -c "<cmd> ; sleep 0.1"` keeps the
// process alive 100ms after the script writes, so the pipe is fully drained
// before the child exits. Scripts therefore need no trailing newline.
import QtQuick
import Quickshell.Io

Item {
    id: root

    /// list of command arguments, e.g. ["/path/to/wifi.sh"]
    property var command: []
    /// milliseconds between runs (waybar `interval`)
    property int interval: 5000
    /// set to false to pause the loop
    property bool active: true

    /// emitted with the script's stdout (last read line) on every run
    signal result(string output)
    /// emitted with the script's stdout when a run exits without output
    signal finished()

    // Quote each argument for sh, then append a settle delay so the final
    // bytes of the script's output drain into the pipe before exit.
    function shellCmd() {
        const parts = []
        for (let i = 0; i < root.command.length; i++) {
            const a = String(root.command[i])
            parts.push("'" + a.replace(/'/g, "'\\''") + "'")
        }
        return "(" + parts.join(" ") + ") ; sleep 0.1"
    }

    Process {
        id: proc
        command: ["sh", "-c", root.shellCmd()]

        stdout: SplitParser {
            onRead: msg => root.result(msg)
        }
    }

    Timer {
        id: pollTimer
        interval: root.interval
        repeat: true
        running: root.active && root.command.length > 0
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        if (root.command.length > 0) pollTimer.triggered()
    }

    function refresh() {
        if (root.command.length === 0) return
        proc.command = ["sh", "-c", root.shellCmd()]
        proc.running = true
    }
}