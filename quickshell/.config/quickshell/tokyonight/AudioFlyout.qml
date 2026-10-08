// AudioFlyout.qml — click flyout for the audio pill.
//
// Sections:
//   Output devices   click a row → Pipewire.preferredDefaultAudioSink
//   Phone audio      the bluetooth phone streaming into this PC, as a switch.
//                    Always drawn; greyed out with a hover explanation when no
//                    phone is connected. Pairing itself is done in the settings
//                    flyout's bluetooth panel.
//   Input devices    click a row → Pipewire.preferredDefaultAudioSource
//                    the active input device also carries a volume slider
//                    + mute, same as the active output device above
//   Applications     per-playback-app volume slider + mute toggle
//   Advanced         bottom drawer: the switch that lifts the app sliders to
//                    150% instead of 100%
//
// Uses the native Quickshell Pipewire service (same source as Audio.qml).
// Device/app lists come from Pipewire.nodes — every node carries isSink/isStream
// flags (no isSource helper): "output device" = isSink, "app" = isSink + isStream,
// "input device" = !isSink (duplex cards are isSink, kept only when they are the
// current default source). `grabFocus` makes the xdg_popup dismiss on any outside
// click (visible flips to false automatically).
//
// CRITICAL: nodes are only bound to PipeWire while something holds a reference
// (PwObjectTracker -> refcount). Unbound nodes report zero/stale audio state and
// volume writes are dropped ("Tried to change node volumes ... not bound"). The
// tracker below keeps every listed app/device node bound so sliders work.
import QtQuick
import QtQuick.Controls.Basic as Controls
import Quickshell
import Quickshell.Services.Pipewire

