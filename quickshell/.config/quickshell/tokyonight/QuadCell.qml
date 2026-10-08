// QuadCell.qml — one titled cell of the clock flyout.
//
// The two cells only share a frame: title, rule, padding, and an area for the
// body. Keeping the frame here (instead of two hand-rolled panels) is what makes
// them line up — both panes then have identical insets, so the rules and the
// text baselines agree across the pair.
//
// Children go into `body`; anything meant to sit at the right end of the title
// row (the timers pane's pause/resume + stop pair) goes into `headerExtra`:
//
//   QuadCell {
//       title: "UPTIME"
//       headerExtra: Row { PillButton { … } }
//       Text { … }        // body
//   }
//
// Deliberately anchored, never a Column: Qt can polish a positioner before all
// of its children exist and never polish it again, which leaves every child
// stacked at y=0 (see TimerCreator.qml for the full story).
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    /// children of this cell, placed under the title rule
    default property alias body: bodyHolder.data
    /// children pinned to the right of the title row
    property alias headerExtra: headerSlot.data

    property string title: ""
    property color accent: Tokyo.blue

    readonly property real pad: 10
    readonly property real headerH: 14
    readonly property real gap: 8

    /// Everything above and below `bodyHolder`: top pad, the title row, the gap
    /// under it (+4 for the headerExtra overhang, see `headerRule` below), the
    /// rule itself, the gap above the body, and the bottom pad.
    ///
    /// Published so a host can size a cell to its content without re-deriving
    /// this arithmetic and getting it subtly wrong. A host that hardcodes the
    /// figure instead compiles, loads, renders — and silently clips the bottom of
    /// whatever it was trying to fit, which is exactly the bug this number is
    /// here to make impossible.
    readonly property real chrome: pad * 2 + headerH + gap * 2 + 5

    implicitWidth: 214
    implicitHeight: 176
    radius: Tokyo.pillRadius
    // `bg`/`bgHighlight`, SysFlyout's card pair, and the reason is the one it
    // gives: the popup's own surface is bgDark, so `bg` (#1e2030) is one small
    // step up from it and the card reads as the same widget — where `pane`
    // (#394161) put a card almost two stops lighter than the surface it sits on.
    // `bgHighlight` for the border is a real step against that fill, which is
    // what makes the card a card.
    color: Tokyo.bg
    border.color: Tokyo.bgHighlight
    border.width: 1

    // ---------- title row ----------
    RowLayout {
        id: headerRow
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            leftMargin: root.pad; rightMargin: root.pad; topMargin: root.pad
        }
        height: root.headerH
        spacing: 6

        Text {
            text: root.title
            color: root.accent
            font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
            Layout.alignment: Qt.AlignVCenter
        }
        // pushes headerExtra to the far edge without ending the layout, so the
        // spacer cannot accidentally take part in the title's sizing
        Item { Layout.fillWidth: true; Layout.preferredHeight: 1 }

        // A nested layout reports its own implicit size, so this collapses to
        // nothing when a cell adds no headerExtra.
        RowLayout {
            id: headerSlot
            spacing: 6
            Layout.alignment: Qt.AlignVCenter
        }
    }

    // The rule sits `gap` below the title row, plus 4. Not because the title row
    // is taller than it looks but because `headerExtra` is: the pause/stop pair
    // are `PillButton`s — 22 tall against a 14 `headerRow` — so centring them
    // leaves them overhanging the row by 4 at the top and 4 at the bottom, and
    // `gap` measured from the row's own bottom is therefore 4 rows of air short
    // under the pair. The extra 4 is what makes the air beneath them 8, the same
    // as everywhere else in the pane. A bare 12 would do the same job and would
    // be wrong the moment `gap` moved; this reads as the 4 px it is.
    //
    // That 4 px is spent on the rule, not taken off the body: the host's `cellH`
    // constant is raised by the same 4, so the two panes keep one height and each
    // body comes out `cellH − chrome` long — unchanged. Leaving `cellH` alone
    // would put the 4 px straight back on the timer list's spare capacity, and
    // would clip the bottom of the clock pane's last block. Keep the two in step;
    // `ClockFlyout.qml`'s `cellH` comment carries the same arithmetic.
    Rectangle {
        id: headerRule
        anchors {
            left: parent.left; right: parent.right
            top: headerRow.bottom; topMargin: root.gap + 4
            leftMargin: root.pad; rightMargin: root.pad
        }
        height: 1
        color: Tokyo.hairline
    }

    // ---------- body ----------
    Item {
        id: bodyHolder
        anchors {
            left: parent.left; right: parent.right
            top: headerRule.bottom; bottom: parent.bottom
            leftMargin: root.pad; rightMargin: root.pad
            topMargin: root.gap; bottomMargin: root.pad
        }
    }
}
