// Workspaces.qml — per-monitor virtual desktop pills.
//
// Matches waybar hyprland/workspaces:
//   format "{id}", sort-by-number, on-click "activate"
//   margin-left: 6px on the container
//   each button: padding 0 10px, margin 4px 3px, radius 8
//     default : bg rgba(47,51,77,0.9)  fg #c8d3f5
//     hover   : bg #2f334d solid        fg #86e1fc   (transition 0.15s)
//     active  : bg rgba(130,170,255,0.2) fg #82aaff + 2px bottom border #82aaff
// For an active+hover button, the `.active` rule wins (it comes after
// `:hover` in the stylesheet) — replicated below.
//
// Gestures (added on top of the waybar behaviour, left-click untouched):
//   left click   switch to that workspace (unchanged)
//   right/middle click  open the brightness flyout for THIS bar's monitor
//   scroll       nudge that monitor's brightness by 5
import QtQuick
import Quickshell
import Quickshell.Hyprland

Item {
    id: root

    required property ShellScreen screen
    property var tooltipHost: null
    /// BrightnessFlyout for this bar's monitor (created in Bar.qml)
    property var flyoutHost: null

    implicitHeight: Tokyo.pillHeight
    // Width = the pill row (its own left margin is 0 — the bar's edgeGap takes
    // over the spacer role, so the total border→first-pill distance is exactly
    // Tokyo.edgeGap). This also removes the old wsPad*2 dead space: the next
    // module (the tray) sits one normal pill gap (12px) from the counter.
    implicitWidth: wsRow.implicitWidth + wsRow.rowLeftMargin

    // The HyprlandMonitor that corresponds to this bar's screen
    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property string monitorName: root.monitor ? root.monitor.name : ""
    // Special workspaces (special:tray, special:magic) are hidden Hyprland
    // scratchpads reached by keybind, not part of normal desktop navigation.
    // They carry negative numeric IDs (special:tray is -98 here), so letting
    // them through rendered a meaningless "-98" pill in the bar. Mirrors the
    // exclusion OpenApps.qml already applies to special:tray windows.
    readonly property var workspaces: root.monitor !== null
        ? Hyprland.workspaces.values.filter(ws =>
            ws.monitor !== null
            && (ws.monitor === root.monitor || ws.monitor.name === root.monitor.name)
            && !String(ws.name).startsWith("special:"))
        : []

    Row {
        id: wsRow
        // waybar's #workspaces margin-left was 6px; now 0 because Bar's
        // edgeGap already provides the exact border spacing.
        readonly property real rowLeftMargin: 0
        anchors { left: parent.left; leftMargin: rowLeftMargin; top: parent.top; bottom: parent.bottom }
        spacing: Tokyo.moduleMarginH * 2        // 3px + 3px button margins

        Repeater {
            model: root.workspaces

            delegate: Rectangle {
                required property var modelData
                readonly property var ws: modelData

                id: pill
                height: parent.height
                width: Math.max(pillLabel.implicitWidth + Tokyo.wsPad * 2, 36)   // waybar button min-width 36px
                radius: Tokyo.pillRadius
                clip: true                      // bottom underline follows the radius

                // waybar marks `.active` on the focused workspace's button only
                readonly property bool globallyActive: ws.active
                    && Hyprland.focusedMonitor !== null
                    && ws.monitor !== null
                    && ws.monitor.name === Hyprland.focusedMonitor.name

                color: globallyActive ? Tokyo.activeTint : (pill.hovered ? Tokyo.bgHighlight : Tokyo.pillBg)
                Behavior on color {
                    ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
                }

                property bool hovered: false

                Text {
                    id: pillLabel
                    anchors.centerIn: parent
                    text: pill.ws.id
                    color: globallyActive ? Tokyo.blue : (pill.hovered ? Tokyo.cyan : Tokyo.fg)
                    font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                    Behavior on color {
                        ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
                    }
                }

                // active underline: border-bottom 2px solid #82aaff
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 2
                    color: Tokyo.blue
                    visible: globallyActive
                    // clamped, not 2: at this height a radius of 2 is twice half
                    // the bar, which draws a lozenge rather than an underline
                    radius: height / 2
                }

                MouseArea {
                    id: pillMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // Right/middle are accepted explicitly; a MouseArea only
                    // reports the buttons listed here.
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onClicked: m => {
                        // Left keeps waybar's original job.
                        if (m.button === Qt.LeftButton) {
                            pill.ws.activate()   // handles lua-mode dispatch automatically
                        } else if (root.flyoutHost && root.monitorName !== "") {
                            root.flyoutHost.toggleFor(pill, root.monitorName)
                        }
                    }
                    onWheel: w => {
                        if (!root.flyoutHost || root.monitorName === "") return
                        root.flyoutHost.nudge(w.angleDelta.y > 0 ? 5 : -5)
                    }
                    onEntered: pill.hovered = true
                    onExited: pill.hovered = false
                }
            }
        }
    }
}