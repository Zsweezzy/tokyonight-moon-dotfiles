pragma Singleton
// Focus.qml — the monitor that has keyboard focus right now.
//
// Quickshell 0.3.1 declares Hyprland.focusedMonitor with a
// `focusedMonitorChanged` notifier that HyprlandIpc never emits, so a binding
// on it evaluates exactly once and then holds that value forever. Measured: it
// reads whichever monitor was focused when the config last loaded — DP-1 when
// this instance started at 11:21, DP-2 after a later reload — and never moves
// again. So it is not "the focused monitor", it is "the focused monitor as of
// the last reload", and every consumer that treats it as live is silently
// wrong. On the toast path that frozen name is what decides which monitor shows
// a notification, so a reload while a different monitor is focused leaves every
// Toast disagreeing with the focus and no toast is shown anywhere at all.
//
// Hyprland emits `focusedmon` on the socket2 event stream for every focus
// change, and that is the only live signal available here, so it is what this
// tracks. The frozen property is kept as the seed so there is a usable name
// before the first focus change arrives.
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    /// The focused monitor's name, spelled the way Hyprland spells it: "DP-1".
    /// Referenced unqualified — `Focus.monitorName` — from anywhere in the
    /// config, which is the same shape as Tokyo.qml.
    property string monitorName: Hyprland.focusedMonitor !== null
        ? Hyprland.focusedMonitor.name
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "focusedmon") return
            root.monitorName = event.data.split(",")[0]
        }
    }
}
