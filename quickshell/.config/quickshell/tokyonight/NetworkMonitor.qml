// NetworkMonitor.qml — shared per-adapter counters and latency snapshots.
import QtQuick

Item {
    id: root

    // Updated once per second by network-monitor.sh.  Settings.qml consumes
    // this array to show per-adapter counters and latency.
    property var adapters: []

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
