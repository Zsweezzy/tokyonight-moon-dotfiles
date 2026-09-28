// Cava.qml — audio visualizer (continuous stream, no interval).
//
// Runs scripts/cava.sh (Tokyo.scriptDir; pipes cava's ascii frames
// through the block-glyph renderer) and renders each frame as the module text.
// Restarts automatically if the process ever exits (waybar `restart-interval: 3`).
import QtQuick
import Quickshell.Io

Module {
    id: root

    fg: Tokyo.cyan
    interactive: false                        // waybar cava has no hover styles/tooltip
    tooltip: ""

    text: root.frames

    property string frames: ""

    Process {
        id: cava
        command: [Tokyo.scriptDir + "/cava.sh"]
        running: true

        stdout: SplitParser {
            onRead: msg => root.frames = msg
        }

        onRunningChanged: {
            if (!cava.running) cava.running = true
        }
    }
}