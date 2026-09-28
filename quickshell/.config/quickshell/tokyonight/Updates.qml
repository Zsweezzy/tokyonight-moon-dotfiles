// Updates.qml — waybar custom/updates. JSON script, interval 600, signal 9.
//   text/tooltip from script; class zero -> green, pending -> yellow.
//   click        : kitty yay -Syu
//   middle-click : force refresh (replaces `pkill -RTMIN+9 -x waybar`)
import QtQuick
import Quickshell

Module {
    id: root

    fg: root.parsed.cls === "zero" ? Tokyo.green : Tokyo.yellow
    text: root.parsed.text
    tooltip: root.parsed.tooltip

    property var parsed: ({ text: "\uf019 ?", tooltip: "", cls: "" })

    Poll {
        id: poll
        command: [Tokyo.scriptDir + "/cachy-updates.sh"]
        interval: 600000
        onResult: output => root.parsed = parseJson(output)
    }

    onClicked: button => {
        if (button === Qt.LeftButton) {
            Quickshell.execDetached([
                "kitty", "--title", "CachyOS update", "-e", "bash", "-lc",
                "yay -Syu; read -rp \"Press Enter to close\"",
            ])
        } else if (button === Qt.MiddleButton) {
            poll.refresh()
        }
    }

    function parseJson(out) {
        try {
            const o = JSON.parse(out)
            return { text: o.text ?? "", tooltip: o.tooltip ?? "", cls: o.class ?? "" }
        } catch (e) {
            return root.parsed
        }
    }
}