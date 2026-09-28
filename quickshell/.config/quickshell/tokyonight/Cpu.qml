// Cpu.qml — waybar cpu. format "\uf2db {usage}%", interval 1, cyan.
// Uses scripts/cpu.sh (same approach as gpu.sh). The script emits ONE
// pipe-delimited line — Poll's SplitParser fires per stdout line, so the
// per-core grid lives in extra `|` fields; the pill text is only field 1.
// Tooltip: aggregate + a per-core grid (4 columns x all cores).
// Click: open btop+.
import QtQuick
import Quickshell

Module {
    id: root

    fg: Tokyo.cyan
    tooltip: root.tooltipText
    text: root.out

    onClicked: button => {
        if (button === Qt.LeftButton) {
            Quickshell.execDetached(["kitty", "--title", "btop+", "-e", "btop"])
        }
    }

    property string out: ""         // pill text, e.g. "\uf2db 12%"
    property string tooltipText: "" // "CPU: 12%\nC01 12%   ..." (multiline)

    Poll {
        command: [Tokyo.shellDir + "/scripts/cpu.sh"]
        interval: 1000
        onResult: output => {
            const parts = String(output).split("|")
            root.out = parts[0] ?? ""
            root.tooltipText = parts.slice(1).join("\n")
        }
    }
}