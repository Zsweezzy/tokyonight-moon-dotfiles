// bellprobe.qml — run by tests/test-notification-widgets.sh.
//
// Prints the bell pill's width with 0 unread, which is where the empty state
// shows up: the pill must be glyph + 2 * hPad and nothing else, 35px on this
// shell. A stray fragment left in the row is what pushed it past that.
import QtQuick
import Quickshell

ShellRoot {
    Module {
        id: bell
        fragments: [
            { text: "\uf0f3", color: Tokyo.dim },
            {
                visible: unread > 0,
                text: unread > 9 ? "9+" : String(unread),
                color: Tokyo.cyan,
            },
        ]
        hPad: 12
        property int unread: 0
    }

    Component.onCompleted: {
        print("bellprobe empty=" + bell.width.toFixed(1))
        Qt.exit(0)
    }
}