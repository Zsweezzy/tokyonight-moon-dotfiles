// Audio.qml — waybar pulseaudio (PipeWire via the native Quickshell service).
//
//   format          {icon} {volume}%
//   format-muted    \uf026 {volume}%
//   format-icons    [\uf027, \uf027, \uf028]   (threshold at 67%)
//   click           : toggle the AudioFlyout (per-app volume, in/out devices)
//   right/middle    : audio-popup.py (legacy)
//   scroll          : volume ±5%   (waybar's built-in scroll behavior)
//   tooltip         : "{desc} {volume}%" (hidden while the flyout is open)
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Module {
    id: root

    fg: Tokyo.magenta

    // Bind the default sink so its audio properties (volume/muted) are valid.
    PwObjectTracker {
        id: tracker
        objects: [Pipewire.defaultAudioSink]
    }

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() {
            tracker.objects = [Pipewire.defaultAudioSink]
        }
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property real volume: sink ? sink.audio.volume : 0
    readonly property bool muted: sink ? sink.audio.muted : false
    readonly property int pct: Math.round(volume * 100)

    /// popup flyout to toggle (AudioFlyout, created in Bar.qml)
    property var flyoutHost: null
    /// true while the flyout popup is visible (used to mute the hover tooltip)
    property bool flyoutOpen: false

    text: root.muted
          ? "\uf026 " + root.pct + "%"
          : (root.pct >= 67 ? "\uf028 " : "\uf027 ") + root.pct + "%"

    tooltip: root.flyoutOpen || !sink ? "" : `${sink.description} ${root.pct}%`

    Connections {
        target: root.flyoutHost
        function onVisibleChanged() {
            root.flyoutOpen = root.flyoutHost.visible
        }
    }

    onClicked: button => {
        if (button === Qt.LeftButton) {
            if (root.flyoutHost) root.flyoutHost.toggleFor(root)
            else Quickshell.execDetached([Tokyo.scriptDir + "/audio-popup.py"])
        } else {
            Quickshell.execDetached([Tokyo.scriptDir + "/audio-popup.py"])
        }
    }

    onWheelTick: dy => {
        if (!sink) return
        const vol = Math.min(1, Math.max(0, root.volume + (dy > 0 ? 0.05 : -0.05)))
        sink.audio.volume = vol
    }
}