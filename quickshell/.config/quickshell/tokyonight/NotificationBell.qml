// NotificationBell.qml — the bar's notification widget, and the entry to the
// centre.
//
// It sits next to Updates rather than in a corner of its own, because "there
// are updates" and "something wants you" are both things that arrived while you
// were looking at something else, and reading them off two adjacent pills costs
// one glance instead of two.
//
// The unread mark is a count and not a dot past nine, because "you have
// notifications" and "you have eleven and one of them is a phone call" are
// different amounts of interrupting.
import QtQuick
import Quickshell

Module {
    id: root

    /// the shell-wide store (NotificationStore.qml)
    property var store: null
    property var flyoutHost: null

    readonly property int unread: store !== null ? store.unread : 0

    // Bell, and a badge only when there is something to badge. The bell itself
    // does not change colour for unread — a coloured bell reads as "this
    // widget is on", and a widget that is always on is a widget you stop seeing.
    fragments: [
        { text: "", color: unread > 0 ? Tokyo.cyan : Tokyo.dim },
        {
            // Hidden, not emptied. An empty string measures the same (35px both
            // ways — Qt gives a zero-width delegate no spacing), so this is
            // about the contract rather than the pixels: a fragment that is not
            // there says so with visible, and nothing has to remember that ""
            // means gone.
            visible: unread > 0,
            text: unread > 9 ? "9+" : String(unread),
            color: Tokyo.cyan,
        },
    ]
    hPad: unread > 0 ? 10 : 12
    interactive: true
    tooltip: unread === 0
        ? "No notifications"
        : unread === 1 ? "1 unread notification" : unread + " unread notifications"

    onClicked: button => {
        if (button !== Qt.LeftButton) return
        if (root.flyoutHost !== null) root.flyoutHost.toggleFor(root)
    }
}
