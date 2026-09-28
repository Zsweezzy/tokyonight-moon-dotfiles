// shell.qml — Tokyo Night Moon bar for Quickshell.
// Launch with:  quickshell -c tokyonight
//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    // One collector is shared by every bar window, so multiple monitors do
    // not race the same interface-rate state or duplicate external probes.
    NetworkMonitor { id: networkMonitor }

    // Likewise for brightness: the Hyprland→ddcutil display map is built once
    // here instead of per bar window (a `ddcutil detect` costs seconds).
    Brightness { id: brightness }

    // There is no second timer surface. The standalone `TimerWindow.qml` and the
    // `timer` IPC target that drove it (and the SUPER + SHIFT + T bind in
    // hyprland.lua) are gone; the clock flyout's TIMERS pane is the only host of
    // `TimerPanel` now, so the list it can show is the list there is.

    Bar {
        networkMonitor: networkMonitor
        brightness: brightness
    }
}