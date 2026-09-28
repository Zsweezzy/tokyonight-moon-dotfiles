// Bar.qml — one PanelWindow per screen, replicating the waybar bar.
//
//   window#waybar : height 34, bg rgba(30,32,48,0.9) — rendered transparent
//                   here (no background / border band): the pills float over
//                   the wallpaper, everything between them is see-through.
//   layout        : left  = workspaces | cava | tray
//                   center= clock (time over date, click → ClockFlyout)
//                   right = wifi | ethernet | audio | gpu | cpu | ram | updates
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
            Cava {
                tooltipHost: tip
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

            Wifi {
                tooltipHost: tip
                networkMonitor: barRoot.networkMonitor
                Layout.alignment: Qt.AlignVCenter
            }
            Ethernet {
                tooltipHost: tip
                networkMonitor: barRoot.networkMonitor
                Layout.alignment: Qt.AlignVCenter
            }
            Audio {
                tooltipHost: tip
                flyoutHost: audioFlyout
                Layout.alignment: Qt.AlignVCenter
            }
            Gpu {
                tooltipHost: tip
                Layout.alignment: Qt.AlignVCenter
            }
            Cpu {
                tooltipHost: tip
                Layout.alignment: Qt.AlignVCenter
            }
            Mem {
                tooltipHost: tip
                Layout.alignment: Qt.AlignVCenter
            }
            Updates {
                tooltipHost: tip
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}







