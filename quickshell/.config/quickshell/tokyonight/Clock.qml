// Clock.qml — the clock pill as the bar draws it: Module's chrome with a
// ClockFace in the middle.
//
// This is the *closed* end of the flyout's morph, and the only end that stays
// on screen. Left-clicking the pill hands its rect to ClockFlyout, whose shape
// starts as a copy of this rect and grows out from under it; the pill itself
// never leaves. The face lives in its own file because the flyout draws the
// same face for the first part of the morph, before the shape's top edge has
// cleared it — two copies of this block would be two copies of the font, and
// the copy that got it wrong would be the one on screen.
//
// The pill shows the time over the date, and becomes a clock glyph while the
// flyout is open. The glyph is not a different widget: the same face, cross-faded
// by `glyphMix`, which this pill reads off the flyout and the flyout's own copy
// reads off itself — one number, so the two copies on screen during the morph
// cannot disagree. The readings stay on screen because a bar with no clock on it
// is a bar you have to click to know what time it is, and the clock was the
// whole reason the widget was there.
//
// Left-click opens the flyout, so the pill takes `hoverStyle` (it looks
// clickable). Right/middle-click deliberately does nothing: a dead gesture that
// highlights the pill just reads as a bug.
import QtQuick

Module {
    id: root

    fg: Tokyo.fg
    hoverStyle: true                       // it opens a flyout
    interactive: true
    /// shared ClockFlyout (Bar.qml) — may be null in previews
    property var flyoutHost: null

    // Module's own label stays empty; the face draws the content.
    text: ""

    // The widget's clock. Owned here rather than by the face, because during the
    // morph there are two faces on screen and the flyout's has to read the very
    // same Date — a second Timer starts at its own instant, and the seconds digit
    // of a cross-fading time reading is the last place a one-second disagreement
    // would be visible.
    property var now: new Date()
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }

    // Lit for as long as the flyout is up. A binding, not a push: the flyout's
    // surface covers this pill, so the bar's MouseArea hears nothing while the
    // panel is open and `hovered` goes false on the exact frame the panel
    // appears. `pillLit` is the flyout's own idea of "the pointer is on the
    // pill", which it keeps latched (`hoverCarry`) because it can no longer ask
    // this MouseArea.
    hoveredExtra: root.flyoutHost !== null && root.flyoutHost.pillLit

    implicitHeight: Tokyo.pillHeight
    // From the face's metrics rather than Module's label, with Module's hPad so
    // a caller can still widen the padding without the content going off-centre.
    // Sized for the readings, which are the wider of the face's two looks — see
    // `contentW` in ClockFace.qml for why the width must not change on the click.
    implicitWidth: face.contentW + hPad * 2

    ClockFace {
        id: face
        anchors.fill: parent
        // `lit`, not `hovered`: while the flyout is open the bar's MouseArea gets
        // nothing, so the fill is being set by `hoveredExtra` alone — reading
        // `hovered` here left a highlighted pill with an unhighlighted face in
        // it, and the two disagreed for the whole time the panel was up.
        hovered: root.lit
        now: root.now
        // Zero while closed, and the flyout's `t` is zero while closed, so the
        // null check is nearly all this needs. The `|| 0` is for the one frame
        // that is not: the bar hands this pill a `flyoutHost` while the flyout
        // is still being constructed, and a bound property read before its first
        // evaluation comes back `undefined`, which `real` will not take. It
        // heals on the first change, but a red line in the log is not worth
        // saving a `Math.max(0, …)` over.
        glyphMix: (root.flyoutHost !== null && root.flyoutHost.glyphMix) || 0
    }

    // A 1x1 invisible dot sitting on the pill's top edge, midway across: the
    // point the flyout's window has to have its top edge on, since the panel is
    // centred on the bar and the shape starts as a copy of this pill.
    //
    // It is a separate item rather than the pill itself because quickshell hangs
    // the popup's edges off the *centre* of whatever it is anchored to, so anchoring
    // to the pill would put the window's top on the pill's middle — half a pill
    // too low, which is the whole difference between a morph and a panel that
    // appears below a pill. A dot-sized rect makes "its centre" and "the pixel I
    // meant" the same pixel. It rides the pill, so it cannot drift from it.
    Item {
        id: magnetItem
        // `implicitWidth`, not `width`: the flyout's window reads this rect the
        // instant it is shown, and reading a number off a binding beats reading
        // whatever a layout left behind. It is the same number either way — the
        // pill is never hidden now, see below — but the binding is the one that
        // was true at every layout pass rather than the one that happened to
        // come out of this one.
        x: (root.implicitWidth - width) / 2
        y: -height / 2
        width: 1
        height: 1
        visible: false
    }
    /// Exposed so the flyout can anchor to it without going through this pill's
    /// click handler.
    readonly property alias magnet: magnetItem

    onClicked: button => {
        if (button === Qt.LeftButton && root.flyoutHost) root.flyoutHost.toggleFor(root, root.magnet)
    }
}
