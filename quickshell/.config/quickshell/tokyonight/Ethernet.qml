// Ethernet.qml — existing Ethernet pill with live adapter metrics appended to
// its IP/netmask and optional DNS/MAC tooltip. Other non-loopback adapters are
// grouped below enp14s0; no visible layout changes.
import QtQuick

Module {
    id: root

    property var networkMonitor: null

    fg: Tokyo.blue
    text: root.parsed.text
    tooltip: root.tooltipWithMetrics(root.parsed.tooltip,
                                    root.networkMonitor ? root.networkMonitor.adapters : [])

    property var parsed: ({ text: " \uef44", tooltip: "" })

    Poll {
        command: [Tokyo.scriptDir + "/ethernet.sh"]
        interval: 60000
        onResult: output => root.parsed = parseJson(output)
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

    function hasValue(value) {
        return value !== undefined && value !== null && value !== "" && value !== "-"
    }

    function metricLines(adapter) {
        return [
            "Download: " + root.valueOrDash(adapter.rxRate),
            "Upload: " + root.valueOrDash(adapter.txRate),
            "External ping (1.1.1.1): " + root.valueOrDash(adapter.externalPing),
        ]
    }

    function adapterBlock(adapter) {
        const lines = [
            "Interface: " + root.valueOrDash(adapter.name),
            "IP: " + root.valueOrDash(adapter.ip),
            "Netmask: " + root.valueOrDash(adapter.netmask),
        ]
        if (root.hasValue(adapter.dns))
            lines.push("DNS: " + root.valueOrDash(adapter.dns))
        if (root.hasValue(adapter.mac))
            lines.push("MAC: " + root.valueOrDash(adapter.mac))
        return lines.concat(root.metricLines(adapter))
    }

    function tooltipWithMetrics(base, records) {
        if (!Array.isArray(records))
            return base

        // Keep enp14s0's existing details and metrics together at the top of
        // the Ethernet tooltip, regardless of the order of other adapters.
        let primaryBlock = null
        const otherBlocks = []
        for (let i = 0; i < records.length; i++) {
            const adapter = records[i]
            // The active Wi-Fi record is shown by Wifi.qml.  Every other
            // non-loopback adapter is grouped into this existing pill.
            if (adapter.activeWifi === true)
                continue

            if (adapter.name === "enp14s0" && primaryBlock === null) {
                primaryBlock = root.metricLines(adapter).join("\n")
            } else {
                otherBlocks.push(root.adapterBlock(adapter).join("\n"))
            }
        }

        const blocks = []
        if (primaryBlock !== null)
            blocks.push(primaryBlock)
        for (let i = 0; i < otherBlocks.length; i++)
            blocks.push(otherBlocks[i])

        if (blocks.length === 0)
            return base
        const prefix = base === "" ? "" : String(base).replace(/\n+$/, "") + "\n"
        return prefix + blocks.join("\n\n")
    }
}