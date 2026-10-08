// Clock.qml — the clock pill as the bar draws it: Module's chrome with a
// ClockFace in the middle.
//
// The pill is the bar's only clock. Left-clicking it opens ClockFlyout, a popup
// that is anchored to the bar rather than to this widget — it opens centred at
// the top of the screen and hangs clear of the pill — so nothing here has to
// move, re-measure or hide when it does. The pill stays lit and on screen the
// whole time, which is why it can read as the thing that owns the clock even
// while the panel is up.
//
// Left-click opens the flyout, so the pill takes `hoverStyle` (it looks
// clickable). Right/middle-click deliberately does nothing: a dead gesture that
// highlights the pill just reads as a bug.
import QtQuick

Module {
    id: root

    fg: Tokyo.fg
    hoverStyle: true                       // it opens a flyout
    /// shared ClockFlyout (Bar.qml) — may be null in previews
    property var flyoutHost: null

    // Module's own label stays empty; the face draws the content.
    text: ""

    // The widget's clock. Owned here rather than by the face, and read by the
    // flyout as well (`ClockFlyout.clock`), so the pill's seconds and the
    // panel's seconds are the same Date rather than two Timers started at two
    // instants and free to sit a second apart against the wall clock.
    property var now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    implicitHeight: Tokyo.pillHeight
    // From the face's metrics rather than Module's label, with Module's hPad so
    // a caller can still widen the padding without the content going off-centre.
    // Sized off `timeWorst`, so the width is a constant and the pill never
    // resizes on the second — see `contentW` in ClockFace.qml.
    implicitWidth: face.contentW + hPad * 2

    ClockFace {
        id: face
        anchors.fill: parent
        // `hovered`, not `lit`: nothing borrows this pill's hover state any more.
        // The flyout is a separate surface on the far side of the screen, so it
        // never covers the pill and the bar's MouseArea keeps hearing the
        // pointer for as long as it is really there.
        hovered: root.hovered
        now: root.now
    }

    onClicked: button => {
        if (button === Qt.LeftButton && root.flyoutHost) root.flyoutHost.toggleFor(root)
    }
}