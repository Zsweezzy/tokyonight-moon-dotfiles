// BrightnessFlyout.qml — click flyout for the workspace pills.
//
// Reached by right- or middle-clicking any workspace pill: it shows a slider
// for the DDC/CI luminance (VCP 0x10) of the monitor that pill belongs to.
// Left-click is left alone — it still switches workspace — so the bar gains a
// brightness control without losing its original job.
//
// Visual language is AudioFlyout's: dark rounded panel, 1 px bgHighlight
// border, small uppercase blue section header, and a transparent strip on top
// (gap) so the pill that opened it stays visible. `grabFocus` dismisses the
// popup on any outside click while leaving drags on the slider alone.
//
// Brightness comes from the shared Brightness service (shell.qml), which
// caches the ddcutil display map and debounces the writes, so the slider here
// only has to render a value and forward intent.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import Quickshell

PopupWindow {
    id: root

    visible: false
    grabFocus: true
    color: "transparent"

    /// shared Brightness service (shell.qml) — may be null in previews
    property var service: null

    /// Hyprland monitor name of the pill that opened this ("DP-1", …)
    property string monitorName: ""
    /// ready once the map knows whether this monitor has DDC/CI at all
    readonly property bool supported: service !== null
        && service.ddcFor(monitorName) >= 0

    readonly property int level: service ? service.level(monitorName, 0) : 0
    readonly property int maxLevel: service ? service.max(monitorName, 100) : 100
    /// nothing read yet — the first ddcutil read takes ~0.4 s
    readonly property bool known: service
        && service.levels[monitorName] !== undefined

    readonly property real gap: 6      // transparent strip, like Tooltip.qml
    readonly property real padH: 16
    readonly property real padV: 12

    implicitWidth: 300
    implicitHeight: box.height + root.gap

    // ---------------- window / anchoring ----------------

    /// Open under `anchorItem` for `name`, or close if that is already the
    /// monitor currently shown (mirrors AudioFlyout.toggleFor).
    function toggleFor(anchorItem, name) {
        if (root.visible && root.monitorName === name) {
            root.visible = false
            return
        }
        root.monitorName = name
        root.anchor.item = anchorItem
        root.anchor.edges = Edges.Bottom
        root.anchor.gravity = Edges.Bottom
        root.visible = true
        // Read the real level in the background; the slider shows the cached
        // one meanwhile so the popup never opens empty.
        if (root.service) {
            root.service.ensureMap()
            root.service.read(name)
        }
    }

    function nudge(delta) {
        if (root.service && root.supported) root.service.nudge(root.monitorName, delta)
    }

    // ---------------- panel ----------------

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
            spacing: 8

            // ---------- header ----------
            Text {
                text: "MONITOR BRIGHTNESS"
                font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                color: Tokyo.blue
                leftPadding: 4
                bottomPadding: 2
            }
            Rectangle {
                width: parent.width; height: 1
                color: Tokyo.bgHighlight
            }

            // ---------- monitor + readout ----------
            RowLayout {
                width: parent.width
                spacing: 8

                Text {
                    text: root.monitorName
                    color: root.supported ? Tokyo.fg : Tokyo.bgHighlight
                    font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Text {
                    // sun glyph, so the control reads as brightness at a glance
                    text: "\uf185"
                    color: root.supported ? Tokyo.yellow : Tokyo.bgHighlight
                    font { family: Tokyo.fontFamily; pixelSize: 12 }
                    visible: root.supported
                }
                Text {
                    text: !root.supported ? "no DDC/CI"
                        : (root.known ? root.level + "%" : "…")
                    color: !root.supported ? Tokyo.yellow : Tokyo.fg
                    font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize; bold: root.known }
                }
            }

            // ---------- slider ----------
            Controls.Slider {
                id: sld
                width: parent.width
                height: 22
                enabled: root.supported
                from: 0
                to: root.maxLevel
                stepSize: 1
                // The service writes the level back the instant the slider
                // moves, so a plain binding tracks the drag without the
                // pointer and the handle fighting each other. A monitor that
                // refuses a value pulls the handle back on the confirm read.
                value: root.level
                onMoved: if (root.service) root.service.request(root.monitorName, sld.value)

                background: Rectangle {
                    x: sld.leftPadding + sld.availableWidth / 2 - width / 2
                    y: sld.topPadding + sld.availableHeight / 2 - height / 2
                    width: sld.availableWidth
                    height: 6
                    radius: 3
                    color: Tokyo.bgHighlight
                    Rectangle {
                        width: sld.visualPosition * parent.width
                        height: parent.height
                        radius: parent.radius
                        color: Tokyo.yellow
                    }
                }
                handle: Rectangle {
                    x: sld.leftPadding + sld.visualPosition * (sld.availableWidth - width)
                    y: sld.topPadding + sld.availableHeight / 2 - height / 2
                    width: 14
                    height: 14
                    radius: 7
                    color: sld.pressed ? Tokyo.fg : Tokyo.yellow
                    border.color: Tokyo.bgDark
                    border.width: 1
                }
            }

            // ---------- hint ----------
            Text {
                width: parent.width
                text: root.supported
                    ? "scroll the pill to adjust · left-click still switches workspace"
                    : "this monitor does not answer DDC/CI luminance (VCP 0x10)"
                color: Tokyo.trayGlyph
                font { family: Tokyo.fontFamily; pixelSize: 10 }
                wrapMode: Text.WordWrap
            }
        }
    }
}
