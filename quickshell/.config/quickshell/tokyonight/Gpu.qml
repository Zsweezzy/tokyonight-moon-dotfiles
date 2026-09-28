// Gpu.qml — waybar custom/gpu. Existing script, interval 1, purple.
//   format "\ue266{text}"  tooltip "GPU: {text}"
//   click : open btop+
import QtQuick
import Quickshell

Module {
    id: root

    fg: Tokyo.purple
    tooltip: "GPU: " + root.out
    text: "\ue266" + root.out

    onClicked: button => {
        if (button === Qt.LeftButton) {
            Quickshell.execDetached(["kitty", "--title", "btop+", "-e", "btop"])
        }
    }

    property string out: ""

    Poll {
        command: [Tokyo.scriptDir + "/gpu.sh"]
        interval: 1000
        onResult: output => root.out = output
    }
}