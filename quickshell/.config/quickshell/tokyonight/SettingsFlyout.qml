// SettingsFlyout.qml — click flyout for the combined net+power pill.
//
// Windows 11 shaped, because that is the shape asked for: a row of tiles, each
// one a switch with its own label, and clicking a tile opens that service's
// detail below. Nothing is a tab bar because nothing here is a peer panel —
// wi-fi and bluetooth are two independent machines that happen to live in one
// menu, and you can have either or both open at once.
//
//   WI-FI       switch, then every network. Networks this machine has used are
//               listed; the ones a scan found that it has never joined stay out
//               of the way until SHOW ALL is pressed, because a flat in a busy
//               building otherwise buries your own network under nine
//               strangers. The ADVANCED disclosure is where the old net
//               flyout's whole block lives — SSID, IP, netmask, DNS, MAC, and
//               the live up/down/ping — for whichever link is up.
//   BLUETOOTH   switch, the paired devices, and a scan button for new ones.
//   AIRDROP     LocalSend. The tile is the whole feature: press it and the
//               window opens, or comes forward if it is already open, and the
//               switch is just on/off for the app itself.
//   POWER       sleep, reboot, shutdown.
import QtQuick
import QtQuick.Shapes
import Quickshell

PopupWindow {
    id: root

    visible: false
    grabFocus: true
    color: "transparent"

    /// the Settings.qml pill — the state and the actions both live there
    property var pill: null

    /// which detail panel is open under the tiles: "", "wifi", "bt"
    property string open: ""
    /// the old net flyout's two tabs, inside the wi-fi detail
    /// 0 = ethernet, 1 = wi-fi
    property int linkTab: 0
    property string entering: ""

    readonly property real gap: 6
    readonly property real padH: 16
    readonly property real padV: 12
    readonly property int tileW: 148
    readonly property int tileH: 56

    // Three tiles and their two gaps: 444 + 16, plus the padding either side.
    implicitWidth: root.tileW * 3 + root.padH * 2 + 16
    implicitHeight: box.height + root.gap

    // ---------------- the reveal ----------------
    // 0 = closed, 1 = open. Everything the panel does on the way in is a
    // function of this one number, so the whole thing moves as one gesture
    // rather than several items each starting their own animation.
    property real t: 0
    /// Set while the close runs, so a second click cannot restart it halfway
    /// and strand the panel at some `t` between 0 and 1.
    property bool closing: false

    /// One window's worth of reveal, given how far along the reveal is. Every
    /// part of the panel calls this with its own index and gets its slice of the
    /// same curve, offset by `i * stagger`: the panel does not fade in as one
    //  flat sheet, it arrives top to bottom, each row a beat behind the last.
    /// `span` is the width of one row's own fade — the overlap between
    /// neighbours, so there is no dead time between them.
    function stagger(i, span) {
        const start = i * root.staggerStep
        const x = (root.t - start) / span
        return x < 0 ? 0 : (x > 1 ? 1 : x)
    }
    /// Seconds between two rows starting. Small: a stagger you notice as
    /// "slow" is worse than no stagger at all.
    readonly property real staggerStep: 0.045
    /// Width of one row's fade, as a fraction of the total. 0.62 with a 0.045
    /// step means six rows are moving at once and the last still finishes at
    /// t = 0.85, so the tail is not left hanging.
    readonly property real staggerSpan: 0.62

    // OutQuart both ways, the same curve the clock flyout uses: the panel
    // decelerates into place instead of arriving at speed and stopping dead.
    // No overshoot — on a panel this size a bounce reads as a wobble.
    SequentialAnimation {
        id: openAnim
        NumberAnimation {
            target: root; property: "t"
            from: 0; to: 1
            duration: 260
            easing.type: Easing.OutQuart
        }
    }

    // The exit is quicker than the entrance (200 vs 260): a panel you are
    // closing is a panel you have already decided about, and making it wait is
    // making the next click feel late. No `from:` — the animation starts from
    // wherever `t` actually is, which is the only way a close can interrupt a
    // half-finished open without a jump.
    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            target: root; property: "t"
            to: 0
            duration: 200
            easing.type: Easing.InQuart
        }
        ScriptAction { script: root.hide() }
    }

    function hide() {
        root.closing = false
        root.visible = false
    }

    function toggleFor(item) {
        root.pill = item
        root.anchor.item = item
        root.anchor.edges = Edges.Bottom
        root.anchor.gravity = Edges.Bottom
        if (root.closing) {
            // A close is in flight: this click reverses it rather than opening
            // a second panel, which is what a plain visible toggle would do.
            closeAnim.stop()
            root.closing = false
            openAnim.start()
            return
        }
        if (root.visible) {
            root.closing = true
            closeAnim.start()
            return
        }
        if (root.pill !== null) {
            root.linkTab = root.pill.primaryEthernet ? 0 : 1
            root.open = ""
        }
        root.visible = true
        root.t = 0
        openAnim.start()
    }

    // A panel dismissed by an outside click never reaches `hide()`: the
    // compositor closes an xdg_popup itself, and the surface is already gone by
    // the time we hear about it. So there is nothing to animate — just drop `t`
    // so the next open starts from the top rather than mid-reveal.
    onVisibleChanged: {
        // The speedtest runs either way; this only picks its cadence. Open
        // kicks a fresh run so the row is current with the panel, close
        // hands the pill back its slow background rhythm.
        if (root.pill !== null) root.pill.setSpeedLive(visible)
        if (visible) return
        openAnim.stop()
        closeAnim.stop()
        root.closing = false
        root.t = 0
    }

    // Escape closes, as a window shortcut rather than a `Keys` handler: a popup
    // holding the keyboard grab *is* the active window, so a window shortcut
    // matches, and Qt resolves shortcuts before ordinary key propagation, which
    // keeps Escape out of the password field's mouth.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: {
            if (root.closing) return
            root.closing = true
            closeAnim.start()
        }
    }

    /// Ask the pill for fresh samples. Called after opening, and again after
    /// any action, since a click here is a request to change the machine.
    function refreshAll() {
        if (root.pill !== null) root.pill.refreshAll()
    }

    // ---------- derived ----------
    readonly property var wifi: root.pill === null
        ? { radio: false, active: "", networks: [] } : root.pill.wl
    readonly property var bt: root.pill === null
        ? { powered: false, devices: [] } : root.pill.bt
    readonly property var btList: root.pill === null ? [] : root.pill.btList
    readonly property bool scanning: root.pill !== null && root.pill.scanning
    readonly property string btBusy: root.pill === null ? "" : root.pill.btBusy
    readonly property string notice: root.pill === null ? "" : root.pill.notice
    readonly property bool ssidShown: root.pill !== null && root.pill.ssidShown
    readonly property bool ethUp: root.pill !== null && root.pill.ethUp
    readonly property bool wifiUp: root.pill !== null && root.pill.wifiUp
    readonly property var airdrop: root.pill === null
        ? { running: false } : root.pill.airdrop

    /// The networks to draw: the ones this machine has used, plus anything
    /// joined right now. `showAll` adds the rest of the scan. Sorted by signal
    /// already by the script, so the list needs no reordering.
    property bool showAll: false
    readonly property var shownNets: {
        if (!root.showAll)
            return root.wifi.networks.filter(n => n.known === true
                                               || n.active === true)
        return root.wifi.networks
    }
    /// Networks in range that are neither known nor in use — the count that
    /// goes on the SHOW ALL button, so the button is not a mystery toggle.
    readonly property int hiddenNets: root.wifi.networks.length
                                     - root.shownNets.length

    /// Every device this machine has paired, connected or not. A paired device
    /// that happens to be off is not the same information as one that has never
    /// been paired: you paired it, you know it is there, and hiding it behind a
    /// disclosure meant the list you saw depended on which buttons you had
    /// pressed. Both are listed, and the row's own status says which is which.
    readonly property var shownBt: root.btList

    /// The old flyout's per-link block, for the tab that is showing.
    readonly property string linkStats: root.pill === null
        ? ""
        : (root.linkTab === 0 ? root.pill.ethernetTooltip : root.pill.wifiTooltip)

    /// The speedtest line, split per direction so each figure carries its
    /// own colour: download keeps the cyan this row always had, upload is
    /// purple. The state words live on the download side and the upload
    /// stays blank until there is a second figure, so "testing…" is shown
    /// once rather than twice.
    readonly property string speedDownText: {
        const s = root.pill === null ? null : root.pill.speed
        if (s === null || s.testing) return "testing…"
        const down = s.down > 0 ? s.down.toFixed(1) : "–"
        const up = s.up > 0 ? s.up.toFixed(1) : "–"
        if (down === "–" && up === "–") return "no result"
        // Same arrow pair the DISK strip uses: down is the download
        // direction there and here, so the two panels read the same way.
        return "\uf063 " + down + " Mbps"
    }
    readonly property string speedUpText: {
        const s = root.pill === null ? null : root.pill.speed
        if (s === null || s.testing) return ""
        const down = s.down > 0 ? s.down.toFixed(1) : "–"
        const up = s.up > 0 ? s.up.toFixed(1) : "–"
        if (down === "–" && up === "–") return ""
        return "\uf062 " + up + " Mbps"
    }

    /// A bar of signal, so strength is a glance and not a number to read.
    function bars(signal) {
        return signal >= 80 ? 4 : signal >= 60 ? 3 : signal >= 35 ? 2 : 1
    }

    // ---------- shared bits ----------
    component SectionLabel: Text {
        font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
        color: Tokyo.blue
        leftPadding: 4
        bottomPadding: 2
    }

    component Rule: Rectangle {
        color: Tokyo.bgHighlight
        height: 1
    }

    /// The on/off switch. A Capsule track with a knob that slides, rather than
    /// a checkbox: it reads as a switch without a label saying "on" or "off"
    /// next to it, and the knob's side is the state.
    component Toggle: Item {
        id: sw
        // `checked`, not `on`: a property called `on` makes `on: <expr>`
        // ambiguous with a signal-handler declaration, and the parser wins
        // that fight.
        property bool checked: false
        property color accent: Tokyo.cyan
        signal toggled()
        implicitWidth: 38
        implicitHeight: 20

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(sw.accent.r, sw.accent.g, sw.accent.b,
                           sw.checked ? 0.30 : 0.10)
            border.color: sw.checked ? sw.accent : Tokyo.bgHighlight
            border.width: 1
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        Rectangle {
            width: 14; height: 14; radius: 7
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            color: sw.checked ? sw.accent : Tokyo.dim
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.toggled()
        }
    }

    /// One Windows-11-style quick-settings tile: a glyph, a label, the switch,
    /// and a subline saying what it is currently doing. The whole tile is the
    /// switch's hit area, so you do not have to find the 38px switch.
    component Tile: Item {
        id: tl
        property string glyph: ""
        property string label: ""
        property string sub: ""
        property color accent: Tokyo.cyan
        property bool lit: false
        property bool expanded: false
        /// the tile body was pressed: open or close this service's detail
        signal toggled()
        /// the switch was pressed: actually change the machine
        signal switched()
        implicitWidth: 148
        implicitHeight: 56

        Rectangle {
            id: tileBg
            anchors.fill: parent
            radius: 8
            color: tl.expanded ? Qt.rgba(tl.accent.r, tl.accent.g, tl.accent.b, 0.22)
                   : hover.containsMouse ? Tokyo.pane
                   : Qt.rgba(tl.accent.r, tl.accent.g, tl.accent.b, 0.10)
            border.color: tl.expanded ? tl.accent : Tokyo.bgHighlight
            border.width: 1
            Behavior on color { ColorAnimation { duration: 130 } }
        }
        Text {
            id: g
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -9
            text: tl.glyph
            color: tl.lit ? tl.accent : Tokyo.dim
            font { family: Tokyo.fontFamily; pixelSize: 15 }
        }
        Text {
            // Both lines stop at the switch, not at the tile edge. `swArea` runs
            // the tile's full height, so the subline — the SSID, at topMargin 24
            // and about 11px tall — sits exactly across the switch's own band
            // (y 22..39). Anchored to parent.right it drew underneath it, and
            // a 24-character SSID drew a long way in.
            anchors { left: g.right; leftMargin: 8; right: swArea.left
                      rightMargin: 4; top: parent.top; topMargin: 9 }
            text: tl.label
            color: Tokyo.fg
            elide: Text.ElideRight
            font { family: Tokyo.fontFamily; pixelSize: 11; bold: true }
        }
        Text {
            anchors { left: g.right; leftMargin: 8; right: swArea.left
                      rightMargin: 4; top: parent.top; topMargin: 24 }
            text: tl.sub
            color: Tokyo.dim
            elide: Text.ElideRight
            font { family: Tokyo.fontFamily; pixelSize: 9 }
        }
        // Pressing the tile body opens its detail; the switch in the corner
        // is the only thing that changes the machine. The two hit areas are
        // kept apart explicitly, because one MouseArea covering the whole
        // tile would swallow the switch's clicks and the switch would be
        // dead — the classic nested-MouseArea trap.
        MouseArea {
            id: hover
            anchors { left: parent.left; leftMargin: 8; right: swArea.left
                      top: parent.top; bottom: parent.bottom }
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tl.toggled()
        }
        Item {
            id: swArea
            anchors { right: parent.right; rightMargin: 6; top: parent.top
                      topMargin: 5; bottom: parent.bottom }
            width: 36
            Toggle {
                anchors.centerIn: parent
                width: 38
                height: 20
                scale: 0.79
                checked: tl.lit
                accent: tl.accent
                onToggled: tl.switched()
            }
        }
    }

    /// One row of a device list. `status` is a short right-hand word so the
    /// meaning does not depend on colour alone.
    component DeviceRow: Item {
        id: dr
        property string name: ""
        /// NOT `right` or `state`: QQuickItem already has both, and shadowing
        /// either makes anchors.right / the enabled-state machinery inside
        /// this component resolve to a string.
        property string status: ""
        property color accent: Tokyo.dim
        /// replaces the status word with a turning arc, so the row reads as
        /// working on something rather than as a row with a label on it
        property bool busy: false
        property string glyph: ""
        /// Opt-in, and off by default: this row is also the wifi network list
        /// and the scan button, and neither of those has anything to forget. A
        /// new call site therefore cannot grow a × by forgetting to ask.
        property bool forgetable: false
        /// Hover as state, rather than reading `hover.containsMouse` at each
        /// use site: the reveal is decided once here, because the × and the
        /// status word are competing for one slot and must not disagree about
        /// which of them owns it.
        property bool hovered: hover.containsMouse
        // NOT just `dr.hovered`. `hover` and the ×'s own MouseArea are
        // SIBLINGS, and Qt delivers hover to the deepest item under the cursor
        // and then to its ancestors only — never sideways. So the moment the
        // pointer crosses onto the plate, `forgetMouse` becomes the hover leaf,
        // `hover.containsMouse` goes false, and a reveal that reads only
        // `dr.hovered` hides the × from under the cursor — which then re-hides
        // it and re-shows it on every subsequent move. Measured, 1px steps
        // across the plate: VVVVVV.V.V.V.V.V.V.V.V.
        // The consequence is not cosmetic: while the × is hidden it is out of
        // the hit test, so the press falls through to the whole-row MouseArea
        // and TOGGLES the connection instead of forgetting. `||` breaks the
        // cycle without a latch: over the row -> shown -> the plate can then
        // hold hover -> still shown; off both -> both false -> hidden.
        readonly property bool forgetShown: dr.forgetable && !dr.busy
                                              && (dr.hovered
                                                  || forgetMouse.containsMouse)
        signal clicked()
        signal forgotten()
        implicitHeight: 26
        implicitWidth: 200

        Rectangle {
            anchors.fill: parent
            anchors.rightMargin: -4
            radius: 6
            color: hover.containsMouse ? Tokyo.pane : "transparent"
            Behavior on color { ColorAnimation { duration: 100 } }
        }
        Text {
            id: g
            visible: dr.glyph !== ""
            text: dr.glyph
            color: dr.accent
            anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
            font { family: Tokyo.fontFamily; pixelSize: 11 }
        }
        Text {
            objectName: "rowName"
            anchors {
                left: g.visible ? g.right : parent.left
                leftMargin: g.visible ? 7 : 6
                right: stateText.left
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: dr.name
            elide: Text.ElideRight
            color: dr.accent
            font { family: Tokyo.fontFamily; pixelSize: 11 }
        }
        Text {
            id: stateText
            objectName: "stateWord"
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            // Same rule the spinner follows, one more competitor: whatever holds
            // the slot hides the word. It is hidden rather than emptied so the
            // name's right anchor — which is this item's left edge — does not
            // move under the pointer and reflow the row as the mouse arrives.
            visible: !dr.busy && !forgetShown
            text: dr.status
            color: Tokyo.dim
            font { family: Tokyo.fontFamily; pixelSize: 10; letterSpacing: 0.8 }
        }

        // The spinner is a three-quarter arc turning forever, drawn in place of
        // the status word rather than beside it: this row's right-hand slot is
        // one piece of state, and a spinner next to a word is two. A bare
        // ellipsis was the previous answer and it did not read as motion — a
        // static "…" looks like a label that happens to be truncated.
        Item {
            id: spin
            visible: dr.busy
            anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
            width: 11
            height: 11

            // Same legibility reasoning as the gauge ring: a 270° arc is one
            // long curve, and CurveRenderer plus 4x MSAA keeps its edges smooth
            // on a surface with no multisampling of its own.
            Shape {
                id: ring
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.samples: 4

                readonly property real r: Math.min(ring.width, ring.height) / 2 - 1

                ShapePath {
                    strokeWidth: 1.6
                    strokeColor: Tokyo.yellow
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: ring.width / 2
                        centerY: ring.height / 2
                        radiusX: ring.r
                        radiusY: ring.r
                        startAngle: 90
                        sweepAngle: 270
                    }
                }
            }

            // RotationAnimator rather than a plain RotationAnimation: this is a
            // pure transform on an unchanging path, so it stays off the render
            // thread's sync path and never competes with a panel repaint. Bound
            // to `running` so a row that stops being busy stops burning frames.
            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
                running: spin.visible
            }
        }
        MouseArea {
            id: hover
            // Named so a test can tell "the row's own click area got it" apart
            // from "nothing got it". Returning a bare `other` for both makes a
            // dead right-hand slot indistinguishable from a working row.
            objectName: "rowHit"
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dr.clicked()
        }

        // Forget, for a paired bluetooth row and nothing else. Declared AFTER
        // the whole-row MouseArea above and given an explicit z on top of it:
        // that area is anchored to fill the row, so z is what decides which of
        // the two takes a press — and if it is the row, a click on the × forgets
        // nothing and toggles the connection instead.
        //
        // z only decides who gets the press. Whether the × is THERE to get it
        // is `forgetShown` above, and that is the half that was broken: a
        // hidden × is out of the hit test, so a hover bug silently becomes a
        // click bug. Both halves are covered by tests/test-forget-button.sh.
        Rectangle {
            id: forgetHit
            // A named handle on the one thing a test cannot reach from outside
            // an inline component — its inner ids are private to this scope.
            objectName: "forgetHit"
            visible: forgetShown
            z: 1
            anchors { right: parent.right; rightMargin: 4
                      verticalCenter: parent.verticalCenter }
            width: 20; height: 20
            radius: 5
            color: forgetMouse.containsMouse ? Tokyo.bgHighlight : "transparent"

            // Same glyph, size and hover plate as the toast dismiss, so a
            // forget and a dismiss are the same shape to the hand.
            Text {
                anchors.centerIn: parent
                text: "×"
                color: Tokyo.dim
                font { family: Tokyo.fontFamily; pixelSize: 13 }
            }
            MouseArea {
                id: forgetMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // forget, and ONLY forget. `dr.clicked()` here as well would
                // make one click drop the pairing and immediately ask the
                // device to pair again, which is the opposite of forgetting it.
                onClicked: dr.forgotten()
            }
        }
    }

    Rectangle {
        id: box
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: content.implicitHeight + root.padV * 2
        color: Tokyo.bgDark
        radius: Tokyo.pillRadius
        border.width: 1

        // The panel rises the last few pixels and fades as it goes. A panel that
        // only fades still reads as a rectangle that was switched on; the rise
        // is what says it came from the pill. 8px, and it is done before the
        // fade finishes, so the motion is over by the time the panel is legible
        // — the reader never watches text slide.
        opacity: root.t
        transform: Translate { id: boxRise; y: (1 - root.t) * 8 }
        Behavior on border.color {
            ColorAnimation { duration: 200 }
        }
        border.color: Qt.lighter(box.color, 1 + 0.25 * root.t)

        Column {
            id: content
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: root.padH; rightMargin: root.padH; topMargin: root.padV
            }
            spacing: 8

            // ================= POWER =================
            // The stagger indices below count bands, not widgets: the whole
            // power block is band 0, the tiles band 1, and so on. Anything that
            // opens a detail panel is band 2, so the two detail panels do not
            // each get a later start and end up noticeably behind the power
            // buttons they are nowhere near.
            SectionLabel {  id: bandPowerLabel
                text: "POWER"
                width: parent.width
                opacity: root.stagger(0, root.staggerSpan)
                transform: Translate { y: (1 - bandPowerLabel.opacity) * 5 }
            }
            Rule {
                width: parent.width
                opacity: root.stagger(0, root.staggerSpan)
            }
            Row {  id: bandPowerRow
                width: parent.width
                spacing: 8
                opacity: root.stagger(0, root.staggerSpan)
                transform: Translate { y: (1 - bandPowerRow.opacity) * 5 }
                // One tile-width cell per action, aligned with the tiles
                // below: shutdown and reboot each get a full cell (root.tileW),
                // sleep and log out share the third (tileW - 8, half each, the
                // 8 being their gap). The row sums to content.width exactly.
                PillButton {
                    width: root.tileW
                    text: "SHUTDOWN"
                    glyph: ""
                    accent: Tokyo.red
                    onClicked: Quickshell.execDetached(["systemctl", "poweroff"])
                }
                PillButton {
                    width: root.tileW
                    text: "REBOOT"
                    glyph: ""
                    accent: Tokyo.magenta
                    onClicked: Quickshell.execDetached(["systemctl", "reboot"])
                }
                PillButton {
                    width: (root.tileW - 8) / 2
                    text: "SLEEP"
                    glyph: ""
                    accent: Tokyo.yellow
                    onClicked: Quickshell.execDetached(["systemctl", "suspend"])
                }
                // Log out rather than power down: `hyprctl dispatch exit`
                // ends the session and leaves the machine at the login
                // screen, which is the one thing this row could not do. The
                // sign-out glyph \uf08b, not the power glyph the other
                // three wear — three identical buttons in one row is how a
                // logout becomes an accidental shutdown.
                PillButton {
                    width: (root.tileW - 8) / 2
                    text: "LOGOUT"
                    glyph: "\uf08b"
                    accent: Tokyo.blue
                    onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
                }
            }
            // ================= the two tiles =================
            Row {  id: bandTiles
                width: parent.width
                spacing: 8
                opacity: root.stagger(1, root.staggerSpan)
                transform: Translate { y: (1 - bandTiles.opacity) * 5 }

                Tile {
                    id: wifiTile
                    width: root.tileW
                    height: root.tileH
                    glyph: ""
                    label: "Wi-Fi"
                    accent: Tokyo.cyan
                    lit: root.wifi.radio
                    expanded: root.open === "wifi"
                    sub: root.wifi.radio
                        ? (root.wifi.active !== "" ? root.wifi.active : "Not connected")
                        : "Off"
                    onToggled: {
                        root.open = root.open === "wifi" ? "" : "wifi"
                        root.showStats = false
                    }
                    onSwitched: {
                        if (root.pill !== null)
                            root.pill.setWifiRadio(!root.wifi.radio)
                    }
                }

                Tile {
                    id: btTile
                    width: root.tileW
                    height: root.tileH
                    glyph: ""
                    label: "Bluetooth"
                    accent: Tokyo.blue
                    lit: root.bt.powered
                    expanded: root.open === "bt"
                    sub: {
                        if (!root.bt.powered) return "Off"
                        const n = root.btList.filter(d => d.connected).length
                        if (n > 0) return n + " connected"
                        return root.btList.length + " paired"
                    }
                    onToggled: {
                        root.open = root.open === "bt" ? "" : "bt"
                    }
                    onSwitched: {
                        if (root.pill !== null)
                            root.pill.setBtRadio(!root.bt.powered)
                    }
                }

                // Airdrop is LocalSend. No detail panel under it: the tile body
                // is the whole feature — it opens (or raises) the window, which
                // is where you send anything. A panel here would be one more
                // click in front of the app for no extra power.
                Tile {
                    id: lsTile
                    width: root.tileW
                    height: root.tileH
                    glyph: ""
                    label: "Airdrop"
                    accent: Tokyo.green
                    lit: root.airdrop.running
                    sub: root.airdrop.running ? "Running" : "Off"
                    onToggled: {
                        if (root.pill !== null) root.pill.openLocalSend()
                    }
                    onSwitched: {
                        if (root.pill !== null)
                            root.pill.setLocalSend(!root.airdrop.running)
                    }
                }
            }

            // ================= SPEEDTEST =================
            // The peak this line can currently reach, re-tested on a timer.
            // The pill always runs the test; this panel only sets the
            // cadence (onVisibleChanged) — fast while it is open, a slow
            // background rhythm when it is not — so opening always finds a
            // fresh run and a shut panel still keeps results coming.
            //
            // Two figures in one card rather than a gauge: down and up are
            // read against each other, and a ring per direction would double
            // the row to say half of what one line says.
            Item {  id: bandSpeed
                width: parent.width
                height: 26
                opacity: root.stagger(1, root.staggerSpan)
                transform: Translate { y: (1 - bandSpeed.opacity) * 5 }

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: Tokyo.bg
                    border.color: Tokyo.bgHighlight
                    border.width: 1
                }
                Text {
                    id: speedLabel
                    anchors {
                        left: parent.left; leftMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    text: "SPEEDTEST"
                    color: Tokyo.yellow
                    font { family: Tokyo.fontFamily; pixelSize: 10
                           bold: true; letterSpacing: 1.5 }
                }
                Row {
                    id: speedValue
                    anchors {
                        right: parent.right; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 12
                    Text {
                        width: implicitWidth
                        elide: Text.ElideRight
                        text: root.speedDownText
                        color: Tokyo.cyan
                        font { family: Tokyo.fontFamily; pixelSize: 12; bold: true }
                    }
                    Text {
                        visible: root.speedUpText !== ""
                        width: implicitWidth
                        elide: Text.ElideRight
                        text: root.speedUpText
                        color: Tokyo.purple
                        font { family: Tokyo.fontFamily; pixelSize: 12; bold: true }
                    }
                }
            }

            // The tile's label doubles as its disclosure: pressing the glyph
            // side of a tile that is already on opens its detail, and the
            // switch is the small control in the corner. A second row of
            // buttons would be one more thing to read.
            Item {  id: bandHead
                width: parent.width
                height: 18
                visible: root.open !== ""
                // This band and the two detail panels below it are one band:
                // the header only ever exists with a panel under it, and giving
                // them separate indices would make the panel arrive visibly
                // later than the label naming it.
                opacity: root.open === "" ? 0 : root.stagger(2, root.staggerSpan)
                transform: Translate { y: (1 - bandHead.opacity) * 5 }

                Text {
                    anchors { left: parent.left; leftMargin: 6
                              verticalCenter: parent.verticalCenter }
                    text: root.open === "wifi" ? "NETWORKS" : "DEVICES"
                    color: Tokyo.blue
                    font { family: Tokyo.fontFamily; pixelSize: 10
                           bold: true; letterSpacing: 1.5 }
                }
                PillButton {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "CLOSE"
                    accent: Tokyo.dim
                    onClicked: root.open = ""
                }
            }

            Rule {
                width: parent.width
                visible: root.open !== ""
                opacity: root.open === "" ? 0 : root.stagger(2, root.staggerSpan)
            }

            // ================= WI-FI detail =================
            Column {  id: bandWifi
                width: parent.width
                spacing: 5
                visible: root.open === "wifi"
                opacity: root.open === "wifi"
                         ? root.stagger(2, root.staggerSpan) : 0
                transform: Translate { y: (1 - bandWifi.opacity) * 5 }

                Repeater {
                    model: root.shownNets
                    delegate: Item {
                        required property var modelData
                        width: content.width
                        // 26 for the row, 52 only while this row's password
                        // field is open. The test used to read `entering !==
                        // ssid`, which handed the tall row to the one network
                        // that can never have a password field — the connected
                        // one — plus every open network, and left 26px of
                        // nothing under the row you are actually on.
                        height: modelData.secure && !modelData.active
                               && root.entering === modelData.ssid ? 52 : 26

                        DeviceRow {
                            id: netRow
                            width: parent.width
                            name: modelData.ssid
                            // A key means the password is saved, so clicking
                            // connects without asking. A padlock means the network
                            // is secured but this machine has no profile for it, so
                            // clicking opens the password field. Neither means the
                            // network is open and clicking joins straight away. The
                            // glyph says which of the three it is before you try.
                            glyph: root.bars(modelData.signal)
                                   + (modelData.active ? ""
                                      : modelData.secure
                                          ? " "
                                              + (modelData.known ? "\uf084"
                                                                 : "\uf023")
                                          : "")
                            accent: modelData.active ? Tokyo.cyan
                                  : modelData.known ? Tokyo.fg : Tokyo.yellow
                            status: modelData.active ? "CONNECTED"
                                  : modelData.known
                                      ? "SAVED " + modelData.signal + "%"
                                      : modelData.signal + "%"
                            onClicked: {
                                if (modelData.active) {
                                    if (root.pill !== null) root.pill.leaveWifi()
                                } else if (modelData.secure && !modelData.known) {
                                    // Only a network this machine has no profile
                                    // for gets a password field. Asking for one
                                    // on a saved network asks for something you
                                    // already have, and it is the one case where
                                    // a click cannot do what the glyph promised.
                                    root.entering = modelData.ssid
                                } else {
                                    // An empty password is not "no password" — it
                                    // is the argument wifi-connect.sh leaves off,
                                    // so nmcli connects with the saved one.
                                    if (root.pill !== null)
                                        root.pill.joinWifi(modelData.ssid, "")
                                }
                            }
                        }

                        // The password row, only for a secured network that is
                        // not the one you are on. An open network joins on click.
                        Item {
                            visible: modelData.secure && !modelData.active
                                     && root.entering === modelData.ssid
                            anchors { left: parent.left; right: parent.right
                                      top: netRow.bottom }
                            height: visible ? 24 : 0

                            Row {
                                anchors { left: parent.left; right: parent.right
                                          verticalCenter: parent.verticalCenter }
                                spacing: 6

                                Rectangle {
                                    // The leftovers, so the field takes
                                    // whatever the two buttons do not. Both
                                    // widths are known by the time this row has
                                    // been laid out, and if the flyout is ever
                                    // narrowed too far it floors at 80 rather
                                    // than collapsing to nothing.
                                    width: Math.max(80, parent.width
                                                        - joinBtn.width
                                                        - cancelBtn.width - 12)
                                    height: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    radius: 6
                                    color: Tokyo.bgHighlight
                                    border.color: passField.activeFocus ? Tokyo.cyan
                                                     : "transparent"
                                    border.width: 1

                                    TextInput {
                                        id: passField
                                        anchors { left: parent.left; leftMargin: 8
                                                  right: parent.right; rightMargin: 8
                                                  verticalCenter: parent.verticalCenter }
                                        font { family: Tokyo.fontFamily; pixelSize: 11 }
                                        color: Tokyo.fg
                                        echoMode: TextInput.Password
                                        clip: true
                                        Keys.onEscapePressed: { root.entering = "" }
                                    }
                                }
                                PillButton {
                                    id: joinBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "JOIN"
                                    accent: Tokyo.cyan
                                    onClicked: {
                                        root.entering = ""
                                        if (root.pill !== null)
                                            root.pill.joinWifi(modelData.ssid,
                                                               passField.text)
                                    }
                                }
                                PillButton {
                                    id: cancelBtn
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "CANCEL"
                                    accent: Tokyo.dim
                                    onClicked: {
                                        root.entering = ""
                                        passField.text = ""
                                    }
                                }
                            }
                        }
                    }
                }

                // `known` is what wifi-list.sh calls a network this machine has
                // a saved profile for. The others are one click away, and the
                // count says how many are being held back.
                PillButton {
                    visible: root.hiddenNets > 0
                    text: root.showAll
                        ? "HIDE " + root.hiddenNets + " UNKNOWN"
                        : "SHOW ALL " + root.hiddenNets
                    accent: root.showAll ? Tokyo.dim : Tokyo.blue
                    onClicked: root.showAll = !root.showAll
                }

                // An empty list is three different things and one line each,
                // because "nothing here" is a useless thing to say.
                Text {
                    width: parent.width
                    visible: root.shownNets.length === 0
                    text: !root.wifi.radio ? "Wi-Fi is off."
                        : root.wifi.networks.length === 0 ? "Scanning for networks…"
                        : root.hiddenNets > 0
                            ? "No known networks. SHOW ALL to see the "
                              + root.hiddenNets + " nearby."
                            : "No networks in range."
                    color: Tokyo.dim
                    wrapMode: Text.WordWrap
                    font { family: Tokyo.fontFamily; pixelSize: 10 }
                }

                // ---------- ADVANCED: the old net flyout ----------
                Item {
                    width: parent.width
                    height: 20

                    PillButton {
                        id: advBtn
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: root.showStats ? "HIDE DETAILS" : "ADVANCED"
                        accent: root.showStats ? Tokyo.dim : Tokyo.cyan
                        onClicked: root.showStats = !root.showStats
                    }
                    // The reveal/hide button only makes sense on the wi-fi tab.
                    PillButton {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        visible: root.linkTab === 1
                        glyph: ""
                        text: root.ssidShown ? "HIDE" : "SHOW SSID"
                        accent: Tokyo.cyan
                        onClicked: {
                            if (root.pill !== null) root.pill.toggleSsid()
                        }
                    }

                    // The wired link's own switch, on the ethernet tab only — the
                    // same slot SHOW SSID uses on the wi-fi tab, because both are
                    // "this link is on / off" and neither belongs on the other tab.
                    //
                    // No fourth tile: the tile row is three wide and the panel is
                    // sized for it, and ethernet already has a panel of its own
                    // under ADVANCED. Adding a tile to reach a switch that has
                    // always been in this panel is a worse trade than one button.
                    PillButton {
                        anchors { right: parent.right
                                  verticalCenter: parent.verticalCenter }
                        visible: root.linkTab === 0
                        text: root.ethUp ? "DISABLE" : "ENABLE"
                        accent: root.ethUp ? Tokyo.dim : Tokyo.blue
                        onClicked: {
                            if (root.pill !== null)
                                root.pill.setEthEnabled(!root.ethUp)
                        }
                    }
                }


                Column {
                    width: parent.width
                    spacing: 6
                    visible: root.showStats

                    Row {
                        visible: root.linkTab === 0 || root.linkTab === 1
                        spacing: 8
                        PillButton {
                            text: "ETHERNET"
                            accent: root.linkTab === 0 ? Tokyo.blue : Tokyo.dim
                            onClicked: root.linkTab = 0
                        }
                        PillButton {
                            text: "WI-FI"
                            accent: root.linkTab === 1 ? Tokyo.cyan : Tokyo.dim
                            onClicked: root.linkTab = 1
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.linkStats
                        color: Tokyo.fg
                        wrapMode: Text.WordWrap
                        lineHeight: 1.2
                        font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize - 1 }
                    }
                }
            }

            // ================= BLUETOOTH detail =================
            Column {  id: bandBt
                width: parent.width
                spacing: 5
                visible: root.open === "bt"
                opacity: root.open === "bt" ? root.stagger(2, root.staggerSpan) : 0
                transform: Translate { y: (1 - bandBt.opacity) * 5 }

                // A discovery button rather than a live list: an always-on scan
                // would list every device in the room and drain the phone.
                DeviceRow {
                    width: parent.width
                    // A scan is off until asked for: an always-on scan drains the
                    // phone's battery and makes every device in the room show up
                    // in the list uninvited.
                    name: root.scanning ? "Scanning…" : "Find new devices"
                    status: ""
                    glyph: ""
                    accent: root.scanning ? Tokyo.yellow : Tokyo.fg
                    busy: root.scanning
                    onClicked: {
                        if (root.pill !== null) root.pill.scanBluetooth()
                    }
                }

                Repeater {
                    model: root.shownBt
                    delegate: DeviceRow {
                        required property var modelData
                        width: content.width
                        name: modelData.name
                        glyph: modelData.paired ? "" : ""
                        accent: modelData.connected ? Tokyo.cyan
                              : modelData.paired ? Tokyo.fg : Tokyo.dim
                        status: modelData.connected ? "CONNECTED"
                              : modelData.paired ? "PAIRED" : "NEW"
                        busy: root.btBusy === modelData.mac
                        // Only a paired device can be forgotten — bluez has no
                        // record to remove for one that was merely seen.
                        forgetable: modelData.paired
                        onClicked: {
                            if (root.pill !== null)
                                root.pill.toggleDevice(modelData.mac,
                                                       modelData.paired,
                                                       modelData.connected)
                        }
                        onForgotten: {
                            if (root.pill !== null)
                                root.pill.forgetDevice(modelData.mac)
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: root.shownBt.length === 0
                    text: !root.bt.powered ? "Bluetooth is off."
                        : "No bluetooth devices yet."
                    color: Tokyo.dim
                    wrapMode: Text.WordWrap
                    font { family: Tokyo.fontFamily; pixelSize: 10 }
            }

            }

            // Whatever the last click is waiting on, said once and then cleared
            // by the confirming poll. Only one line, for one line of state.
            Text {
                width: parent.width
                visible: root.notice !== ""
                text: root.notice
                color: Tokyo.yellow
                font { family: Tokyo.fontFamily; pixelSize: 10 }
            }
        }
    }

    /// Whether the ADVANCED disclosure is open. A separate property from `open`
    /// so closing the wifi panel also forgets that you had looked at the stats.
    property bool showStats: false
}