PopupWindow {
    id: root

    visible: false
    grabFocus: true
    color: "transparent"

    readonly property real gap: 6      // transparent strip, like Tooltip.qml
    readonly property real padH: 16
    readonly property real padV: 12
    readonly property int rowHeight: 36

    // 392, not the 360 it was: the device rows gained a percentage readout, and
    // at 360 the device name was left with 98px — enough for "USB Audio" and
    // nothing else, so the longest names all elided to the same stub. The
    // panel is anchored to the pill, not sized by the bar, so widening it
    // costs nothing but the room it takes on screen.
    implicitWidth: 392
    implicitHeight: box.height + root.gap

    // ---------------- lists ----------------
    function correctType(node, isSink) {
        return !!node && node.isSink === isSink && !!node.audio
    }
    function outputDevicesList() {
        return Pipewire.nodes.values.filter(n => root.correctType(n, true) && !n.isStream)
    }
    // Inputs are `!isSink` audio nodes (alsa_input.* etc.). Duplex cards also
    // satisfy isSink, so keep them here only when they are the current default
    // source — otherwise they would never show up as input devices.
    //
    // The active source is kept unconditionally, `!n.audio` included. Quickshell
    // builds a node's audio interface from an exact match on media.class, so a
    // driver that names its source `Audio/Source/Virtual` (linux-soundboard)
    // gets no interface at all — and dropping it for that reason hid the one
    // mic you are actually recording from. WpAudio below still drives it.
    function inputDevicesList() {
        return Pipewire.nodes.values.filter(n => {
            if (!n || n.isStream) return false
            if (n === Pipewire.defaultAudioSource) return true
            if (!n.audio) return false
            return !n.isSink
        })
    }
    function appNodes(isSink) {
        return Pipewire.nodes.values.filter(n => root.correctType(n, isSink) && n.isStream)
    }
    readonly property var outputDevices: root.outputDevicesList()
    readonly property var inputDevices: root.inputDevicesList()
    readonly property var apps: root.appNodes(true)
    /// every node the flyout manages — kept ref'd/bound by the tracker below
    readonly property var trackedNodes: root.outputDevices.concat(root.inputDevices, root.apps)

    // ---------------- devices with no native audio interface ----------------
    /// Volume/mute for a device Quickshell gave no audio interface, addressed
    /// through wpctl instead. It presents the same `volume` / `muted` surface a
    /// PwNodeAudioIface does, so the rows below cannot tell the two apart.
    ///
    /// This is not hypothetical: a node's `media.class` is matched EXACTLY
    /// against "Audio/Source" / "Audio/Sink" / "Audio/Duplex" /
    /// "Stream/Output/Audio" / "Stream/Input/Audio" when Quickshell decides
    /// whether to build it an audio interface (PwNode::initProps), and anything
    /// else gets none. "Audio/Source/Virtual" — the linux-soundboard mic, i.e.
    /// this machine's default source — is one of those. No interface means no
    /// `volume` property, so there is nothing for a slider to bind to.
    ///
    /// wpctl addresses a node by its numeric PipeWire id and does not care
    /// about media.class at all. It is also the only way to READ back state
    /// here: there is no native signal to subscribe to, so the value is polled.
    component WpAudio: Item {
        id: wpa

        /// the PwNode this stands in for, or null
        property var node: null
        /// 0.0 - 1.0, as wpctl reports it
        property real volume: 0
        property bool muted: false
        /// One flag per polled property, NOT one shared flag: the poll absorbs
        /// both in the same tick, and each assignment synchronously runs its
        /// own onChanged handler — so a single flag would be consumed by the
        /// first one and the second would write the poll's own value straight
        /// back out as if the user had moved a control.
        ///
        /// ONLY absorbX arms these, and only when the value actually moved —
        /// see absorbVolume. writeVolume deliberately does NOT arm them: the
        /// property already holds the value just written, so the next poll
        /// finds it unchanged and never needs suppressing, and an arm here
        /// would outlive that poll and eat the following real drag.
        property bool applyingVolume: false
        property bool applyingMuted: false

        /// wpctl takes the numeric PipeWire id; a node NAME is rejected with
        /// "Error: '<name>' is not a valid number". `id` is readonly on PwNode
        /// and is exactly the number `wpctl status` prints.
        readonly property int id: wpa.node ? wpa.node.id : -1

        function writeVolume(v) {
            if (wpa.id < 0) return
            Quickshell.execDetached(["wpctl", "set-volume",
                                     String(wpa.id), Math.max(0, v).toFixed(3)])
        }
        function writeMute(on) {
            if (wpa.id < 0) return
            Quickshell.execDetached(["wpctl", "set-mute", String(wpa.id), on ? "1" : "0"])
        }

        /// Absorb a polled value WITHOUT writing it straight back out.
        ///
        /// The `if (same) return` guard is load-bearing, not an optimisation:
        /// QML fires NO onChanged when a property is assigned its current value,
        /// so arming the suppression flag and then assigning an unchanged
        /// number leaves the flag armed forever — and the next real user write
        /// is eaten as if it were an echo of the poll. Measured: a source
        /// polled every 400ms whose volume stopped at 0.82 ignored every
        /// subsequent drag because of exactly this.
        function absorbVolume(v) {
            if (Math.abs(wpa.volume - v) < 0.001) return
            wpa.applyingVolume = true
            wpa.volume = v
        }
        function absorbMuted(m) {
            if (wpa.muted === m) return
            wpa.applyingMuted = true
            wpa.muted = m
        }

        /// wpctl has NO get-mute command — asking for one prints the usage
        /// banner and changes nothing — and `wpctl inspect` does not report
        /// mute either (measured: 0 lines matching "mute" on a node that was
        /// muted at the time). Measured working read:
        /// `pactl get-source-mute <name>`, which speaks the same PipeWire graph
        /// through the pulse shim. So the probe is wpctl for the number and
        /// pactl for the flag, in one shell line, coming back as two:
        ///
        ///   Volume: 0.82
        ///   Mute: no
        ///
        /// A source answers get-source-mute and a sink get-sink-mute; one of
        /// the two always fails, so the second is the fallback of the first.
        /// Poll emits per LINE, so both are read here.
        Poll {
            id: probe
            interval: 400
            // No id means nothing to read: the command would still be non-empty
            // and Poll would still spawn `sh` for it, five times a second, to
            // run `true`. Park it instead.
            active: wpa.id >= 0
            command: ["sh", "-c",
                      wpa.id < 0 ? "true"
                      : "wpctl get-volume " + wpa.id
                        + " ; pactl get-source-mute " + wpa.node.name
                        + " 2>/dev/null || pactl get-sink-mute " + wpa.node.name
                        + " 2>/dev/null"]
            onResult: output => {
                const t = String(output)
                const m = t.match(/Volume:\s*([0-9.]+)/)
                if (m) wpa.absorbVolume(parseFloat(m[1]))
                wpa.absorbMuted(/Mute:\s*yes/.test(t))
            }
        }

        onVolumeChanged: if (wpa.applyingVolume) wpa.applyingVolume = false
                         else wpa.writeVolume(wpa.volume)
        onMutedChanged: if (wpa.applyingMuted) wpa.applyingMuted = false
                        else wpa.writeMute(wpa.muted)
    }

    /// The two devices that can be controlled: the active output and the active
    /// input. Only these carry a slider, so only these need a fallback — and
    /// `!n.audio` is part of the lookup, because a device that HAS a native
    /// interface is driven through it, and standing a poll (a `sh` every 400ms)
    /// up for a node this will never be asked about is pure waste.
    WpAudio {
        id: wpSink
        node: root.outputDevices.find(n => !n.audio
                                     && n === Pipewire.defaultAudioSink) || null
    }
    WpAudio {
        id: wpSource
        node: root.inputDevices.find(n => !n.audio
                                     && n === Pipewire.defaultAudioSource) || null
    }

    /// The object a device row should control: the node's own interface when it
    /// has one, the wpctl stand-in when it does not, null when there is nothing
    /// to control. This is the single point where the two paths are chosen.
    function audioFor(node, asInput) {
        if (!node) return null
        if (node.audio) return node.audio
        const fb = asInput ? wpSource : wpSink
        return fb.node === node ? fb : null
    }

    // ---------------- phone audio ----------------
    // A phone streaming over bluetooth is a PipeWire *sink* named bluez5.*: the
    // phone is the source, the PC is the A2DP receiver. So there is nothing to
    // pair here and nothing to install — pairing happens in the settings flyout,
    // and the moment the phone is connected its audio arrives as one of these
    // nodes. The toggle is therefore just "make this the default sink", which is
    // what sends the PC's sound out through the phone, and the un-toggle puts
    // back whatever was default before.
    function isPhoneAudio(node) {
        if (!node) return false
        // The name is the old test, kept because it costs nothing, but it is a
        // naming convention rather than an interface. The driver says what a
        // node really is in its own properties: anything the bluez5 driver
        // built carries `api.bluez5.*` and `device.api = bluez…`, whatever it
        // decided to call itself. That is the difference between a phone being
        // connected and this row saying "no phone connected".
        if (String(node.name || "").indexOf("bluez5") === 0) return true
        const p = node.properties || {}
        if (String(p["device.api"] || "").indexOf("bluez") === 0) return true
        return ["api.bluez5.address", "api.bluez5.device",
                "api.bluez5.media.sink", "api.bluez5.media.source",
                "api.bluez5.profile"].some(k => p[k] !== undefined)
    }
    readonly property var phoneSinks: Pipewire.nodes.values
        .filter(n => root.isPhoneAudio(n) && n.isSink && !n.isStream)
    readonly property var phoneSink: root.phoneSinks.length > 0
        ? root.phoneSinks[0] : null
    /// true when the phone is what you are hearing
    readonly property bool phoneAudioOn: root.phoneSink !== null
        && Pipewire.defaultAudioSink === root.phoneSink
    /// what to go back to when the toggle is switched off: the first non-phone
    /// output, which is the speakers in every setup where a phone has ever
    /// connected. Held so it is not recomputed the moment the phone is default.
    property int lastLocalSink: -1

    // Whether the radio is even on. Needed because "no bluez5 sink" has two
    // very different causes — the radio is off, or the radio is on and nothing
    // is paired to it — and the fix is different for each. A permanently
    // greyed-out switch cannot tell you which one it is.
    property bool btRadio: true
    Poll {
        command: ["bluetoothctl", "show"]
        // 10s: the radio is toggled in the settings flyout and the phone
        // connects on its own, so this row has to wake up by itself rather
        // than waiting for the flyout to be opened.
        interval: 10000
        onResult: output => {
            root.btRadio = /Powered:\s*yes/.test(String(output))
        }
    }

    /// Why the switch cannot be used right now, in one sentence. This is the
    /// tooltip, and it is ordered from the most fundamental cause down: no
    /// point telling someone to pair a phone when the radio is off.
    readonly property string phoneAudioWhy: {
        if (root.phoneSink !== null)
            return "Send this PC's sound out through your phone."
        if (!root.btRadio)
            return "Bluetooth is off. Turn it on in the quick menu first."
        return "No phone connected. Pair one in the quick menu, then press "
             + "play on the phone — it shows up here as soon as it streams."
    }
    readonly property bool phoneAudioReady: root.phoneSink !== null

    function togglePhoneAudio(on) {
        if (on) {
            // Remember the speakers before leaving them.
            if (Pipewire.defaultAudioSink !== root.phoneSink) {
                for (let i = 0; i < root.outputDevices.length; i++) {
                    const n = root.outputDevices[i]
                    if (!root.isPhoneAudio(n) && n !== root.phoneSink) {
                        root.lastLocalSink = i
                        break
                    }
                }
            }
            Pipewire.preferredDefaultAudioSink = root.phoneSink
        } else {
            const back = root.outputDevices[root.lastLocalSink]
            if (back !== undefined && back !== null) {
                Pipewire.preferredDefaultAudioSink = back
            } else {
                // No speaker remembered — pick any non-phone output.
                for (let i = 0; i < root.outputDevices.length; i++) {
                    if (!root.isPhoneAudio(root.outputDevices[i])) {
                        Pipewire.preferredDefaultAudioSink = root.outputDevices[i]
                        break
                    }
                }
            }
        }
    }

    function friendlyName(node) {
        // The phone's own name first: a bluez node is called
        // `bluez5.AA_BB_CC_DD_EE_FF_A2DP_SINK`, and the driver already knows
        // the thing on the other end is called "Pixel 8".
        return (node.properties["api.bluez5.device"]
                || node.properties["application.name"]
                || node.description || node.nickname || node.name || "Unknown")
    }

    function setDefault(node, asInput) {
        if (asInput) Pipewire.preferredDefaultAudioSource = node
        else Pipewire.preferredDefaultAudioSink = node
    }

    // ---------------- window / anchoring ----------------
    PwObjectTracker {
        objects: root.trackedNodes
    }
    // The phone sink is tracked on its own: it is in no other list (a paired
    // phone is a sink but not an app, and it is kept out of the output list so
    // the speakers do not shuffle around under the user when a phone
    // connects), and an untracked node's volume writes are dropped.
    PwObjectTracker {
        objects: root.phoneSinks
    }

    function toggleFor(item) {
        root.anchor.item = item
        root.anchor.edges = Edges.Bottom
        root.anchor.gravity = Edges.Bottom
        root.visible = !root.visible
    }

    // ---------------- overboost ----------------
    // PipeWire takes a volume above 1.0 — that is exactly what "volume over
    // 100%" means in pavucontrol — and these sliders hand the number straight to
    // it. It is off by default because a boosted stream clips on its loud parts,
    // so it has to be asked for rather than reached by accident.
    property bool overboost: false
    /// whether the ADVANCED drawer at the bottom of the panel is open
    property bool advanced: false
    /// slider ceiling: 150% with overboost on, the ordinary 100% without it.
    /// Switching it off does not pull anything already above 100% back down —
    /// it only stops the slider from going there.
    readonly property real maxVolume: root.overboost ? 1.5 : 1

    /// The on/off switch, same shape as the settings flyout's: a capsule track
    /// with a knob that slides, so the knob's side is the state and no
    /// "on"/"off" text is needed beside it.
    component Toggle: Item {
        id: sw
        property bool checked: false
        /// false = drawn dim, no pointer: a hand cursor over something that
        /// cannot be pressed is a small lie.
        property bool interactive: true
        property color accent: Tokyo.cyan
        signal toggled()
        implicitWidth: 34
        implicitHeight: 18

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
            width: 12; height: 12; radius: 6
            y: 3
            x: sw.checked ? parent.width - width - 3 : 3
            color: sw.checked ? sw.accent : Tokyo.dim
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: sw.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (sw.interactive) sw.toggled()
        }
    }

    // ---------------- volume slider + mute (shared) ----------------
    // One definition for every slider in this panel, so the device rows and
    // the app rows cannot drift apart. `audio` is a PwAudioNode — pass null
    // and the control simply draws nothing rather than throwing.
    component VolumeSlider: Controls.Slider {
        id: vs
        /// what this slider drives: a PwNodeAudioIface, a WpAudio, or null.
        /// Assigning `.volume` works for the native one; for WpAudio the
        /// assignment is what triggers its onVolumeChanged push, which is
        /// suppressed for a poll echo by its own `applying` flag — so both
        /// paths are the same line of code.
        property var audio
        height: 22
        from: 0
        to: root.maxVolume
        stepSize: 0.01
        value: vs.audio ? vs.audio.volume : 0
        onMoved: {
            if (vs.audio) vs.audio.volume = vs.value
        }

        background: Rectangle {
            y: vs.topPadding + vs.availableHeight / 2 - height / 2
            width: vs.availableWidth
            height: 4
            radius: 2
            color: Tokyo.bgHighlight
            Rectangle {
                width: vs.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: Tokyo.magenta
            }
        }
        handle: Rectangle {
            x: vs.leftPadding + vs.visualPosition * (vs.availableWidth - width)
            y: vs.topPadding + vs.availableHeight / 2 - height / 2
            width: 12
            height: 12
            radius: 6
            color: vs.pressed ? Tokyo.fg : Tokyo.pink
            border.color: Tokyo.bgDark
            border.width: 1
        }
    }

    /// The volume number, as a percentage. Extracted for the same reason as
    /// VolumeSlider and MuteGlyph: the device rows and the app rows would
    /// otherwise each carry their own copy and drift. Reaches past 100 when
    /// AMPLIFY is on, which is the point — that is what the slider is showing.
    component VolumePercent: Text {
        id: vp
        /// the PwAudioNode whose volume and mute state this reports; null
        /// renders nothing rather than throwing
        property var audio
        text: vp.audio ? Math.round(vp.audio.volume * 100) + "%" : ""
        // Recedes on mute, matching the app rows' long-standing behaviour —
        // the mute glyph beside it turns yellow and is what carries the state.
        color: vp.audio && vp.audio.muted ? Tokyo.bgHighlight : Tokyo.fg
        font { family: Tokyo.fontFamily; pixelSize: 12 }
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
    }

    /// The speaker/mic glyph, doubling as the mute switch. `audio` is null
    /// when there is nothing to control yet.
    component MuteGlyph: Item {
        id: mg
        /// the PwAudioNode whose muted flag this toggles
        property var audio
        /// true on an input device: a mute button drawn as a speaker is a small
        /// lie about which side of the pipe it controls, so inputs get the
        /// microphone glyphs (U+F130 / U+F131) instead.
        property bool isInput: false
        implicitWidth: 20
        implicitHeight: 18

        Text {
            anchors.centerIn: parent
            // \uF026 / \uF028 speaker off/on, \uF131 / \uF130 mic off/on.
            text: !mg.audio ? ""
                 : (mg.audio.muted ? (mg.isInput ? "" : "")
                                   : (mg.isInput ? "" : ""))
            color: mg.audio && mg.audio.muted ? Tokyo.yellow : Tokyo.fg
            font { family: Tokyo.fontFamily; pixelSize: 11 }
        }
        MouseArea {
            anchors.fill: parent
            enabled: !!mg.audio
            onClicked: if (mg.audio) mg.audio.muted = !mg.audio.muted
        }
    }

    Rectangle {
        id: box
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: content.implicitHeight + root.padV * 2
        color: Tokyo.bgDark
        radius: Tokyo.pillRadius
        border.color: Tokyo.bgHighlight
        border.width: 1

        Column {
            id: content
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: root.padH; rightMargin: root.padH; topMargin: root.padV
            }
            spacing: 2

            // ---------- output devices ----------
            Text {
                text: "OUTPUT DEVICES"
                font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                color: Tokyo.blue
                leftPadding: 4
                bottomPadding: 2
            }
            Rectangle {
                width: parent.width; height: 1
                color: Tokyo.bgHighlight
            }
            Repeater {
                model: root.outputDevices
                delegate: deviceRow
            }

            Item { height: 8 }

            // ---------- phone audio ----------
            // Always drawn, ready or not. A switch that only appears once it
            // works cannot be found, and the one time you want it is the time
            // you are looking for it — so the row is permanent, greyed out
            // when there is no phone, and hovering it says why. The switch
            // itself is the same shape as the settings flyout's, so the two
            // menus do not disagree about what "on" looks like.
            Column {
                width: parent.width
                spacing: 2

                Text {
                    text: "PHONE AUDIO"
                    font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                    color: root.phoneAudioReady ? Tokyo.blue : Tokyo.dim
                    leftPadding: 4
                    bottomPadding: 2
                }
                Rectangle {
                    width: parent.width; height: 1
                    color: root.phoneAudioReady ? Tokyo.bgHighlight
                                                : Qt.rgba(0.18, 0.20, 0.30, 0.5)
                }

                Rectangle {
                    id: phoneRow
                    width: parent.width
                    height: root.rowHeight
                    radius: 6
                    // No hover fill when the row is dead: the fill is the
                    // "this does something" signal, and this does not.
                    color: phoneHover.hovered && root.phoneAudioReady
                           ? Tokyo.bgHighlight : "transparent"

                    Row {
                        anchors {
                            left: parent.left; right: parent.right
                            leftMargin: 8; rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Text {
                            width: parent.width - 60
                            text: root.phoneSink
                                ? root.friendlyName(root.phoneSink)
                                : "No phone connected"
                            elide: Text.ElideRight
                            color: !root.phoneAudioReady ? Tokyo.dim
                                  : root.phoneAudioOn ? Tokyo.cyan : Tokyo.fg
                            font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                            verticalAlignment: Text.AlignVCenter
                        }
                        Toggle {
                            width: 34; height: 18
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.phoneAudioOn
                            interactive: root.phoneAudioReady
                            opacity: root.phoneAudioReady ? 1 : 0.4
                            onToggled: root.togglePhoneAudio(!root.phoneAudioOn)
                        }
                    }

                    MouseArea {
                        id: phoneHover
                        // Stops short of the switch's own hit area (8px margin
                        // + the 34px switch), so the row and the switch never
                        // both swallow one click.
                        anchors { left: parent.left; right: parent.right
                                  rightMargin: 42
                                  top: parent.top; bottom: parent.bottom }
                        hoverEnabled: true
                        onClicked: {
                            if (root.phoneAudioReady)
                                root.togglePhoneAudio(!root.phoneAudioOn)
                        }
                    }

                    // ---------- the tooltip ----------
                    // A panel of its own rather than another line in the column:
                    // an inline explanation would make the whole panel jump
                    // taller every time the pointer crossed the row, which is
                    // worse than the problem it explains. This floats over the
                    // rows below instead, and is only ever shown for a dead
                    // row — when the switch works, the label already says what
                    // it does.
                    Rectangle {
                        id: phoneTip
                        width: tipText.width + 20
                        height: tipText.height + 20
                        radius: Tokyo.pillRadius
                        color: Tokyo.bgDark
                        border.color: Tokyo.bgHighlight
                        border.width: 1
                        visible: opacity > 0.01
                        opacity: (!root.phoneAudioReady && phoneHover.hovered)
                                 ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: 130; easing.type: Easing.OutQuad }
                        }
                        anchors { left: parent.left; leftMargin: 2
                                  top: parent.bottom; topMargin: 2 }
                        z: 10
                        Text {
                            id: tipText
                            anchors { left: parent.left; right: parent.right
                                      top: parent.top; margins: 10 }
                            text: root.phoneAudioWhy
                            color: Tokyo.fg
                            wrapMode: Text.WordWrap
                            width: 236
                            font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize - 1 }
                        }
                    }
                }
            }

            Item { height: 8 }

            // ---------- input devices ----------
            Text {
                text: "INPUT DEVICES"
                font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                color: Tokyo.blue
                leftPadding: 4
                bottomPadding: 2
            }
            Rectangle {
                width: parent.width; height: 1
                color: Tokyo.bgHighlight
            }
            Repeater {
                model: root.inputDevices
                delegate: deviceRow
            }

            Item { height: 8 }

            // ---------- applications ----------
            Text {
                text: "APPLICATIONS"
                font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                color: Tokyo.blue
                leftPadding: 4
                bottomPadding: 2
            }
            Rectangle {
                width: parent.width; height: 1
                color: Tokyo.bgHighlight
            }
            Repeater {
                model: root.apps
                delegate: appRow
            }

            Item { height: 8 }
            Rectangle {
                width: parent.width; height: 1
                color: Tokyo.bgHighlight
            }

            // ---------- advanced ----------
            // The boost switch is folded away under this rather than sitting in
            // the panel: going past 100% distorts and clips, so it should be one
            // deliberate click instead of something in the way every time the
            // panel opens. The label stays lit when the panel is closed and
            // boosting is on — otherwise the setting would be invisible while
            // still in effect.
            Rectangle {
                id: advancedButton
                width: parent.width
                height: root.rowHeight
                radius: 6
                color: advancedHover.hovered ? Tokyo.bgHighlight : "transparent"

                Text {
                    anchors { left: parent.left; leftMargin: 8
                              verticalCenter: parent.verticalCenter }
                    text: "ADVANCED"
                    color: root.advanced || root.overboost ? Tokyo.blue : Tokyo.dim
                    font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 8
                              verticalCenter: parent.verticalCenter }
                    // chevron down = closed, and there is more below it
                    text: root.advanced ? "\uf077" : "\uf078"
                    color: root.advanced ? Tokyo.blue : Tokyo.dim
                    font { family: Tokyo.fontFamily; pixelSize: 10 }
                }
                MouseArea {
                    id: advancedHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.advanced = !root.advanced
                }
            }

            Column {
                width: parent.width
                visible: root.advanced
                // A Column counts hidden children, so the height has to go to 0
                // by hand or the flyout keeps a gap where the switch used to be.
                height: visible ? implicitHeight : 0

                Rectangle {
                    id: boostRow
                    width: parent.width
                    height: root.rowHeight
                    radius: 6
                    color: boostHover.hovered ? Tokyo.bgHighlight : "transparent"

                    Row {
                        anchors {
                            left: parent.left; right: parent.right
                            leftMargin: 8; rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        Text {
                            width: parent.width - 40
                            text: "Allow volume to go up to 150%"
                            elide: Text.ElideRight
                            color: root.overboost ? Tokyo.cyan : Tokyo.fg
                            font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                            verticalAlignment: Text.AlignVCenter
                        }
                        Toggle {
                            checked: root.overboost
                            onToggled: root.overboost = !root.overboost
                        }
                    }

                    MouseArea {
                        id: boostHover
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.overboost = !root.overboost
                    }
                }
            }
        }
    }

    // ---------------- device row (output + input) ----------------
    Component {
        id: deviceRow
        Rectangle {
            required property var modelData
            readonly property var node: modelData
            readonly property bool asInput: root.inputDevices.includes(modelData)
            readonly property bool isDefault: node && (asInput
                ? Pipewire.defaultAudioSource === node
                : Pipewire.defaultAudioSink === node)

            id: row
            width: parent.width
            height: root.rowHeight
            radius: 6
            // `|| sld.hovered` is not redundancy: the row's MouseArea stops at
            // the slider, and Qt only propagates hover to ancestors, never to
            // siblings — so hovering the slider would blank the row behind it.
            color: hover.hovered || (row.controllable && sld.hovered)
                   ? Tokyo.bgHighlight : "transparent"

            // Only the device you are actually listening to / talking into gets
            // a volume control. Every other row is just a way to *choose* that
            // device, and a slider on a device nothing is routed through is a
            // control with no effect. The widths collapse to 0 by hand rather
            // than relying on `visible: false`, which a Row still lays out.
            readonly property bool controllable: row.isDefault
                    && !!root.audioFor(row.node, row.asInput)

            Row {
                anchors {
                    left: parent.left; right: parent.right
                    leftMargin: 8; rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 6

                Text {
                    // 26 = the 20px check + its 6px gap. The control column is
                    // percent 40 + mute 20 + slider 110 plus the three gaps
                    // between them and the check's — 214 — i.e. everything that
                    // is not the name.
                    width: parent.width - (row.controllable ? 214 : 26)
                    text: root.friendlyName(row.node)
                    elide: Text.ElideRight
                    color: row.isDefault ? Tokyo.blue : Tokyo.fg
                    font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                    verticalAlignment: Text.AlignVCenter
                }
                VolumePercent {
                    width: row.controllable ? 40 : 0
                    audio: row.controllable ? root.audioFor(row.node, row.asInput) : null
                }
                MuteGlyph {
                    width: row.controllable ? 20 : 0
                    audio: root.audioFor(row.node, row.asInput)
                    isInput: row.asInput
                }
                VolumeSlider {
                    id: sld
                    width: row.controllable ? 110 : 0
                    audio: root.audioFor(row.node, row.asInput)
                }
                Text {
                    width: 20
                    text: "\uf00c" // check
                    color: row.isDefault ? Tokyo.green : "transparent"
                    font { family: Tokyo.fontFamily; pixelSize: 12 }
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
            }

            MouseArea {
                id: hover
                // Stops short of the volume control, or the row would eat every
                // drag and press on the one slider that is supposed to do
                // something. On a row with no control it still spans the width.
                // rightMargin, not `right: muteArea.left`: the glyph is a
                // grandchild through the Row, and QML refuses to anchor to
                // anything that is not a parent or a sibling. 206 = the Row's
                // own 8px right margin + mute 20 + gap 6 + slider 110 + gap 6
                // + percent 40 + gap 6, i.e. everything from the percentage's
                // left edge to the row's right edge. The check mark lives inside
                // that span and stays non-clickable, which is right: it is a
                // marker on a row already switched on.
                anchors {
                    left: parent.left; top: parent.top; bottom: parent.bottom
                    right: parent.right
                    rightMargin: row.controllable ? 206 : 0
                }
                hoverEnabled: true
                onClicked: root.setDefault(row.node, row.asInput)
            }
        }
    }

    // ---------------- application row ----------------
    Component {
        id: appRow
        Rectangle {
            required property var modelData
            readonly property var node: modelData

            id: row
            width: parent.width
            height: root.rowHeight
            radius: 6
            color: "transparent"

            Row {
                anchors {
                    left: parent.left; right: parent.right
                    leftMargin: 8; rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 6

                Text {
                    width: 118
                    text: root.friendlyName(row.node)
                    elide: Text.ElideRight
                    color: Tokyo.fg
                    font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                    verticalAlignment: Text.AlignVCenter
                }
                VolumePercent {
                    width: 40
                    audio: row.node ? row.node.audio : null
                }
                MuteGlyph {
                    width: 20
                    audio: row.node ? row.node.audio : null
                }

                // 150% with AMPLIFY on, the usual 100% ceiling without it.
                VolumeSlider {
                    width: parent.width - 202
                    audio: row.node ? row.node.audio : null
                }
            }
        }
    }
}