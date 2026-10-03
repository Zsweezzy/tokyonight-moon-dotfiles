// TimerCreator.qml — "set a new timer": slider + manual entry + Start.
//
// The "new timer" block: a readout, a 1-30 min slider, a Name field, a
// manual-entry box and a START button. With TimerWindow.qml gone there is one
// host — ClockFlyout's timers pane — so every size in here is a constant rather
// than something the host negotiates.
//
// Deliberately anchored rather than a Column: Qt can polish a positioner before
// all of its children exist and never polish it again, which left every child
// stacked at y=0 and this block reporting zero height — the slider, entry box and
// START button were clipped off both panels. Anchors do not depend on polish
// order. (forceLayout() also rescues it, but only if you remember to call it.)
//
// Range is 1-30 minutes in 1-minute steps, matching the slider — that is
// `TimerState.maxMinutes`, the slider's range and nothing more. The manual box
// has its own, much higher ceiling, `TimerState.maxEntryMinutes` (24 h): a bar
// slider cannot reach a 45-minute tea or a long focus block, and a box clamped
// to the slider's range would just start 30:00 when you typed 45.
//
// Typing in the box live-moves the slider too, so the readout stays honest —
// rounded to whole minutes AND clamped into the slider's own range, or "2:00:00"
// would park the handle at 30 while the box said two hours. The box keeps the
// exact typed value regardless. Only Enter starts what was typed; START starts
// the slider's whole minutes, not what is in the box.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import Quickshell

