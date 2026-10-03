// Settings.qml — the internet and the power tools in ONE pill (they were two).
//
// Three glyphs, no text: the ethernet cable in blue while enp14s0 has carrier,
// the wifi glyph while a link is associated, and the power glyph, which is the
// same one the shutdown button in the flyout wears. Each net icon is there only
// while its link is up, so the pill carries just the one that is actually
// moving data. The power glyph is always there — it is the way into the menu,
// and a pill that changes width as you unplug things is a moving target.
//
// Everything the pill used to say in a tooltip is now one click away in
// SettingsFlyout, so no tooltip: the network block, the SSID reveal, the
// bluetooth devices and the power actions all live in there.
import QtQuick
import Quickshell

Module {
    id: root

    property var networkMonitor: null
    /// SettingsFlyout to toggle (created in Bar.qml)
    property var flyoutHost: null

    // ---------- net state (was Net.qml) ----------
    /// raw script output per link
    // showSsid defaults false: hidden until the flyout's button says otherwise.
    property var wifi: ({ label: "wifi", showSsid: false, tooltip: "" })
    property var eth: ({ label: "ethernet", showSsid: false, tooltip: "" })

    readonly property var adapters: root.networkMonitor ? root.networkMonitor.adapters : []

    function findAdapter(name) {
        if (!Array.isArray(root.adapters)) return null
        for (let i = 0; i < root.adapters.length; i++) {
            if (root.adapters[i] && root.adapters[i].name === name)
                return root.adapters[i]
        }
        return null
    }

    readonly property bool ethUp: {
        const a = root.findAdapter("enp14s0")
        return a !== null && a.state === "up"
    }
    readonly property bool wifiUp: {
        if (!Array.isArray(root.adapters)) return false
        return root.adapters.some(a => a && a.activeWifi === true)
    }
    /// wired wins when both are up — it is the link everything else rides on
    readonly property bool primaryEthernet: root.ethUp

    // ---------- connection stats (was Net.qml, read by the flyout) ----------
    /// The WI-FI section's reveal/hide button, and the only thing that decides
    /// whether the network name is readable. Read from wifi.sh's own
    /// `showSsid` rather than guessed from the label: a network actually named
    /// "wifi" must not read as permanently hidden.
    readonly property bool ssidShown: root.wifi.showSsid === true

    Poll {
        id: wifiPoll
        command: [Tokyo.scriptDir + "/wifi.sh"]
        interval: 60000
        onResult: output => root.wifi = root.parseJson(output, root.wifi)
    }

    Poll {
        id: ethPoll
        command: [Tokyo.scriptDir + "/ethernet.sh"]
        interval: 60000
        onResult: output => root.eth = root.parseJson(output, root.eth)
    }

    // Flip the button on the spot, then let the poll correct us. wifi.sh takes
    // a moment (it shells out for the SSID), so waiting for it before showing
    // anything left the tab looking broken for the best part of a second.
    Timer {
        id: postToggle
        interval: 400
        onTriggered: wifiPoll.refresh()
    }

    function toggleSsid() {
        Quickshell.execDetached([Tokyo.scriptDir + "/wifi-toggle.sh"])
        // New object, not a field write: `wifi` is a `var` and bindings only
        // re-run when the reference itself changes.
        root.wifi = Object.assign({}, root.wifi,
                                 { showSsid: !root.ssidShown })
        postToggle.start()
    }

    function parseJson(out, fallback) {
        try {
            const o = JSON.parse(out)
            // both scripts prefix their label with the nerd-font glyph
            const label = String(o.text ?? "").replace(/^\S+\s+/, "").trim()
            return {
                label: label === "" ? fallback.label : label,
                // wifi.sh reports the reveal state; ethernet.sh has no such
                // field, so it keeps the last one it was given.
                showSsid: o.showSsid === undefined
                    ? fallback.showSsid
                    : o.showSsid === true,
                tooltip: o.tooltip ?? fallback.tooltip,
            }
        } catch (e) {
            return fallback
        }
    }

    function valueOrDash(value) {
        return (value === undefined || value === null || value === "") ? "-" : String(value)
    }

    function hasValue(value) {
        return value !== undefined && value !== null && value !== "" && value !== "-"
    }

    /// null-safe: the wifi adapter is looked up by a flag and may be absent
    function metricLines(adapter) {
        if (adapter === null || adapter === undefined)
            return []

        return [
            "Download: " + root.valueOrDash(adapter.rxRate),
            "Upload: " + root.valueOrDash(adapter.txRate),
            "External ping (1.1.1.1): " + root.valueOrDash(adapter.externalPing),
        ]
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

    function withMetrics(base, blocks) {
        if (blocks.length === 0)
            return base

        const prefix = base === "" ? "" : String(base).replace(/\n+$/, "") + "\n"
        return prefix + blocks.join("\n\n")
    }

    /// ssid/ip/netmask + dns/mac + the active wifi adapter's live rates.
    /// The three rates are ONE block, so they are joined here: `withMetrics`
    /// separates blocks with a blank line (that is what keeps the per-adapter
    /// blocks apart), and handing it the three lines separately gave each of
    /// them its own blank line.
    ///
    /// The SSID line is masked unless the button has revealed it. This is the
    /// only place the name is ever shown now that the pill is icons only, so it
    /// is also the only place the button can have an effect.
    readonly property string wifiTooltip: root.withMetrics(
        root.ssidForDisplay(root.wifi.tooltip),
        [root.metricLines(root.findWifiAdapter(root.adapters)).join("\n")])

    /// The SSID line as the flyout is allowed to show it: the name once
    /// revealed, dots until then. The line itself is always kept, so the block
    /// does not change shape as the button flips.
    function ssidForDisplay(base) {
        if (root.ssidShown) return String(base)
        const text = String(base)
        if (!text.includes("SSID:")) return text
        return text.replace(/^(SSID: ).*$/m, "$1•••••••")
    }

    /// enp14s0's live rates first, then every other non-loopback adapter as
    /// its own block (the wifi record is the wifi section's business)
    readonly property string ethernetTooltip: {
        if (!Array.isArray(root.adapters))
            return root.eth.tooltip

        let primary = null
        const others = []
        for (let i = 0; i < root.adapters.length; i++) {
            const adapter = root.adapters[i]
            if (adapter.activeWifi === true)
                continue
            if (adapter.name === "enp14s0" && primary === null)
                primary = root.metricLines(adapter)
            else
                others.push(root.adapterBlock(adapter).join("\n"))
        }

        const blocks = []
        if (primary !== null)
            blocks.push(primary.join("\n"))
        for (let i = 0; i < others.length; i++)
            blocks.push(others[i])

        return root.withMetrics(root.eth.tooltip, blocks)
    }

    // ---------- bluetooth + wifi lists ----------
    readonly property string wifiListCmd: Tokyo.scriptDir + "/wifi-list.sh"
    readonly property string btStateCmd: Tokyo.scriptDir + "/bt-state.sh"

    property var wl: ({ radio: true, active: "", networks: [] })
    property var bt: ({ powered: true, devices: [] })
    /// discovery results, kept apart from the paired list on purpose: scanning
    /// finds neighbours, and those must not be listed as if they were yours
    property var found: []
    /// true while bt-scan.sh is out listening — the list it fills arrives when
    /// it returns, so without this the button looks broken
    property bool scanning: false
    /// the MAC of the device row currently waiting on bluez, or "" for none.
    /// A MAC and not a bool because pairing is per device: the row you clicked
    /// is the one spinning, not the whole bluetooth section.
    property string btBusy: ""
    property string notice: ""

    /// Paired devices and the scan results are one list between them; a paired
    /// device is just one that is already known. Rebuilt whenever either
    /// changes. A device with no name is dropped: it is a bare MAC, and a row
    /// saying so is one you cannot do anything with.
    readonly property var btList: {
        const out = []
        const seen = {}
        for (let i = 0; i < root.bt.devices.length; i++) {
            const d = root.bt.devices[i]
            if (!d.name) continue
            seen[d.mac] = true
            out.push({ mac: d.mac, name: d.name, paired: true,
                       connected: d.connected === true })
        }
        for (let i = 0; i < root.found.length; i++) {
            const d = root.found[i]
            if (seen[d.mac] || !d.name) continue
            out.push({ mac: d.mac, name: d.name, paired: false,
                       connected: false })
        }
        return out
    }

    Poll {
        id: wifiListPoll
        command: [root.wifiListCmd]
        interval: 30000
        onResult: out => root.wl = root.parseWifi(out)
    }

    Poll {
        id: btPoll
        command: [root.btStateCmd]
        interval: 20000
        onResult: out => root.bt = root.parseBt(out)
    }

    Poll {
        id: btScanPoll
        command: [Tokyo.scriptDir + "/bt-scan.sh", "10"]
        // Off until asked for: an always-on scan drains the phone's battery and
        // makes every device in the room show up in the list uninvited.
        active: false
        onResult: out => {
            root.scanning = false
            try {
                root.found = JSON.parse(out).devices || []
            } catch (e) {
                root.found = []
            }
        }
    }

    function parseWifi(out) {
        try {
            const o = JSON.parse(out)
            return {
                radio: o.radio === true,
                active: o.active || "",
                networks: Array.isArray(o.networks) ? o.networks : [],
            }
        } catch (e) {
            return root.wl
        }
    }

    function parseBt(out) {
        try {
            const o = JSON.parse(out)
            return {
                powered: o.powered === true,
                devices: Array.isArray(o.devices) ? o.devices : [],
            }
        } catch (e) {
            return root.bt
        }
    }

    /// Called by the flyout when it opens: the 30s and 20s polls are too slow
    /// to trust on open, and after any action this is what re-reads the truth.
    function refreshAll() {
        wifiPoll.refresh()
        ethPoll.refresh()
        wifiListPoll.refresh()
        btPoll.refresh()
        lsPoll.refresh()
    }

    // ---------- airdrop (LocalSend) ----------
    readonly property string airdropCmd: Tokyo.scriptDir + "/localsend.sh"
    property var airdrop: ({ running: false })

    Poll {
        id: lsPoll
        command: [root.airdropCmd]
        // Faster than the other polls: this one tracks something the tile was
        // just clicked for, so the light has to follow the click rather than
        // arrive up to a poll later.
        interval: 4000
        onResult: out => {
            try {
                root.airdrop = { running: JSON.parse(out).running === true }
            } catch (e) {
                // No state to report: leave the last one alone.
            }
        }
    }

    /// One command for launch and for raise — LocalSend is single-instance, so
    /// starting it while it is up brings its window forward instead of opening a
    /// second copy.
    function openLocalSend() {
        root.run(root.airdropCmd, ["start"])
        // Optimistic, like the SSID button: the window takes a moment to come
        // up and the light must not lag the pointer.
        root.airdrop = Object.assign({}, root.airdrop, { running: true })
    }

    function setLocalSend(on) {
        if (on) {
            root.openLocalSend()
            return
        }
        root.run(root.airdropCmd, ["stop"])
        root.airdrop = Object.assign({}, root.airdrop, { running: false })
        settle.start()
    }

    // ---------- actions ----------
    // Actions (join/pair) are execDetached rather than polls: they can block
    // for seconds waiting on a phone, and a Poll would hold its process open
    // that whole time.
    function run(script, args) {
        Quickshell.execDetached([script].concat(args || []))
    }

    function setWifiRadio(on) {
        root.run(Tokyo.scriptDir + "/wifi-radio.sh", [on ? "on" : "off"])
        // Optimistic, like the SSID button: nmcli returns before the radio has
        // actually dropped, so waiting for the poll leaves the switch lagging
        // behind the pointer.
        root.wl = Object.assign({}, root.wl, { radio: on })
        settle.start()
    }

    function setBtRadio(on) {
        root.run(Tokyo.scriptDir + "/bt-radio.sh", [on ? "on" : "off"])
        root.bt = Object.assign({}, root.bt, { powered: on })
        settle.start()
    }

    /// Bring the wired link down or back up. There is no optimistic update
    /// here, unlike the two radios: `ethUp` is read from the interface's
    /// carrier, and carrier does not answer until the interface has actually
    /// gone quiet — an optimistic write would light the switch for a link that
    /// is still up, or blank it for one that is still carrying. The 900ms
    /// settle is enough for nmcli to finish the transition.
    function setEthEnabled(on) {
        root.run(Tokyo.scriptDir + "/eth-radio.sh", [on ? "on" : "off"])
        settle.start()
    }

    function joinWifi(ssid, password) {
        root.notice = "Joining " + ssid + "…"
        root.run(Tokyo.scriptDir + "/wifi-connect.sh",
                 password ? ["join", ssid, password] : ["join", ssid])
        confirm.start()
    }

    function leaveWifi() {
        root.notice = "Leaving…"
        root.run(Tokyo.scriptDir + "/wifi-connect.sh", ["leave"])
        confirm.start()
    }

    function scanBluetooth() {
        root.scanning = true
        root.notice = "Scanning…"
        btScanPoll.refresh()
    }

    function toggleDevice(mac, paired, connected) {
        root.notice = ""
        // Busy from before the script is even spawned: bt-dev.sh pair blocks for
        // up to 25s waiting on the phone, and a row that only spins once the
        // script returns looks like nothing happened for those 25 seconds.
        root.btBusy = mac
        if (!paired || !connected)
            root.run(Tokyo.scriptDir + "/bt-dev.sh", ["connect", mac])
        else
            root.run(Tokyo.scriptDir + "/bt-dev.sh", ["disconnect", mac])
        // Pairing waits on a tap on the other device, so this is deliberately
        // slower than a radio toggle.
        confirm.start()
    }

    // One timer for every deferred re-poll: whatever was just clicked needs a
    // beat to actually take effect before the poll will show it.
    Timer {
        id: settle
        interval: 900
        onTriggered: root.refreshAll()
    }
    Timer {
        id: confirm
        interval: 4000
        onTriggered: { root.refreshAll(); root.notice = ""; root.btBusy = "" }
    }

    /// The pill is the three glyphs and nothing else: no link name, no SSID, no
    /// "off". The power glyph is last, so it sits against the screen edge and
    /// the net icons read as its traffic rather than the other way round.
    fragments: [
        {
            text: "\uef44",
            color: Tokyo.blue,
            visible: root.ethUp,
        },
        {
            text: "\uf1eb",
            color: Tokyo.cyan,
            visible: root.wifiUp,
        },
        {
            text: "\uf011",
            color: Tokyo.fg,
            visible: true,
        },
    ]
    hPad: 12
    tooltip: ""

    onClicked: button => {
        if (button === Qt.LeftButton && root.flyoutHost) {
            root.flyoutHost.toggleFor(root)
            root.flyoutHost.refreshAll()
        }
    }
}
