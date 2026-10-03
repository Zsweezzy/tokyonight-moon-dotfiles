// NotificationCenter.qml — the notification centre: everything that has
// arrived, read or not, with its actions still on it.
//
// The list is the history the store keeps, not the notifications the daemon is
// currently holding. Those are different things and the difference is the whole
// point of a centre: a toast has gone by the time you get to it, and a
// notification that is still resident because nothing acted on it is a bug
// report, not a record.
//
// Every row can still be acted on, because the store keeps the daemon's live
// object alongside the record for as long as it exists. When it does not — the
// notification expired, or it came back off disk after a reboot — the row says
// so and offers to open the app instead, rather than showing a button that
// does nothing.
import QtQuick
import Quickshell

PopupWindow {
    id: root

    visible: false
    // Dismisses on any click outside, which is every other flyout's contract and
    // the reason none of them need a click-outside MouseArea.
    grabFocus: true
    // White unless told otherwise, and the window is exactly the box's size, so
    // the white showed as a slab behind the panel with nothing in front of it.
    color: "transparent"

    property var store: null
    property var pill: null

    readonly property real gap: 6
    readonly property real padH: 16
    readonly property real padV: 12

    /// How many rows the list shows before it scrolls. A centre is for
    /// skimming, not for reading four hundred of them.
    readonly property int visibleRows: 8
    readonly property real rowH: 62

    implicitWidth: 380
    implicitHeight: box.height + root.gap

    // ---------------- the reveal ----------------
    // The same one-number reveal SettingsFlyout uses, because it is the same
    // gesture: the panel leaves the pill it belongs to. `t` is 0 shut and 1
    // open, and the box fades and rises off it, so the whole panel moves as one
    // thing rather than each row arriving on its own.
    property real t: 0
    /// Set while the close runs, so a second click reverses it instead of
    /// starting a second open on top of a half-finished close.
    property bool closing: false

    SequentialAnimation {
        id: openAnim
        NumberAnimation {
            target: root; property: "t"
            from: 0; to: 1
            duration: 260
            easing.type: Easing.OutQuart
        }
    }

    // Quicker than the open, and no `from:`, so it starts from wherever `t`
    // actually is — the only way a close can interrupt a half-finished open
    // without a jump.
    SequentialAnimation {
        id: closeAnim
        NumberAnimation {
            target: root; property: "t"
            to: 0
            duration: 200
            easing.type: Easing.InQuart
        }
        ScriptAction { script: root.hide() }
    }

    function hide() {
        root.closing = false
        root.visible = false
    }

    function toggleFor(item) {
        root.pill = item
        // Bottom/Bottom like the other right-hand flyouts, so the panel hangs
        // under the bell and the 6px `gap` is the strip of nothing that makes
        // it read as coming out of the pill rather than sitting on it.
        root.anchor.item = item
        root.anchor.edges = Edges.Bottom
        root.anchor.gravity = Edges.Bottom
        if (root.closing) {
            closeAnim.stop()
            root.closing = false
            openAnim.start()
            return
        }
        if (root.visible) {
            root.closing = true
            closeAnim.start()
            return
        }
        // Opening the centre is the act of reading it. Anything less makes the
        // badge a thing you have to dismiss separately, and a badge you have to
        // dismiss is a badge you learn to ignore.
        if (root.store !== null) root.store.markAllRead()
        root.visible = true
        root.t = 0
        openAnim.start()
    }

    // A panel dismissed by an outside click never reaches `hide()`: the
    // compositor closes an xdg_popup itself, and the surface is already gone by
    // the time we hear about it. So there is nothing to animate — just drop `t`
    // so the next open starts from the top rather than mid-reveal.
    onVisibleChanged: {
        if (visible) return
        openAnim.stop()
        closeAnim.stop()
        root.closing = false
        root.t = 0
    }

    // A notification arriving while the centre is open goes straight into the
    // list, and the list is showing the newest at the top, so nothing has to
    // move. It is not a toast: the centre is already the place you are looking.
    Connections {
        target: root.store
        function onNewNotification() { if (root.visible) root.list.positionViewAtBeginning() }
    }

    Rectangle {
        id: box
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: content.implicitHeight + root.padV * 2
        color: Tokyo.bgDark
        radius: Tokyo.popupRadius
        // A distinct 1px outline, like the launcher panel's. `paneEdge` rather
        // than a `Qt.lighter` of our own fill: `box.color` is `bgDark`
        // (#16161e), so lightening it by 1.25 lands near #1f1f29 — an outline
        // nine units off the fill it borders, i.e. nothing — and `paneEdge` is
        // exactly what it is for, a card reads as a card because of its outline
        // and an outline at rule strength is lost in the fill beside it. The
        // reveal still fades in on `opacity: root.t`, so nothing is lost by the
        // border no longer tracking the open animation.
        border.color: Tokyo.paneEdge
        border.width: 1
        opacity: root.t
        // Rises the last 8px up into the pill it hangs from, fading as it goes.
        transform: Translate { y: (1 - root.t) * 8 }

        Column {
            id: content
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: root.padH; rightMargin: root.padH; topMargin: root.padV
            }
            spacing: 8

            // ---------- header ----------
            Item {
                width: parent.width
                height: 20

                Text {
                    anchors { left: parent.left; leftMargin: 4
                              verticalCenter: parent.verticalCenter }
                    text: "NOTIFICATIONS"
                    color: Tokyo.blue
                    font { family: Tokyo.fontFamily; pixelSize: 10
                           bold: true; letterSpacing: 1.5 }
                }
                PillButton {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    text: "CLEAR ALL"
                    accent: root.store !== null && root.store.entries.length > 0
                            ? Tokyo.dim : Tokyo.bgHighlight
                    onClicked: {
                        if (root.store !== null) root.store.clearAll()
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 1
                color: Tokyo.bgHighlight
            }

            // ---------- the list ----------
            ListView {
                id: list
                width: parent.width
                height: root.store === null || root.store.entries.length === 0
                        ? 0
                        : Math.min(root.store.entries.length, root.visibleRows) * root.rowH
                clip: true
                spacing: 4
                // Newest at the top, and the top is where the eye already is.
                model: root.store !== null ? root.store.entries : []
                boundsBehavior: Flickable.StopAtBounds

                // A delete leaves rather than blinking out: the row slides off
                // to the left and the ones below close the gap behind it. Both
                // motions are the ListView's own, so `dismiss()` still just
                // drops the entry — no per-row state to keep in sync.
                displaced: Transition {
                    NumberAnimation {
                        properties: "x,y"
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }
                remove: Transition {
                    NumberAnimation {
                        properties: "x"
                        to: -list.width
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        properties: "opacity"
                        to: 0
                        duration: 140
                    }
                }

                delegate: Rectangle {
                    id: entry
                    required property var modelData
                    required property int index
                    width: list.width
                    height: root.rowH - 4
                    // Deliberately still `pillRadius`, not the slab's own
                    // `popupRadius`: this row is an inner surface nested inside
                    // the panel, which is the relationship the launcher already
                    // has between `.launcher-panel` (20px) and its `.result-row`
                    // (12px) inside `.result-list`. A row that matched the slab's
                    // own corner radius would stop reading as a widget sitting in
                    // a panel and start reading as a second, smaller slab.
                    // `panelHover` rather than `pane`/`bgHighlight`: Tokyo.qml
                    // documents it as the hover for a `panelFill` surface.
                    radius: Tokyo.pillRadius
                    color: rowHover.containsMouse ? Tokyo.panelHover : Tokyo.panelFill
                    border.color: Tokyo.paneEdge
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 110 } }

                    NotifyIcon {
                        id: icon
                        anchors { left: parent.left; leftMargin: 6
                                  verticalCenter: parent.verticalCenter }
                        size: 36
                        // The live object when there is one, the record
                        // otherwise — NotifyIcon reads the same field names off
                        // both, and the live one is the fresher of the pair.
                        source: modelData.live !== null && modelData.live !== undefined
                                ? modelData.live : modelData
                        store: root.store
                    }

                    Column {
                        anchors {
                            left: icon.right; leftMargin: 10
                            right: dismiss.left; rightMargin: 6
                            top: parent.top; topMargin: 8
                        }
                        spacing: 2

                        Item {
                            width: parent.width
                            height: 12
                            Text {
                                id: app
                                anchors { left: parent.left; right: time.left
                                          rightMargin: 6; verticalCenter: parent.verticalCenter }
                                text: modelData.app
                                color: Tokyo.dim
                                elide: Text.ElideRight
                                font { family: Tokyo.fontFamily; pixelSize: 9
                                       letterSpacing: 0.8 }
                            }
                            Text {
                                id: time
                                anchors { right: parent.right
                                          verticalCenter: parent.verticalCenter }
                                text: root.ago(modelData.time)
                                color: Tokyo.dim
                                font { family: Tokyo.fontFamily; pixelSize: 9 }
                            }
                        }
                        Text {
                            width: parent.width
                            text: modelData.summary
                            color: modelData.urgency === 2 ? Tokyo.red : Tokyo.fg
                            elide: Text.ElideRight
                            font { family: Tokyo.fontFamily; pixelSize: 12; bold: true }
                        }
                        Text {
                            width: parent.width
                            visible: String(modelData.body || "") !== ""
                            text: modelData.body
                            color: Tokyo.dim
                            elide: Text.ElideRight
                            font { family: Tokyo.fontFamily; pixelSize: 10 }
                        }
                    }

                    // ---------- the row's own actions ----------
                    // Only while the notification is still live. Once the
                    // daemon has let go of it the action cannot be delivered to
                    // anyone, and a button that silently does nothing is worse
                    // than no button.
                    Flow {
                        id: acts
                        anchors { left: icon.right; leftMargin: 10
                                  bottom: parent.bottom; bottomMargin: 4 }
                        spacing: 4
                        visible: entry.hasLiveActions
                        height: visible ? 18 : 0

                        Repeater {
                            model: entry.hasLiveActions ? modelData.live.actions : []
                            delegate: Rectangle {
                                required property var modelData
                                width: aText.implicitWidth + 12
                                height: 18
                                radius: 5
                                color: aHover.containsMouse ? Tokyo.bgHighlight
                                                             : Qt.rgba(0, 0, 0, 0.2)
                                border.color: Tokyo.hairline
                                border.width: 1
                                Text {
                                    id: aText
                                    anchors.centerIn: parent
                                    text: modelData.text
                                    color: Tokyo.fg
                                    font { family: Tokyo.fontFamily; pixelSize: 9 }
                                }
                                MouseArea {
                                    id: aHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        modelData.invoke()
                                        root.store.dismiss(entry.modelData)
                                    }
                                }
                            }
                        }
                    }

                    // ---------- dismiss ----------
                    Rectangle {
                        id: dismiss
                        anchors { right: parent.right; rightMargin: 4
                                  verticalCenter: parent.verticalCenter }
                        width: 20; height: 20
                        radius: 5
                        // Always there, not on hover: a delete you have to find
                        // is a delete you do not use. `rowHover` already stops
                        // short of this rectangle, so it never eats the click.
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
                            onClicked: {
                                if (root.store !== null)
                                    root.store.dismiss(entry.modelData)
                            }
                        }
                    }

                    readonly property bool hasLiveActions: modelData.live !== null
                        && modelData.live !== undefined
                        && modelData.live.actions !== undefined
                        && modelData.live.actions.length > 0

                    MouseArea {
                        id: rowHover
                        anchors {
                            left: parent.left; leftMargin: 4
                            right: acts.visible ? acts.left : dismiss.left
                            top: parent.top
                            bottom: acts.visible ? acts.top : parent.bottom
                        }
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.launch(entry.modelData)
                    }
                }
            }

            // ---------- nothing here ----------
            Text {
                width: parent.width
                visible: root.store === null || root.store.entries.length === 0
                text: "Nothing yet. Notifications land here as they arrive."
                color: Tokyo.dim
                wrapMode: Text.WordWrap
                font { family: Tokyo.fontFamily; pixelSize: 10 }
            }
        }
    }

    /// Open a notification's app. The live object carries the client's id, which
    /// is what `gtk-launch` and `dex` both want; the record's appName is the
    /// fallback for a notification read back off disk.
    function launch(entry) {
        const id = entry.desktopEntry !== "" ? entry.desktopEntry
                   : String(entry.app || "").toLowerCase().replace(/\s+/g, "-")
        if (id === "") return
        Quickshell.execDetached(["gtk-launch", id])
    }

    /// "4m" / "2h" / "3d". Relative, and recomputed on open rather than stored,
    /// so a notification read on Tuesday is not labelled with Tuesday's
    /// arithmetic done on Sunday.
    function ago(t) {
        const s = Math.max(0, Math.floor((Date.now() - t) / 1000))
        if (s < 60) return s + "s"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }
}