Item {
    id: root

    /// the host is closing / clearing the form (panel hidden, timer started)
    signal started()
    /// one of the two fields was clicked. The host takes the keyboard for it:
    /// a layer surface is only handed the keys by the compositor when it is
    /// clicked, and `forceActiveFocus()` on its own would put a caret in a field
    /// that cannot see any keystrokes. Which one is in `nameWasClicked`.
    signal fieldActivated()

    /// Which of the two fields the last click landed on. `fieldActivated()`
    /// carries no argument — the host only needs to know that *a* field was
    /// clicked, because a layer surface is only handed the keys by the
    /// compositor when it is clicked — so which one has to be remembered here.
    /// Set before the signal goes out, because the host answers it
    /// synchronously by calling `focusField()`.
    property bool nameWasClicked: false

    /// put the keyboard in the field that was clicked. A host that owns the
    /// keyboard calls this once it has the grab; ids are file-private, so this
    /// is the only way in from outside.
    ///
    /// The MouseAreas inside both TextFields are what report the click, and
    /// they are declared above each field's contentItem, so they also swallow
    /// the press that would otherwise place a caret — one focus call cannot
    /// serve both, because putting the caret in a field the user did not click
    /// is what made the Name field look inert.
    ///
    /// `selectAll()` is the same pairing `openPrecise()` uses, and for the same
    /// reason: focus alone leaves `cursorPosition` at 0, so clicking a box that
    /// already holds text would PREPEND the next keystroke to it. Guarded on
    /// there being text, so an empty box is just focused.
    function focusField() {
        const target = root.nameWasClicked ? nameField : field
        target.forceActiveFocus()
        if (target.text.length > 0) target.selectAll()
    }

    /// for the host's own diagnostics
    readonly property bool hasActiveField: field.activeFocus || nameField.activeFocus

    /// slider position in minutes, 1..30
    property real minutes: 25
    property string entry: ""
    property string timerName: ""
    property bool entryBad: false

    readonly property real minMinutes: TimerState.minMinutes
    readonly property real maxMinutes: TimerState.maxMinutes
    readonly property int maxMinutesInt: TimerState.maxMinutes

    readonly property real gap: 8

    implicitHeight: entryRow.y + entryRow.height
    height: implicitHeight

    // ---------------- readout ----------------
    RowLayout {
        id: readout
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 6

        Text {
            text: TimerState.fmt(root.minutes * 60000)
            color: Tokyo.fg
            font { family: Tokyo.fontFamily; pixelSize: 20; bold: true }
        }
        Text {
            text: "min"
            color: Tokyo.trayGlyph
            font { family: Tokyo.fontFamily; pixelSize: 11 }
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 3
        }
        Item { Layout.fillWidth: true }
        Text {
            text: "1-" + root.maxMinutesInt + " min"
            color: Tokyo.trayGlyph
            font { family: Tokyo.fontFamily; pixelSize: 10 }
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: 2
        }
    }

    // ---------------- name ----------------
    // Declared above the slider but anchored below it: the order asked for is
    // length first (readout, slider), then the name, then the precise entry and
    // START. Anchors, not declaration order, decide where a block is drawn, so
    // the declaration order is left alone.
    Text {
        id: nameLabel
        anchors {
            left: parent.left
            top: sld.bottom; topMargin: root.gap
        }
        text: "Name"
        color: Tokyo.trayGlyph
        font { family: Tokyo.fontFamily; pixelSize: 10 }
    }

    Controls.TextField {
        id: nameField
        anchors {
            left: parent.left; right: parent.right
            top: nameLabel.bottom; topMargin: 4
        }
        implicitHeight: 26
        text: root.timerName
        placeholderText: "e.g. Tea, Focus, Break (optional)"
        color: Tokyo.fg
        placeholderTextColor: Tokyo.trayGlyph
        font { family: Tokyo.fontFamily; pixelSize: 12 }
        leftPadding: 8
        rightPadding: 8
        topPadding: 0
        bottomPadding: 0
        verticalAlignment: TextInput.AlignVCenter
        selectByMouse: true

        background: Rectangle {
            radius: 6
            color: Tokyo.panelFill
            border.width: 1
            border.color: nameField.activeFocus ? Tokyo.blue : Tokyo.paneEdge
        }
        onTextChanged: root.timerName = text
        onAccepted: root.startFromEntry()
        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.nameWasClicked = true
                root.fieldActivated()
            }
        }
    }

    // ---------------- slider ----------------
    Controls.Slider {
        id: sld
        anchors {
            left: parent.left; right: parent.right
            top: readout.bottom; topMargin: root.gap
        }
        height: 22
        from: root.minMinutes
        to: root.maxMinutes
        stepSize: 1
        snapMode: Controls.Slider.SnapAlways
        value: root.minutes
        // Release commits; dragging only previews, so a stray movement never
        // starts a timer by accident.
        onMoved: root.minutes = sld.value
        onPressedChanged: if (!sld.pressed) root.commitSlider()

        background: Rectangle {
            x: sld.leftPadding + sld.availableWidth / 2 - width / 2
            y: sld.topPadding + sld.availableHeight / 2 - height / 2
            width: sld.availableWidth
            height: 6
            radius: 3
            color: Tokyo.bgHighlight
            Rectangle {
                width: sld.visualPosition * parent.width
                height: parent.height
                radius: parent.radius
                color: Tokyo.yellow
            }
        }
        handle: Rectangle {
            x: sld.leftPadding + sld.visualPosition * (sld.availableWidth - width)
            y: sld.topPadding + sld.availableHeight / 2 - height / 2
            width: 14
            height: 14
            radius: 7
            color: sld.pressed ? Tokyo.fg : Tokyo.yellow
            border.color: Tokyo.bgDark
            border.width: 1
        }
    }

    // ---------------- entry + start ----------------
    RowLayout {
        id: entryRow
        anchors {
            left: parent.left; right: parent.right
            top: nameField.bottom; topMargin: root.gap
        }
        spacing: 8

        Controls.TextField {
            id: field
            Layout.preferredWidth: 96
            // implicitHeight, not height: a RowLayout manages its geometry and
            // assigning `height` there is undefined behaviour.
            implicitHeight: 26
            text: root.entry
            placeholderText: "12 or 12:30"
            color: Tokyo.fg
            placeholderTextColor: Tokyo.trayGlyph
            font { family: Tokyo.fontFamily; pixelSize: 12 }
            leftPadding: 8
            rightPadding: 8
            topPadding: 0
            bottomPadding: 0
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true

            background: Rectangle {
                radius: 6
                color: Tokyo.panelFill
                border.width: 1
                border.color: field.activeFocus ? Tokyo.blue
                    : (root.entryBad ? Tokyo.magenta : Tokyo.paneEdge)
            }
            onTextChanged: {
                root.entry = text
                root.entryBad = false
                // live-sync the slider, rounded to the slider's own step and
                // clamped to the slider's own range: the box reaches 24 h and
                // the slider stops at 30 min, so "2:00:00" would otherwise set
                // minutes to 120 and park the handle pinned at 30 while START
                // started two hours.
                //
                // The BOX keeps the exact typed value. Only Enter applies what
                // was typed (`startFromEntry`); START applies the slider, and
                // committing the slider here would overwrite the box with the
                // clamped value and throw away the hours the user just typed.
                const ms = root.parse(text)
                if (ms !== null) root.clampSlider(ms / 60000)
            }
            onAccepted: root.startFromEntry()
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    root.nameWasClicked = false
                    root.fieldActivated()
                }
            }
        }

        PillButton {
            text: "START"
            accent: Tokyo.blue
            Layout.alignment: Qt.AlignVCenter
            onClicked: root.start()
        }
    }

    // ---------------- logic ----------------

    /// "25" | "25:30" | "1:00:00" → ms, clamped to
    /// TimerState.minMs..maxMs, i.e. 1 minute to `maxEntryMinutes`. null if
    /// unparseable. The clamp is the manual box's own ceiling, not the
    /// slider's: "3:00:00" is a legitimate thing to type here even though the
    /// slider stops at 30 minutes.
    function parse(text) {
        const s = String(text).trim()
        if (!/^\d{1,3}(:\d{1,2}){0,2}$/.test(s)) return null
        const p = s.split(":").map(Number)
        let ms
        if (p.length === 1) ms = p[0] * 60000
        else if (p.length === 2) ms = p[0] * 60000 + p[1] * 1000
        else ms = (p[0] * 3600 + p[1] * 60 + p[2]) * 1000
        return Math.max(TimerState.minMs, Math.min(TimerState.maxMs, ms))
    }

    /// Whole minutes, forced into the slider's own range. Every write to
    /// `minutes` goes through here, and it has to: `minutes` is bound to the
    /// Slider, so a value off the end of the range is pinned by the control
    /// while every reader of the PROPERTY still sees the number that was
    /// written — a handle parked at 30 beside a readout saying "2:00:00", and
    /// a START that then starts the readout's number. Rounding and clamping are
    /// the same operation for this slider: stepSize 1, SnapAlways.
    function clampSlider(minutes) {
        root.minutes = Math.max(root.minMinutes,
            Math.min(root.maxMinutes, Math.round(minutes)))
    }

    /// snap the slider to whole minutes and mirror it into the entry box
    function commitSlider() {
        root.clampSlider(root.minutes)
        root.entry = ""
        root.entryBad = false
    }

    function start() {
        TimerState.start(root.minutes * 60000, root.timerName)
        root.entry = ""
        root.timerName = ""
        root.entryBad = false
        root.started()
    }

    /// back to the default slider position with an empty box. A host that is
    /// dismissed by an outside click (the clock flyout) would otherwise
    /// reopen showing whatever was half-typed last time.
    function clear() {
        root.minutes = 25
        root.entry = ""
        root.timerName = ""
        root.entryBad = false
    }

    function startFromEntry() {
        const ms = root.parse(root.entry)
        if (ms === null) {
            // nudge the box: red border for a moment, keep the typed text so
            // it can be corrected instead of retyped
            root.entryBad = true
            badFlash.restart()
            return
        }
        // The slider is left pointing at what START would use, which for a
        // typed value longer than the slider's range is the slider's maximum
        // and not the typed number — that number is already started above.
        root.clampSlider(ms / 60000)
        TimerState.start(ms, root.timerName)
        root.entry = ""
        root.timerName = ""
        root.entryBad = false
        root.started()
    }

    Timer {
        id: badFlash
        interval: 900
        onTriggered: root.entryBad = false
    }
}
