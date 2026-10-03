// Bar.qml — one PanelWindow per screen, replicating the waybar bar.
//
//   window#waybar : height 34, bg rgba(30,32,48,0.9) — rendered transparent
//                   here (no background / border band): the pills float over
//                   the wallpaper, everything between them is see-through.
//   layout        : left  = workspaces | audio | tray
//                   center= clock (time over date, click → ClockFlyout)
//                   right = network | sys (gpu+cpu+ram) | updates
//   module pills  : radius 8, margin 4px 3px (26px tall, 3px from each edge)
//   pill gap      : 12px = 6px bar spacing + 3px margins each side (GTK semantics)
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

Variants {
    id: barRoot
    property var networkMonitor: null
    /// shared Brightness service (shell.qml) — DDC/CI per-monitor luminance
    property var brightness: null
    /// shared NotificationStore (shell.qml) — the daemon + the centre's history
    property var notifications: null

    model: Quickshell.screens

    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData

        anchors { top: true; left: true; right: true }
        implicitHeight: Tokyo.barHeight
        exclusiveZone: Tokyo.barHeight
        color: "transparent"

        // ---------- bar chrome ----------
        // No background: the bar strip is fully transparent so the wallpaper
        // shows through between the floating pills. The old underlay (rounded
        // rect + 2px bottom border band, waybar's rgba(30,32,48,0.9) bg) is
        // dropped; Tokyo.barBg/barRadius/barBorderBottom stay defined in
        // Tokyo.qml as the waybar style reference.

        // ---------- shared tooltip popup ----------
        Tooltip { id: tip }

        // ---------- audio flyout ----------
        // Clicking the audio pill opens this popup: per-app volume + device
        // selection. Grab-focus popups (xdg_popup) auto-dismiss on outside click.
        AudioFlyout { id: audioFlyout }

        // ---------- brightness flyout ----------
        // Right/middle-clicking a workspace pill opens this: a DDC/CI luminance
        // slider for the monitor behind that bar. One per window, so it always
        // opens on the screen the gesture happened on.
        BrightnessFlyout {
            id: brightnessFlyout
            service: barRoot.brightness
        }

        // ---------- clock flyout ----------
        // Left-clicking the clock pill opens this: the timers / clock pair
        // (clock = time+zones, date, uptime). One per window, anchored to the
        // clicked pill.
        ClockFlyout { id: clockFlyout }

        // ---------- sys flyout ----------
        // Clicking the combined gpu/cpu/ram pill opens this: one tachometer
        // per stat. One per window, so it opens on the screen the click
        // happened on.
        SysFlyout { id: sysFlyout }

        // ---------- settings flyout ----------
        // The combined net+power pill's menu: wi-fi and bluetooth as quick
        // tiles with their device lists, the connection stats behind ADVANCED,
        // and the three power actions. One per window, so it opens on the
        // screen the click happened on.
        SettingsFlyout { id: settingsFlyout }

        // ---------- notification centre + toasts ----------
        // The centre is one per window, anchored to the clicked bell. The list
        // it shows is shared (shell.qml's NotificationStore), so every monitor
        // shows the same history.
        NotificationCenter {
            id: notificationCenter
            store: barRoot.notifications
        }

        // The toasts have no pill to hang off, and Quickshell 0.3.1's
        // PopupWindow can only place itself against an anchor item, so this is
        // the marker they aim at: zero-sized, in the bar's top-right corner,
        // clear of the bar itself. Its own size is never drawn.
        Item {
            id: toastAnchor
            anchors {
                top: parent.top; right: parent.right
                topMargin: Tokyo.barHeight + 8; rightMargin: Tokyo.edgeGap + 3
            }
            width: 0
            height: 0
        }

        // One per window so a toast lands on the monitor you are looking at.
        // Only the one on the focused monitor accepts anything — see Toast.qml.
        Toast {
            id: toast
            store: barRoot.notifications
            anchorItem: toastAnchor
        }

        // ---------- left ----------
        RowLayout {
            id: leftBox
            // leftMargin = hyprland gaps_out (6): the first pill sits exactly as
            // far from the monitor border as a tiled window's edge. Pills are
            // shifted down (barShiftV) to sit midway between the monitor's top
            // edge and the top border of the first tiled window.
            anchors { left: parent.left; leftMargin: Tokyo.edgeGap; verticalCenter: parent.verticalCenter; verticalCenterOffset: Tokyo.barShiftV }
            spacing: Tokyo.pillGap

            Workspaces {
                screen: win.screen
                tooltipHost: tip
                flyoutHost: brightnessFlyout
                Layout.alignment: Qt.AlignVCenter
            }
            // Audio lives on the left: volume is a control, not a readout, and
            // the right end of the bar is now all monitor-and-link state.
            Audio {
                tooltipHost: tip
                flyoutHost: audioFlyout
                Layout.alignment: Qt.AlignVCenter
            }
            Tray {
                tooltipHost: tip
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ---------- center ----------
        RowLayout {
            id: centerBox
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: Tokyo.barShiftV }
            spacing: Tokyo.pillGap

            // One pill for the whole centre of the bar: time stacked on the
            // date, and the four things that used to sit beside it (date, time,
            // uptime, timer countdown) moved into the flyout it opens.
            Clock {
                id: clockPill
                flyoutHost: clockFlyout
                Layout.alignment: Qt.AlignVCenter
                // Not hidden while the flyout is open, and not faded. The panel
                // hangs *under* this pill rather than over it — the flyout's
                // shape starts on this rect and walks its top edge down past the
                // pill's bottom edge as it opens — so the two are on different
                // pixels by the end of the morph and there is nothing to hide.
                //
                // Hiding it was never more than a workaround for the panel
                // landing on top of it. It was worth two bugs to stop doing:
                // `visible: false` is skipped by the layout that positions the
                // pill, and the popup reads this pill's `magnet` at the instant
                // it is shown, so the anchor was being read off geometry that was
                // mid-flight and the panel landed up to half a pill off. Opacity
                // 0 fixed that one and left a second: the widget disappeared
                // whenever its panel was open, which is a poor thing for a widget
                // to do when the panel is meant to look like it belongs to it.
                //
                // It stays lit instead, which it manages through `hoveredExtra` —
                // the flyout's surface covers this pill, so this MouseArea gets
                // nothing while the panel is up.
            }
        }

        // ---------- right ----------
        RowLayout {
            id: rightBox
            // rightMargin = hyprland gaps_out (6): the last pill (updates / cachy)
            // ends exactly gaps_out from the monitor border, mirroring windows.
            // (Was 0 to touch the border; now matches the window gap setting.)
            anchors { right: parent.right; rightMargin: Tokyo.edgeGap; verticalCenter: parent.verticalCenter; verticalCenterOffset: Tokyo.barShiftV }
            spacing: Tokyo.pillGap

            Sys {
                tooltipHost: tip
                flyoutHost: sysFlyout
                Layout.alignment: Qt.AlignVCenter
            }
            Updates {
                tooltipHost: tip
                Layout.alignment: Qt.AlignVCenter
            }
            // Beside cachy-updates on purpose: "there are updates" and
            // "something wants you" are both things that arrived while you were
            // looking at something else, and reading them off two adjacent
            // pills is one glance rather than two.
            NotificationBell {
                store: barRoot.notifications
                flyoutHost: notificationCenter
                tooltipHost: tip
                Layout.alignment: Qt.AlignVCenter
            }
            // The net icons and the power glyph are one pill now: the links the
            // machine is actually on sit next to the switch that changes them.
            // Last on the right, so the power glyph is against the screen edge.
            Settings {
                networkMonitor: barRoot.networkMonitor
                flyoutHost: settingsFlyout
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}







