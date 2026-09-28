// TimerCreator.qml — "set a new timer": slider + manual entry + Start.
//
// The "new timer" block: a readout, a 1-30 min slider, a manual-entry box and a
// START button. With TimerWindow.qml gone there is one host — ClockFlyout's
// timers pane — so every size in here is a constant rather than something the
// host negotiates.
//
// Deliberately anchored rather than a Column: Qt can polish a positioner before
// all of its children exist and never polish it again, which left every child
// stacked at y=0 and this block reporting zero height — the slider, entry box and
// START button were clipped off both panels. Anchors do not depend on polish
// order. (forceLayout() also rescues it, but only if you remember to call it.)
//
// Range is 1-30 minutes in 1-minute steps, matching the slider. The manual box
// accepts finer values ("4:30") because that is the reason it exists — the
// slider then rounds to the nearest minute for display, while the started
// timer keeps the exact value that was typed.
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls
import Quickshell

Item {
    id: root

    /// the host is closing / clearing the form (panel hidden, timer started)
    signal started()
    /// the manual box was clicked. The host takes the keyboard for the field:
    /// a layer surface is only handed the keys by the compositor when it is
    /// clicked, and `forceActiveFocus()` on its own would put a caret in a field
    /// that cannot see any keystrokes.
    signal fieldActivated()

    /// put the keyboard in the manual box. A host that owns the keyboard calls
    /// this once it has the grab; ids are file-private, so this is the only way
    /// in from outside.
    function focusField() {
        field.forceActiveFocus()
    }

    /// for the host's own diagnostics
    readonly property bool hasActiveField: field.activeFocus

    /// slider position in minutes, 1..30
    property real minutes: 25
    property string entry: ""
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
            top: sld.bottom; topMargin: root.gap
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
                // live-sync the slider, rounded to the slider's own step
                const ms = root.parse(text)
                if (ms !== null) root.minutes = Math.round(ms / 60000)
            }
            onAccepted: root.startFromEntry()
            MouseArea {
                anchors.fill: parent
                onClicked: root.fieldActivated()
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

    /// "25" | "25:30" | "1:00:00" → ms, clamped to 1-30 min. null if unparseable.
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

    /// snap the slider to whole minutes and mirror it into the entry box
    function commitSlider() {
        root.minutes = Math.round(root.minutes)
        root.entry = ""
        root.entryBad = false
    }

    function start() {
        TimerState.start(root.minutes * 60000)
        root.entry = ""
        root.entryBad = false
        root.started()
    }

    /// back to the default slider position with an empty box. A host that is
    /// dismissed by an outside click (the clock flyout) would otherwise
    /// reopen showing whatever was half-typed last time.
    function clear() {
        root.minutes = 25
        root.entry = ""
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
        root.minutes = Math.round(ms / 60000)
        TimerState.start(ms)
        root.entry = ""
        root.entryBad = false
        root.started()
    }

    Timer {
        id: badFlash
        interval: 900
        onTriggered: root.entryBad = false
    }
}
