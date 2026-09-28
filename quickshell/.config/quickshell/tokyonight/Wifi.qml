// Wifi.qml — existing Wi‑Fi pill with live adapter metrics appended to its
// SSID/IP/netmask and optional DNS/MAC tooltip.
//
//   click : wifi-toggle.sh (reveal/hide SSID) — then refresh immediately,
//           replacing waybar's `pkill -RTMIN+8 -x waybar` behavior.
//   hover : existing link details + per-adapter rates and external ping time.
import QtQuick
import Quickshell

Module {
    id: root

    property var networkMonitor: null

    fg: Tokyo.cyan
    text: root.parsed.text
    tooltip: root.tooltipWithMetrics(root.parsed.tooltip,
                                    root.networkMonitor ? root.networkMonitor.adapters : [])

    property var parsed: ({ text: " \uf1eb", tooltip: "" })

    Poll {
        id: poll
        command: [Tokyo.scriptDir + "/wifi.sh"]
        interval: 60000
        onResult: output => root.parsed = parseJson(output)
    }

    Timer {
        id: postToggle
        interval: 800
        onTriggered: poll.refresh()
    }

    onClicked: button => {
        if (button === Qt.LeftButton) {
            Quickshell.execDetached([Tokyo.scriptDir + "/wifi-toggle.sh"])
            postToggle.start()
        }
    }

    function parseJson(out) {
        try {
            const o = JSON.parse(out)
            return {
                text: o.text ?? "",
                tooltip: o.tooltip ?? "",
            }
        } catch (e) {
            return { text: root.parsed.text, tooltip: root.parsed.tooltip }
        }
    }

    function valueOrDash(value) {
        return (value === undefined || value === null || value === "") ? "-" : String(value)
    }

    function findWifiAdapter(records) {
        if (!Array.isArray(records))
            return null

        for (let i = 0; i < records.length; i++) {
            if (records[i].activeWifi === true)
                return records[i]
        }
        return null
    }

    function metricLines(adapter) {
        if (adapter === null || adapter === undefined)
            return []

        return [
            "Download: " + root.valueOrDash(adapter.rxRate),
            "Upload: " + root.valueOrDash(adapter.txRate),
            "External ping (1.1.1.1): " + root.valueOrDash(adapter.externalPing),
        ]
    }

    function tooltipWithMetrics(base, records) {
        const lines = root.metricLines(root.findWifiAdapter(records))
        if (lines.length === 0)
            return base

        const prefix = base === "" ? "" : String(base).replace(/\n+$/, "") + "\n"
        return prefix + lines.join("\n")
    }
}