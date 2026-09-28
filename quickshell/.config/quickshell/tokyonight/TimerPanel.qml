// TimerPanel.qml — the timer list + the "new timer" form, with no frame.
//
// Extracted from TimerWindow.qml so it could be shared by the clock flyout's
// timers cell and the standalone window over one TimerState singleton instead
// of two hand-kept copies. The host owns the frame and the title row; the only
// host left is ClockFlyout's QuadCell, which already has a title row and a rule
// in the same place. The window, its SUPER + SHIFT + T bind and the `timer` IPC
// target that opened it are gone — so `maxListHeight` and the unpinned branch of
// `listCap` below have no host left either, and exist only because removing them
// was not what was asked for.
//
// What the second host bought was list capacity: the window was as tall as its
// timers needed, while the flyout's pane is sized by the clock pane's content
// next to it and so caps the list. That cap is now silent — see `listCap`.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import Quickshell

Item {
    id: root

    /// the manual box was clicked — the host puts the keyboard in it
    signal fieldActivated()
    /// a timer was started, so a host that clears its form on close can reset
    signal formChanged()

    /// cap the list and clip it; -1 grows with the number of timers. Ignored
    /// while `pinFormToBottom` is set — then the cap comes from the space.
    property int maxListHeight: -1
    /// row height: 38. There is exactly one host — ClockFlyout's TIMERS pane —
    /// and it used to pass 36 here over a default of 46 that therefore never
    /// took effect, so this is now the one place the number lives and the host
    /// says nothing.
    ///
    /// 38 is what five rows fit into: the measured cap is 227 px, so five rows
    /// at 38 with the 8 px gaps take 5 × 38 + 4 × 8 = 222 px and leave 5 px
    /// spare (at 36 the same five rows left 15). The drop boundary is the same
    /// either way: a row could only grow to 39 before the count falls to four.
    /// The tightness INSIDE a row is therefore not something a taller row was
    /// going to rescue — it is what the capacity budget spends.
    /// See the README. The cap itself is derived, see `listCap`; this is what
    /// it is divided by.
    property int rowH: 38

    /// The host's box is taller than this panel's content and wants the form
    /// pinned to the bottom of it, with the list at the top and the slack
    /// between: "what is running" and "set one up" as two ends of one pane
    /// rather than one stack floating in the middle. The window host leaves
    /// this off — it is exactly as tall as its content, so there is no slack to
    /// spend.
    property bool pinFormToBottom: false

    // ---------------- geometry ----------------

    readonly property real gap: 8
    /// the bottom of the form, measured off its last anchored child (the entry
    /// row) rather than off anything the form's contents happen to be
    readonly property real tail: creator.y + creator.height

    // A positioner is never nested inside another one (see TimerCreator.qml),
    // and a binding that reads an unset positioner's y once is how this panel
    // ends up a block too short. Measuring from the last anchored child keeps
    // the height honest no matter what polish order Qt picks.
    implicitHeight: root.tail
    // Only `top` is anchored, never `top`+`bottom`: anchoring both would make
    // the anchors own the height, and assigning to `height` on top of that is
    // a binding loop. So "fill the host" is expressed here instead.
    height: root.pinFormToBottom ? parent.height : implicitHeight

    /// How far down the list may go. Unpinned, that is the host's `maxListHeight`
    /// and nothing else. Pinned, it is the gap between the top of the panel and
    /// the rule above the form, so the list runs down to the slider instead of
    /// stopping short and leaving a hole in the middle of the pane.
    ///
    /// Derived, never a constant: the pane's height is itself measured off the
    /// clock pane's font metrics, so a hard-coded row count is wrong the moment
    /// either side changes — and wrong here means either a gap or rows running
    /// under the form.
    ///
    /// There is no overflow line any more. It used to read "+N more — full list
    /// in the timer window" and point at `TimerWindow.qml`, which is gone, so it
    /// was removed rather than reworded. That leaves the cap *silent*: past the
    /// rows that fit, the next one simply is not drawn and nothing says so. The
    /// alternatives were a count somewhere that survives (the host's title row)
    /// or letting the list grow, and both are a design change rather than a
    /// deletion — so this is a known gap, not an oversight.
    readonly property real listCap: root.pinFormToBottom
        ? Math.max(root.rowH, creatorRule.y - root.gap - 3)
        : root.maxListHeight

    /// how many rows fit under the cap; -1 = unlimited
    readonly property int capacity: root.listCap < 0
        ? -1
        : Math.max(1, Math.floor((root.listCap + root.gap) / (root.rowH + root.gap)))

    /// running timers the cap is not showing. Drawn nowhere — see `listCap` —
    /// but kept, because it is the input any overflow affordance needs and
    /// recomputing it is the easy half of that job.
    readonly property int hidden: TimerState.timers.length - Math.min(
        TimerState.timers.length, root.capacity < 0 ? TimerState.timers.length : root.capacity)

    // ---------------- the list ----------------

    Item {
        id: rowsArea
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: root.capacity < 0
            ? (TimerState.active
                ? TimerState.timers.length * (root.rowH + root.gap) - root.gap
                : emptyLine.implicitHeight)
            : Math.min(
                root.listCap,
                TimerState.active
                    ? TimerState.timers.length * (root.rowH + root.gap) - root.gap
                    : emptyLine.implicitHeight)
        // Only clip when capped: with no cap the rows define the height, and
        // clipping would shave the progress bar off the last one.
        clip: root.capacity > 0

        Text {
            id: emptyLine
            anchors { left: parent.left; right: parent.right; top: parent.top }
            visible: !TimerState.active
            text: root.capacity < 0
                ? "nothing running — set one below"
                : "nothing running"
            color: Tokyo.trayGlyph
            font { family: Tokyo.fontFamily; pixelSize: 11 }
        }

        Repeater {
            id: rows
            model: TimerState.timers

            delegate: Rectangle {
                id: row
                required property int index
                required property var modelData
                readonly property var t: modelData

                // A Repeater hands out no geometry of its own and the parent is
                // a plain Item, so place the row by hand.
                width: rowsArea.width
                height: root.rowH
                y: index * (root.rowH + root.gap)
                visible: root.capacity < 0 || index < root.capacity
                radius: 6
                color: "transparent"

                readonly property bool fired: row.t.fired
                readonly property bool paused: row.t.paused && !row.t.fired
                readonly property color accent: row.fired
                    ? (row.paused ? Tokyo.trayGlyph : Tokyo.green)
                    : (row.paused ? Tokyo.yellow : Tokyo.blue)

                // x across the grab strip -> how much is left. 0 at the strip's
                // left edge is nothing left, 1 at its right edge is the whole
                // total still to run — which is why this is a playhead and not
                // a length control.
                function scrubTo(x) {
                    if (grabArea.width <= 0) return
                    const fraction = Math.max(0, Math.min(1, x / grabArea.width))
                    TimerState.scrub(row.t.id, row.t.totalMs * (1 - fraction))
                }

                // Prefilled with the time that is LEFT, not the total: that is
                // the number the pointer is about to move. Assigned rather than
                // bound to `remainingMs` on purpose — a `text:` binding is torn
                // down by the first keystroke and would then greet the next
                // open of this row with the previous attempt still in it.
                function openPrecise() {
                    preciseBox.visible = true
                    preciseField.text = TimerState.fmt(TimerState.remainingMs(row.t))
                    preciseField.forceActiveFocus()
                    preciseField.selectAll()
                }

                // Every way the box closes goes through here. The obvious way —
                // the field losing the focus — cannot be relied on for a flyout
                // close: nothing here can check whether Qt drops item focus when
                // a popup window is hidden, and whether a leave event still
                // reaches the grab strip on a surface that is unmapping. So the
                // host's reset() closes it explicitly for every row instead of
                // depending on either.
                function closePrecise() {
                    preciseBox.visible = false
                }

                // Enter, and only Enter, applies. Everything else — the field
                // losing focus, or the pointer leaving the strip — closes the
                // box and throws away whatever was typed.
                function commitPrecise() {
                    const typed = preciseField.text.trim()
                    row.closePrecise()
                    // Checked against the raw string, not the parts: `Number("")`
                    // is 0, so "::" and "-" split into numbers without error and
                    // would reach retime() as 0 — which is a running timer's end,
                    // and fires it. Same regex as TimerCreator.parse, so the two
                    // boxes take the same set of strings and neither surprises.
                    // 0 itself is legitimate: retime() allows it, so a paused
                    // timer parks its playhead at 0 and stays paused, and a
                    // running one ends now.
                    if (!/^\d{1,3}(:\d{1,2}){0,2}$/.test(typed)) return
                    const parts = typed.split(":").map(Number)
                    let ms = parts[0] * 60000
                    if (parts.length === 2) ms = parts[0] * 60000 + parts[1] * 1000
                    if (parts.length === 3) ms = (parts[0] * 3600 + parts[1] * 60 + parts[2]) * 1000
                    TimerState.retime(row.t.id, ms)
                }

                // The playhead's grab area: a 12 px transparent strip on the
                // row's bottom edge. It has to be bigger than the 3 px bar it
                // covers, because a 3 px target is not a target — but the bar
                // itself keeps its 3 px and stays exactly where it is. This is
                // an input surface laid over the row, not a resize of it.
                //
                // 12 px is the bar's 3 px plus enough slack to be a real target
                // with a mouse. It also reaches up over the "of mm:ss" line just
                // above the bar, which is the band the pointer is aiming at when
                // it goes for the bar.
                //
                // Declared BEFORE the RowLayout on purpose. A later sibling
                // paints on top and takes the clicks first, so this has to sit
                // UNDER the three PillButtons: their boxes reach down into the
                // bottom 3 px of this strip, and a strip on top would quietly
                // eat that much of their click area.
                MouseArea {
                    id: grabArea
                    // A finished timer is locked, and gets no grab area at all.
                    // `visible: false` is enough to say that — an invisible item
                    // takes no input either way.
                    visible: !row.fired
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                        leftMargin: 4; rightMargin: 4
                    }
                    height: 12
                    hoverEnabled: true
                    // A press is a drag of zero length, so the two handlers
                    // below do the same arithmetic and differ only in that
                    // `pressed` is already true for the second one.
                    //
                    // Qt documents `positionChanged` as firing only while a
                    // button is down, so on a Qt that behaves as documented the
                    // `pressed` test never changes anything. It is there so that
                    // a plain hover cannot rewrite a deadline if that ever stops
                    // holding: a hover near the right end of a strip would set
                    // remaining to 0 and fire a running timer — chime and
                    // notification — from a mouse merely crossing the panel.
                    onPressed: (mouse) => {
                        preciseWait.stop()
                        row.closePrecise()
                        row.scrubTo(mouse.x)
                    }
                    onPositionChanged: (mouse) => { if (pressed) row.scrubTo(mouse.x) }
                    onEntered: preciseWait.start()
                    onExited: {
                        preciseWait.stop()
                        hoverSettle.restart()
                    }
                }

                RowLayout {
                    id: rowLayout
                    anchors {
                        left: parent.left; right: parent.right
                        leftMargin: 4; rightMargin: 4
                        verticalCenter: parent.verticalCenter
                        verticalCenterOffset: -4   // keeps the bar clear: air measured below
                    }
                    spacing: 8

                    Text {
                        text: row.fired ? "\uf00c" : (row.paused ? "\uf04b" : "\uf04c")
                        color: row.accent
                        font { family: Tokyo.fontFamily; pixelSize: 12 }
                    }

                    Column {
                        id: textColumn
                        spacing: 0
                        Layout.fillWidth: true

                        Text {
                            text: row.fired
                                ? "done"
                                : TimerState.fmt(TimerState.remainingMs(row.t))
                            color: row.accent
                            font { family: Tokyo.fontFamily; pixelSize: 16; bold: true }
                        }
                        Text {
                            // The same line in every state, on purpose. "paused ·
                            // of 30:00" measured 91.9 px in the 86.8 px this
                            // column actually has, so it overhung by 5.1 px into
                            // the 8 px gap before the buttons — it stopped being
                            // inside the box it belongs in, and that is all.
                            // Nothing on the row clips and neither Text elides,
                            // so every glyph painted; no letter was ever lost.
                            // It was also the fifth way this row said "paused":
                            // the big time, the left glyph, the pause button
                            // and the bar are all yellow already, and the bar
                            // has to keep that job now that it is draggable.
                            text: "of " + TimerState.fmt(row.t.totalMs)
                            color: Tokyo.trayGlyph
                            font { family: Tokyo.fontFamily; pixelSize: 9 }
                        }
                    }

                    PillButton {
                        glyph: row.fired ? "\uf067" : (row.paused ? "\uf04b" : "\uf04c")
                        accent: row.fired ? Tokyo.green : Tokyo.yellow
                        onClicked: row.fired
                            ? TimerState.nudge(row.t.id, 1)
                            : TimerState.togglePause(row.t.id)
                    }
                    PillButton {
                        glyph: "\uf067"        // plus
                        accent: Tokyo.cyan
                        onClicked: TimerState.nudge(row.t.id, 1)
                    }
                    PillButton {
                        glyph: "\uf068"        // times
                        accent: Tokyo.magenta
                        onClicked: TimerState.stop(row.t.id)
                    }
                }

                // progress bar
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom
                              leftMargin: 4; rightMargin: 4; bottomMargin: 2 }
                    height: 3
                    // A radius past half the height is not a pill, it is a
                    // lozenge: 2 on a 3 px bar rounds it into a lens, not a bar.
                    radius: height / 2
                    color: Tokyo.bgHighlight
                    Rectangle {
                        width: parent.width * TimerState.progress(row.t)
                        height: parent.height
                        radius: parent.radius
                        // A finished timer greys its bar out, because the bar is
                        // now the one thing on the row that says the playhead is
                        // locked there. The big time and the tick glyph stay
                        // green — those are the "done" signal, and the row stays
                        // on screen precisely because `+1` is the only way back.
                        color: row.fired ? Tokyo.trayGlyph : row.accent
                        Behavior on width {
                            // Off while the pointer has the bar. A 250 ms ease on
                            // a playhead the pointer is driving leaves the bar
                            // trailing behind it and settling somewhere the
                            // pointer is not.
                            enabled: !grabArea.pressed
                            NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
                        }
                    }
                }

                // Precise entry: resting the pointer on the strip for one
                // second opens a box to type an exact remaining time into. The
                // delay is what keeps a sweep across several bars from opening
                // five boxes at once. Deliberately started on the hover and not
                // on the press, so it can never pop open under a drag.
                Timer {
                    id: preciseWait
                    interval: 1000
                    onTriggered: row.openPrecise()
                }

                // The strip and this box touch, and they are two separate
                // MouseAreas, so whichever one Qt tells first would be a guess.
                // The leave only schedules this; by the time it runs, both hover
                // flags have settled and the answer is unambiguous.
                Timer {
                    id: hoverSettle
                    interval: 0
                    onTriggered: {
                        if (!grabArea.containsMouse && !boxHover.containsMouse) row.closePrecise()
                    }
                }

                Rectangle {
                    id: preciseBox
                    visible: false
                    // Inside the row, above the bar, so it can never reach the
                    // row above. Its top edge sits on the grab strip's top edge,
                    // so the two do not overlap and a click inside the box can
                    // never fall through into a drag. It runs from the row's
                    // left margin to the text column's right edge, so the whole
                    // time it is editing is covered while the three buttons past
                    // that edge stay clickable.
                    //
                    // The right edge is arithmetic rather than
                    // `right: textColumn.right`. The column is placed by the
                    // layout, not by anchors, so its `right` line is expressed
                    // in the layout's coordinates, while this box is a child of
                    // the row and its anchors are read in the row's — two spaces
                    // that differ by where the layout sits and the row's own
                    // margin. Resolving one against the other is a quiet way to
                    // land that far out with nothing to say so, so the
                    // conversion is written out instead: the column's real
                    // right edge is its own x plus its width, offset by the
                    // layout's x, and the right margin is what is left of the
                    // row past that.
                    anchors {
                        left: parent.left; right: parent.right; bottom: parent.bottom
                        leftMargin: 4
                        rightMargin: parent.width - (rowLayout.x + textColumn.x + textColumn.width)
                        bottomMargin: 12
                    }
                    height: 20
                    radius: 6
                    color: Tokyo.panelFill
                    border.width: 1
                    border.color: Tokyo.blue

                    Controls.TextField {
                        id: preciseField
                        anchors.fill: parent
                        color: Tokyo.fg
                        font { family: Tokyo.fontFamily; pixelSize: 12 }
                        leftPadding: 6
                        rightPadding: 6
                        topPadding: 0
                        bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        // The box around it is the frame; the Basic style's own
                        // background would only paint over the top of it.
                        background: Item {}
                        onAccepted: row.commitPrecise()
                        // Losing the focus dismisses without applying — which is
                        // how a click elsewhere in the pane and a Tab both end
                        // up throwing the typed value away. A pane that closes
                        // does not rely on this: `reset()` closes every box
                        // explicitly, because nothing here can check that Qt
                        // drops item focus when a popup window is hidden.
                        //
                        // There is deliberately no Escape handler of its own:
                        // ClockFlyout registers a window-level `Shortcut` on
                        // Escape, and Qt resolves shortcuts before ordinary key
                        // propagation, so anything written here would never fire
                        // — it would only be a lie in the source. Escape closes
                        // the whole flyout, and `reset()` closes this box on the
                        // way out, so the dismissal does not rest on the field
                        // happening to lose its focus as the window goes.
                        onActiveFocusChanged: {
                            if (!activeFocus) row.closePrecise()
                        }
                    }

                    // Hover only, and declared after the field on purpose: put
                    // it first and the field is above it and takes every event,
                    // so it would never learn the pointer had left. It must not
                    // swallow the clicks that put a caret in the field and drag
                    // out a selection either, which is what `Qt.NoButton` is
                    // for — it lets the press fall through to the field.
                    MouseArea {
                        id: boxHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onExited: hoverSettle.restart()
                    }
                }
            }
        }
    }

    // ---------------- the form ----------------

    Rectangle {
        id: creatorRule
        anchors { left: parent.left; right: parent.right }
        height: 1
        color: TimerState.active ? Tokyo.hairline : "transparent"
        // Directly above the form when the form is pinned to the bottom,
        // directly below the list when it is not. A `y` binding rather than a
        // `top` anchor because this needs *two* branches and an anchor bound to
        // a conditional keeps the value it was first given.
        y: root.pinFormToBottom
            ? creator.y - root.gap - 1
            : rowsArea.bottom + root.gap
    }

    TimerCreator {
        id: creator
        anchors { left: parent.left; right: parent.right }
        // Bottom-anchored in pin mode, chained off the rule otherwise. `y` for
        // the same reason as the rule: two branches, and neither of them reads
        // the other in the same direction, so there is no loop either way.
        y: root.pinFormToBottom
            ? parent.height - height
            : creatorRule.y + 1 + root.gap
        onStarted: root.formChanged()
        onFieldActivated: root.fieldActivated()
    }

    // ---------------- host hooks ----------------

    function focusField() {
        creator.focusField()
    }

    /// a flyout that closes on an outside click would otherwise reopen with
    /// half-typed minutes still in the box.
    function reset() {
        creator.clear()
        // The precise boxes go too, closed by hand rather than left to the
        // focus loss that normally does it. The rows are reused, not rebuilt, so
        // a `visible: true` here survives into the next opening of the pane —
        // and whether Qt drops item focus on a hidden popup window, or delivers
        // a leave event to the grab strip on an unmapping surface, is not
        // something this code can check. This is: the box is closed either way.
        for (let i = 0; i < rows.count; ++i) {
            const item = rows.itemAt(i)
            if (item) item.closePrecise()
        }
    }
}
