// Mem.qml — waybar memory. format "\uefc5 {used:0.0f}/{total:0.0f} GB",
// interval 1, green. Uses scripts/mem.sh. The script emits ONE pipe-delimited
// line — Poll's SplitParser fires per stdout line, so the pill text is field 1
// and the tooltip (usage header + top-10 processes by memory) lives in the
// remaining fields. Click: open btop+.
import QtQuick
import Quickshell

Module {
    id: root

    fg: Tokyo.green
    tooltip: root.tooltipText
    text: root.out

    onClicked: button => {
        if (button === Qt.LeftButton) {
            Quickshell.execDetached(["kitty", "--title", "btop+", "-e", "btop"])
        }
    }

    property string out: ""         // pill text, e.g. "\uefc5 6.2/30.0 GB"
    property string tooltipText: "" // "6.2/30.0 GB (20%)\nllama-server 13.5G 44.7%\n..." (multiline)

    Poll {
        command: [Tokyo.shellDir + "/scripts/mem.sh"]
        interval: 1000
        onResult: output => {
            const parts = String(output).split("|")
            root.out = parts[0] ?? ""
            root.tooltipText = parts.slice(1).join("\n")
        }
    }
}