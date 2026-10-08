// ToastRow.qml — one notification in the toast stack.
//
// The layout here is deliberately flat: absolute x/y with widths derived from
// the card's own width, and the card's height derived from the text column's
// implicitHeight. The obvious nested version — a Column holding an Item that
// holds the icon and another Column holding the text — renders the card and
// the icon and silently drops every glyph, because two layout engines end up
// assigning y to the same item and the text ends up past the card's bottom.
// One owner per axis is worth the extra three lines.
//
// Three other things here are not decoration:
//
//   - The row slides in from the right and out to the right. A toast that only
//     fades reads as something that was switched on; the slide is what says it
//     arrived from the edge.
//   - The icon goes through NotifyIcon, so it is drawn at a size the source
//     actually has rather than upscaled into a fixed box.
//   - The × is always there, not on hover: a dismiss you have to find is a
//     dismiss you do not use, and it closes through the daemon's own object.
//     There are no action buttons here — a toast says what happened; the
//     notification centre is where you act on it.
import QtQuick
import Quickshell

Item {
    id: root

    /// The daemon's Notification for this row.
    ///
    /// Required, not assigned. When a Repeater's model is an array of objects,
    /// QML fills a delegate's required properties from the matching key — so
    /// `[{n: notification}]` fills this with no expression in between.
    required property var n
    /// The row's own index in `rows`. Required, and not taken from context:
    /// declaring `required property var n` above switches the delegate to
    /// required-property filling, and the unqualified `index` that used to come
    /// from the Repeater's context is then simply not there — `onDone` threw
    /// `ReferenceError: index is not defined` and the row never left the stack.
    required property int index
    /// the store, for the icon map
    property var store: null
    /// how long this row stays, in ms
    property int timeout: 5000

    /// emitted when the row has finished sliding out and can be dropped
    signal done()

    /// True once the row has decided to leave. Every exit path funnels
    /// through `leave()`, so `done()` fires exactly once per row: the ×, the
    /// expiry timer and the daemon's `onClosed`/`onNChanged` can all arrive in
    /// the same instant, and a second `done()` with the row already spliced
    /// out of the model lands on a different row with the wrong index.
    property bool leaving: false
    function leave() {
        if (root.leaving) return
        root.leaving = true
        root.done()
    }

    readonly property color accent: n !== null && n.urgency === 2
        ? Tokyo.red          // NotificationUrgency.Critical
        : Tokyo.blue

    /// 0 at construction, 1 once it is up. The card's x is driven off this same
    /// number, so the fade and the slide cannot disagree about where the row is
    /// in its own lifetime.
    property real shown: 0
    visible: root.shown > 0.001

    implicitHeight: card.height

    Behavior on shown {
        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: card
        width: parent.width
        // The taller of the icon and the text block, plus the padding either
        // side. Derived from the text rather than guessed at, so a four-line
        // body grows the card instead of spilling out of it.
        height: 20 + Math.max(40, textCol.implicitHeight)
        radius: Tokyo.popupRadius
        color: Tokyo.panelFill
        border.color: Tokyo.paneEdge
        border.width: 1

        // The slide. Starts a card-width to the right and settles against the
        // row's left edge.
        x: (1 - root.shown) * (root.width + 24)
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Critical notifications get a stripe down their leading edge. Colour
        // alone would not survive a greyscale screenshot, and a stripe is the
        // one cue that costs no width.
        Rectangle {
            x: 1
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: parent.height - 14
            radius: 2
            color: root.accent
            visible: root.accent !== Tokyo.blue
        }

        NotifyIcon {
            x: 12
            y: 10
            // 40, not 64. 64 is the size the toast this replaces asked for,
            // and it is the number that made every 32px app icon in the system
            // render as a blurry square. 40 is a size the installed themes
            // actually carry; a real image is still shown at its own size when
            // it is bigger than the box.
            size: 40
            source: root.n
            store: root.store
        }

        Column {
            id: textCol
            x: 62
            y: 10
            // Stops short of the × rather than running the summary under it.
            // `.x`, not `.left`: in this Qt build Item.left is a QQuickAnchorLine
            // object, not a number, so the arithmetic below went NaN, the width
            // became 0, and every glyph in the column silently vanished — a card
            // with an icon and a × and no text. `.x` is the plain number, and it
            // is in the same card-relative space as `x`, so the two subtract.
            width: dismiss.x - x - 6
            spacing: 2

            Text {
                width: parent.width
                text: root.n ? (root.n.appName || root.n.app || "") : ""
                color: Tokyo.dim
                elide: Text.ElideRight
                font { family: Tokyo.fontFamily; pixelSize: 10; letterSpacing: 0.8 }
                visible: root.n !== null && String(root.n.appName || root.n.app || "") !== ""
            }
            Text {
                width: parent.width
                text: root.n ? (root.n.summary || root.n.body || root.n.appName || root.n.app || "Notification") : ""
                color: root.n !== null && root.n.urgency === 2 ? Tokyo.red : Tokyo.fg
                elide: Text.ElideRight
                maximumLineCount: 3
                wrapMode: Text.WordWrap
                font { family: Tokyo.fontFamily; pixelSize: 12; bold: true }
            }
            Text {
                width: parent.width
                visible: root.n !== null && String(root.n.body || "") !== "" && String(root.n.body) !== String(root.n.summary)
                text: root.n ? (root.n.body || root.n.summary || "") : ""
                color: Tokyo.dim
                elide: Text.ElideRight
                maximumLineCount: 3
                wrapMode: Text.WordWrap
                font { family: Tokyo.fontFamily; pixelSize: 10 }
            }
        }

        // ---------- dismiss ----------
        Rectangle {
            id: dismiss
            anchors { right: parent.right; rightMargin: 4
                      verticalCenter: parent.verticalCenter }
            width: 28; height: 28
            radius: 5
            color: dHover.containsMouse ? Tokyo.bgHighlight : "transparent"

            Text {
                anchors.centerIn: parent
                text: "×"
                color: Tokyo.dim
                font { family: Tokyo.fontFamily; pixelSize: 13 }
            }
            MouseArea {
                id: dHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // `done()` rather than `dismiss()` on the daemon: it is the same
                // path the timeout and the client's own close take, so a hand
                // dismiss cannot land where an automatic one does not.
                onClicked: root.leave()
            }
        }

        // Clicking the body runs the notification's default action, which is
        // what a click anywhere in the middle of a notification means. Stops
        // short of the ×, which is a sibling and would otherwise lose the click
        // to whichever MouseArea Qt asks first.
        MouseArea {
            anchors {
                left: parent.left; leftMargin: 6
                right: dismiss.left; rightMargin: 6
                top: parent.top; topMargin: 4
                bottom: parent.bottom; bottomMargin: 4
            }
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (root.n === null) return
                const def = root.n.defaultAction
                if (def) def.invoke()
                if (root.n.appName !== "") {
                    Quickshell.execDetached([
                        "gtk-launch",
                        root.n.desktopEntry !== ""
                            ? root.n.desktopEntry
                            : String(root.n.appName).toLowerCase().replace(/\s+/g, "-"),
                    ])
                }
                root.leave()
            }
        }
    }

    // ---------- the clock ----------
    Timer {
        id: life
        interval: root.n !== null && root.n.expireTimeout > 0
            ? root.n.expireTimeout
            : root.timeout
        repeat: false
        onTriggered: root.leave()
    }

    Component.onCompleted: {
        // Start at 0 so the first frame is already at the slide's start offset;
        // setting `shown` immediately would let the Behavior animate from
        // whatever it happened to be.
        root.shown = 0
        Qt.callLater(() => root.shown = 1)
        if (root.n === null) { root.leave(); return }
        // `resident` is the client's own statement that this notification wants
        // to stay until it is acted on — a running transfer, a pending
        // question. Honouring it is the difference between a toast and a
        // banner.
        if (root.n.resident) { life.stop(); return }
        life.start()
    }

    // The daemon's object dying — the client closed or replaced the
    // notification, quickshell drops it — nulls `n`, which blanks every Text
    // at once and leaves an empty card. Leave immediately: `onClosed` can no
    // longer arrive from an object that is already gone, and the timer below
    // would otherwise spend its remaining seconds on a card with nothing in it.
    onNChanged: {
        if (root.n === null || root.n === undefined) root.leave()
    }

    // The notification expiring on its own — the client closed it, or it hit its
    // own timeout — takes the row with it, so the toast does not sit there
    // showing something that is no longer true.
    Connections {
        target: root.n
        function onClosed() { root.leave() }
    }


}
