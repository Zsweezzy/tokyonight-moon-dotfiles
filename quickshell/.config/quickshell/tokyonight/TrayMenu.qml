// TrayMenu.qml — SNI right-click menus rendered like the audio flyout instead
// of as a native platform menu.
//
// Fed by QsMenuOpener from the tray item's QsMenuHandle (SystemTrayItem.menu);
// every QsMenuEntry renders as a row with the flyout's row language (bgDark
// panel, pillRadius, bgHighlight border, bgHighlight row hover, check mark in
// green). Rows with children open a nested flyout to the right on click
// (click-to-open — no hover timing to get wrong), and the close-chain logic
// collapses the whole stack on activation or on an outside click.
//
// Positioning mirrors the old platform menu's anchoring for the root
// (edges=Bottom, gravity=Bottom, margins.bottom=-2 → the -2 offset plus the
// popup's own 6 px strip reproduces the ~8 px gap below the cell), and uses a
// top-right corner anchor for submenus (edges=Top|Right + gravity=Right|Bottom
// + margins.right=-4 → flush under the parent row, extending right, with a
// small gap so the borders don't merge).
import QtQuick
import QtQuick.Layouts
import Quickshell

PopupWindow {
    id: root

    /// QsMenuHandle to render. A QsMenuEntry also works — it subclasses
    /// QsMenuHandle, which is how a submenu flyout renders an entry's children.
    property var menuHandle: null

    /// set on submenu flyouts: the flyout that opened us
    property var parentFlyout: null
    /// the currently open submenu flyout, and which row opened it
    property var subFlyout: null
    property var subOwnerRow: null
    /// reentrancy guard for hideAll() → onVisibleChanged → childDismissed chains
    property bool closing: false

    visible: false
    grabFocus: true
    color: "transparent"

    // ---- flyout geometry (mirrors AudioFlyout.qml) ----
    // gap is the transparent strip above the panel: PopupAnchor grows the popup
    // downward from the anchor line, and the panel is anchored to the popup's
    // bottom, so the panel visually floats `gap` px below the cell.
    readonly property real gap: 6
    readonly property real padH: 10
    readonly property real padV: 8
    readonly property int rowH: 30
    readonly property real panelW: 220

    implicitWidth: root.panelW
    implicitHeight: box.height + root.gap

    QsMenuOpener {
        id: opener
        menu: root.menuHandle
    }

    // ---------------- placement ----------------
    // side "below": under the bar cell, matching the old platform menu's spot.
    // side "right": submenu — anchored at the row's top-right corner, growing
    // right and down from it (its left edge meets the row's right edge).
    function showFor(item, side) {
        root.anchor.item = item
        if (side === "right") {
            root.anchor.margins.bottom = 0
            root.anchor.margins.right = -4
            root.anchor.edges = Edges.Top | Edges.Right
            root.anchor.gravity = Edges.Right | Edges.Bottom
        } else {
            root.anchor.margins.right = 0
            // -2 margin + the popup's own 6 px strip = the ~8 px gap the old
            // platform menu had below the cell
            root.anchor.margins.bottom = -2
            root.anchor.edges = Edges.Bottom
            root.anchor.gravity = Edges.Bottom
        }
        root.visible = true
    }

    // ---------------- closing ----------------
    // collapse this flyout and everything under it. The parent nulls its
    // subFlyout reference first, so a sub's hideAll can't trigger a
    // chain-up through childDismissed while we're already tearing down.
    function hideAll() {
        if (root.closing) return
        root.closing = true
        if (root.subFlyout) {
            const s = root.subFlyout
            root.subFlyout = null
            root.subOwnerRow = null
            s.hideAll()
        }
        root.visible = false
        root.closing = false
    }

    // a leaf entry was activated: bubble up to the top of the chain, collapse
    // everything from there.
    function itemActivated() {
        if (root.parentFlyout) root.parentFlyout.itemActivated()
        else root.hideAll()
    }

    // a submenu was dismissed on its own (grabFocus → click outside): collapse
    // the whole chain from here up so nothing lingers.
    function childDismissed(sub) {
        if (root.subFlyout === sub) {
            root.subFlyout = null
            root.subOwnerRow = null
        }
        root.hideAll()
    }

    onVisibleChanged: {
        if (!root.visible) {
            // reset every row's submenu holder so a stale submenu can't re-open
            // when this menu is shown again
            for (let i = 0; i < entries.count; i++) {
                const d = entries.itemAt(i)
                if (d && d.subOpen) d.subOpen = false
            }
            if (root.parentFlyout && !root.closing) {
                // hidden by grabFocus, not by hideAll() — collapse the chain up
                root.parentFlyout.childDismissed(root)
            }
        }
    }

    // open/close the submenu of a row that has children (click toggles it;
    // clicking a different parent row swaps the submenu). Closing also
    // deactivates the row's holder so the next click builds a fresh sub.
    function toggleSub(row, entry) {
        if (root.subFlyout) {
            const sameRow = root.subOwnerRow === row
            const s = root.subFlyout
            const owner = root.subOwnerRow
            root.subFlyout = null
            root.subOwnerRow = null
            s.hideAll()
            if (owner) owner.subOpen = false
            if (sameRow) return
        }
        row.subOpen = true
    }

    // ---------------- the panel ----------------
    Rectangle {
        id: box
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: content.implicitHeight + root.padV * 2
        width: root.panelW
        color: Tokyo.bgDark
        radius: Tokyo.pillRadius
        border.color: Tokyo.bgHighlight
        border.width: 1

        Column {
            id: content
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: root.padH; rightMargin: root.padH; topMargin: root.padV
            }
            spacing: 2

            Repeater {
                id: entries
                model: opener.children

                delegate: Rectangle {
                    required property var modelData
                    readonly property bool sep: !!modelData && !!modelData.isSeparator
                    readonly property bool enabled: !!modelData && !!modelData.enabled
                    readonly property bool hasKids: !!modelData && !!modelData.hasChildren

                    id: row
                    property bool subOpen: false

                    width: parent.width
                    height: row.sep ? 7 : root.rowH
                    // Clamped, because the separator row is 7 px and a radius of 6
                    // is more than half of it: 6 reads on a 30 px row and renders
                    // a 7 px one as a lozenge.
                    radius: Math.min(6, height / 2)
                    // hover highlight like the audio flyout's rows; disabled
                    // entries never light up (their text is dimmed instead)
                    color: row.sep || !row.enabled || !mouse.containsMouse
                        ? "transparent" : Tokyo.bgHighlight

                    // separator: a thin rule centered in a short row
                    Rectangle {
                        visible: row.sep
                        anchors {
                            left: parent.left; right: parent.right
                            leftMargin: 4; rightMargin: 4
                            verticalCenter: parent.verticalCenter
                        }
                        height: 1
                        color: Tokyo.bgHighlight
                    }

                    // the menu item: icon, label, check/radio state, submenu chevron
                    RowLayout {
                        visible: !row.sep
                        anchors {
                            left: parent.left; right: parent.right
                            leftMargin: 8; rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        Image {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            visible: row.modelData ? row.modelData.icon !== "" : false
                            source: row.modelData ? row.modelData.icon : ""
                            sourceSize: Qt.size(18, 18)
                            fillMode: Image.PreserveAspectFit
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData ? row.modelData.text : ""
                            elide: Text.ElideRight
                            color: row.enabled ? Tokyo.fg : Tokyo.trayGlyph
                            font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
                            verticalAlignment: Text.AlignVCenter
                        }
                        // check/radio indicator — reserves space only for rows
                        // that are actually checkable, so plain items sit flush
                        Text {
                            Layout.preferredWidth: (row.modelData
                                && row.modelData.buttonType !== QsMenuButtonType.None) ? 16 : 0
                            text: row.modelData
                                && row.modelData.buttonType !== QsMenuButtonType.None
                                && row.modelData.checkState === Qt.Checked
                                ? (row.modelData.buttonType === QsMenuButtonType.RadioButton
                                   ? "\uf192" : "\uf00c") // dot-circle / check
                                : ""
                            color: Tokyo.green
                            font { family: Tokyo.fontFamily; pixelSize: 12 }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            Layout.preferredWidth: row.hasKids ? 12 : 0
                            text: row.hasKids ? "\uf054" : "" // chevron-right
                            color: Tokyo.trayGlyph
                            font { family: Tokyo.fontFamily; pixelSize: 11 }
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            if (row.sep) return
                            if (row.hasKids) {
                                if (row.enabled) root.toggleSub(row, row.modelData)
                            } else if (row.enabled) {
                                row.modelData.triggered()
                                root.itemActivated()
                            }
                        }
                    }

                    // submenu flyout, created lazily when this row opens one
                    Loader {
                        id: subLoader
                        active: row.subOpen
                        source: "TrayMenu.qml"
                        onLoaded: {
                            const sub = subLoader.item
                            sub.menuHandle = row.modelData
                            sub.parentFlyout = root
                            sub.showFor(row, "right")
                            root.subFlyout = sub
                            root.subOwnerRow = row
                        }
                    }
                }
            }
        }
    }
}