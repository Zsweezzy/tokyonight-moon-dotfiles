// NetworkMonitor.qml — shared per-adapter counters and latency snapshots.
import QtQuick
import Quickshell.Io

Item {
    id: root

    // Updated once per second by network-monitor.sh.  Wifi.qml and
    // Ethernet.qml consume this array without adding a third visible pill.
    property var adapters: []
    property bool ready: false

    function refresh() {
        poll.refresh()
    }

    function apply(output) {
        try {
            const parsed = JSON.parse(output)
            if (parsed && Array.isArray(parsed.adapters)) {
                root.adapters = parsed.adapters
                root.ready = true
            }
        } catch (e) {
            // Keep the last good snapshot if a transient process error occurs.
        }
    }

    Poll {
        id: poll
        command: [Tokyo.scriptDir + "/network-monitor.sh"]
        interval: 1000
        onResult: output => root.apply(output)
    }
}
