// AudioFlyout.qml — click flyout for the audio pill.
//
// Sections:
//   Output devices   click a row → Pipewire.preferredDefaultAudioSink
//   Input devices    click a row → Pipewire.preferredDefaultAudioSource
//   Applications     per-playback-app volume slider + mute toggle
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

    implicitWidth: 360
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
    function inputDevicesList() {
        return Pipewire.nodes.values.filter(n => {
            if (!n || !n.audio || n.isStream) return false
            if (!n.isSink) return true
            return n === Pipewire.defaultAudioSource
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

    function friendlyName(node) {
        return (node.properties["application.name"]
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

    function toggleFor(item) {
        root.anchor.item = item
        root.anchor.edges = Edges.Bottom
        root.anchor.gravity = Edges.Bottom
        root.visible = !root.visible
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
            color: hover.hovered ? Tokyo.bgHighlight : "transparent"

            Row {
                anchors {
                    left: parent.left; right: parent.right
                    leftMargin: 8; rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                spacing: 6

                Text {
                    width: parent.width - 26
                    text: root.friendlyName(row.node)
                    elide: Text.ElideRight
                    color: row.isDefault ? Tokyo.blue : Tokyo.fg
                    font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                    verticalAlignment: Text.AlignVCenter
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
                anchors.fill: parent
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
                Text {
                    width: 40
                    text: Math.round(row.node.audio.volume * 100) + "%"
                    color: row.node.audio.muted ? Tokyo.bgHighlight : Tokyo.fg
                    font { family: Tokyo.fontFamily; pixelSize: 12 }
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                }
                Text {
                    width: 20
                    text: row.node.audio.muted ? "\uf026" : "\uf028" // volume-off / volume-up
                    color: row.node.audio.muted ? Tokyo.yellow : Tokyo.fg
                    font { family: Tokyo.fontFamily; pixelSize: 11 }
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: row.node.audio.muted = !row.node.audio.muted
                    }
                }

                Controls.Slider {
                    id: sld
                    height: 22
                    width: parent.width - 202
                    from: 0
                    to: 1
                    stepSize: 0.01
                    value: row.node.audio ? row.node.audio.volume : 0
                    onMoved: {
                        if (row.node.audio) row.node.audio.volume = sld.value
                    }

                    background: Rectangle {
                        y: sld.topPadding + sld.availableHeight / 2 - height / 2
                        width: sld.availableWidth
                        height: 4
                        radius: 2
                        color: Tokyo.bgHighlight
                        Rectangle {
                            width: sld.visualPosition * parent.width
                            height: parent.height
                            radius: parent.radius
                            color: Tokyo.magenta
                        }
                    }
                    handle: Rectangle {
                        x: sld.leftPadding + sld.visualPosition * (sld.availableWidth - width)
                        y: sld.topPadding + sld.availableHeight / 2 - height / 2
                        width: 12
                        height: 12
                        radius: 6
                        color: sld.pressed ? Tokyo.fg : Tokyo.pink
                        border.color: Tokyo.bgDark
                        border.width: 1
                    }
                }
            }
        }
    }
}