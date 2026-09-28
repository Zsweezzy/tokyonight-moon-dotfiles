// ClockFace.qml — the clock pill's contents, with no chrome: `HH:mm:ss` over
// `Sat 27 Sep` when the pill is closed, a clock glyph when it is open, and the
// two cross-fading on the way between.
//
// Both looks are here because the change is the morph. The bar's copy is covered
// by the flyout's surface for the whole open, so the widget has no way to swap
// its own contents on the frame the panel appears — the copy that *is* on screen
// during the morph is the flyout's, and it has to be showing the same thing the
// bar's copy will be showing when the shape's top edge walks off the pill. One
// `glyphMix`, shared by both hosts, is what keeps that true; see `glyphMix` in
// ClockFlyout.qml.
//
// Still worth its own file for the reason it always was: the pill's contents get
// drawn twice over the morph — the bar's copy and the flyout's — and the two
// must be the same face at the same pixels, so exactly one of them may own the
// font, the metrics and the padding arithmetic. It has no clock of its own; the
// bar's `Module` supplies hover and the click, and each host supplies `now`.
import QtQuick

Item {
    id: root

    /// Set by the host from whatever MouseArea is over the face.
    property bool hovered: false

    /// The clock this face reads. Supplied, never owned: there are two faces on
    /// screen at once during the morph, and two Timers with two start instants
    /// are two clocks that can disagree about the seconds digit for as long as
    /// both are drawing.
    property var now

    /// 0 = the readings, 1 = the glyph. Real-valued rather than a bool because
    /// the flyout's copy is drawn *on* the shape, not clipped by it: all 26 rows
    /// of it are on screen from t=0, so a hard swap is a pop the morph's cover
    /// cannot hide. Short fade — see `glyphMix` in ClockFlyout.qml for why it
    /// must not be a long one.
    property real glyphMix: 0

    /// The widest thing the face can draw. The glyph is the odd one out: it is
    /// centred, and it is nowhere near as wide as a line of digits, so the pill
    /// is sized for the readings and the glyph gets whatever is left over. That
    /// is also what keeps the pill's width the same in both looks — a pill that
    /// narrowed on the click would leave the shape's closed end (which is a copy
    /// of the pill's *wide* rect, measured before the click) hanging over a
    /// narrower pill, and the joint would open on the wrong edges.
    readonly property real contentW: Math.max(
        timeMetrics.width, dateMetrics.width, glyphMetrics.width)

    /// The pill width this face wants, at the bar's own horizontal padding. The
    /// bar's `Module` uses it for its implicit width; the flyout only needs it
    /// as a fallback for before the bar's pill has been handed over.
    readonly property real faceW: contentW + 2 * Tokyo.pillHPad

    // The two readings, 15 + 10 = 25 px of text in a 26 px pill. Heights are
    // declared rather than left to the fonts' line boxes (18 + 12) because the
    // sum of the line boxes is taller than the pill, and a Column that overflows
    // its pill clips the time's descenders into the date.
    Item {
        id: readings
        anchors.centerIn: parent
        width: root.contentW
        height: 25
        opacity: 1 - root.glyphMix
        // Off at exactly 0, so the last frame of a fade is the same as no item.
        visible: opacity > 0

        Text {
            id: time
            x: 0; y: 0
            width: parent.width
            height: 15
            verticalAlignment: Text.AlignVCenter
            text: Qt.formatDateTime(root.now, "HH:mm:ss")
            // Cyan on hover, like every other label in the bar. The date does
            // not follow it: a 9 px line changing shade under a 13 px one that
            // is reads as a bug, and the pair's whole job is that the lower line
            // stays the quieter of the two.
            color: root.hovered ? Tokyo.cyan : Tokyo.fg
            font {
                family: Tokyo.fontFamily
                pixelSize: 13
                bold: true
                letterSpacing: 0.2
            }
            Behavior on color {
                ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
            }
        }

        Text {
            id: date
            x: 0; y: 15
            width: parent.width
            height: 10
            verticalAlignment: Text.AlignVCenter
            text: Qt.formatDateTime(root.now, "ddd dd MMM")
            color: Tokyo.trayGlyph
            font {
                family: Tokyo.fontFamily
                pixelSize: 9
                letterSpacing: 0.2
            }
        }
    }

    // The open end. Centred in whatever rect it is given, which is the pill's
    // own — same pixels, same colour, same 26 rows as the face that is fading
    // out underneath it, so the hand-over between them is not a thing you can
    // see. Cyan on hover, the whole pill's worth of it.
    Text {
        id: glyph
        anchors.centerIn: parent
        text: Tokyo.clockGlyph
        opacity: root.glyphMix
        visible: opacity > 0
        color: root.hovered ? Tokyo.cyan : Tokyo.fg
        font {
            family: Tokyo.fontFamily
            pixelSize: Tokyo.clockGlyphSize
            letterSpacing: 0
        }
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
    }

    // Measured rather than implicit: the flyout reads `faceW` to know how wide
    // the pill is at t=0, and a `Text` nested in an Item reports its width only
    // after layout — a binding that reads it during the first polish is how
    // pills end up one glyph short. The glyphs' own text is the sample, so a
    // change to either format is a change to the width with nothing else to
    // remember to update.
    //
    // They read `text` and `font` off the Texts but nothing else, and in
    // particular not their visibility: both looks are hidden at their own end of
    // the cross-fade, and if the width followed the hidden look out, the pill
    // would resize on the click that opens the panel — with the shape's closed
    // end already measured from the old width.
    TextMetrics { id: timeMetrics;  font: time.font;  text: time.text }
    TextMetrics { id: dateMetrics;  font: date.font;  text: date.text }
    TextMetrics { id: glyphMetrics; font: glyph.font; text: glyph.text }
}
