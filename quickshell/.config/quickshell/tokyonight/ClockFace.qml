// ClockFace.qml — the clock pill's contents, with no chrome: `HH:mm:ss` over
// `Sat 27 Sep`, at rest, on hover and while the popup is open. One look, and it
// does not move.
//
// It is a separate file because the pill's contents are one measurement and the
// pill's width is cut from it (see `contentW`): the font, the metrics and the
// padding arithmetic live here, exactly once. It has no clock of its own — the
// bar's `Clock` supplies the tick, the same value the popup's CLOCK card reads,
// and the hover.
import QtQuick

Item {
    id: root

    /// Set by the host from whatever MouseArea is over the face.
    property bool hovered: false

    /// The clock this face reads. Supplied, never owned: the host's timer is the
    /// only tick, so a face built against any other Date disagrees about the
    /// seconds digit.
    property var now

    /// The widest thing the face can draw, and the number the pill's width is cut
    /// from. Measured rather than read off the live text, and the reason is
    /// worth keeping: Qt rounds each character's advance separately, and it does
    /// not think this font's digits are all the same width. Measured over every
    /// time there is, `HH:mm:ss` ranges 62..64px on the seconds alone (`00:00:00`
    /// is 63, `00:00:01` is 64). A face sized off its own live text is therefore
    /// a pill that resizes once a second, which re-runs the bar's layout and
    /// slides the clock sideways. One pixel of disagreement between the pill's
    /// width and its text is what reads as a doubled clock.
    ///
    /// `timeWorst` is the widest the time can get, so the width is a constant.
    /// The date needs no such sample: all 2604 possible `ddd dd MMM` strings
    /// measure exactly 56px, because the format's variable parts are letters and
    /// a fixed-shape two-digit day. Re-measure `timeWorst` if the time's format
    /// or the font ever changes.
    readonly property real contentW: timeWorst.width

    // The two readings, 15 + 10 = 25 px of text in a 26 px pill. Heights are
    // declared rather than left to the fonts' line boxes (18 + 12) because the
    // sum of the line boxes is taller than the pill, and a Column that overflows
    // its pill cuts the time's descenders into the date.
    Item {
        id: readings
        anchors.centerIn: parent
        width: root.contentW
        height: 25

        Text {
            id: time
            x: 0; y: 0
            width: parent.width
            height: 15
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.now, "HH:mm:ss")
            // Cyan on hover, like every other label in the bar, and on the same
            // 120ms the popup's own hover runs at. The date does not follow it: a
            // 9 px line changing shade under a 13 px one that is reads as a bug,
            // and the pair's whole job is that the lower line stays the quieter
            // of the two.
            color: root.hovered ? Tokyo.cyan : Tokyo.fg
            font {
                family: Tokyo.fontFamily
                pixelSize: 13
                bold: true
                letterSpacing: 0.2
            }
            Behavior on color {
                ColorAnimation { duration: 120; easing.type: Easing.OutQuad }
            }
        }

        Text {
            id: date
            x: 0; y: 15
            width: parent.width
            height: 10
            verticalAlignment: Text.AlignVCenter
            // Centred, and the reason is `contentW`: the box is as wide as the
            // widest time there is, and the readings fill it. The date is 9px
            // against the time's 13px bold, so left-aligned it sat ~4px left of
            // centre — measurably off, and only against the time above it.
            horizontalAlignment: Text.AlignHCenter
            text: Qt.formatDateTime(root.now, "ddd dd MMM")
            color: Tokyo.trayGlyph
            font {
                family: Tokyo.fontFamily
                pixelSize: 9
                letterSpacing: 0.2
            }
        }
    }

    // Measured rather than implicit, and read by the pill's own width: a `Text`
    // nested in an Item reports its width only after layout, and a binding that
    // reads it during the first polish is how pills end up a character short.
    TextMetrics { id: timeWorst; font: time.font; text: "08:88:88" }
}