// SysFlyout.qml — click flyout for the combined gpu/cpu/ram pill.
//
// One tachometer per stat, ring = utilization, hole = the figure that dial is
// about: GPU allocates VRAM in the middle, CPU shows its current clock, RAM
// shows the same allocation in both (there is no second, separate number to
// ring for it). Under them, a DISK strip: what is left of / and what is moving
// across it, and under that the heaviest PROCESSES right now — one row per PID,
// sortable by CPU or memory, killable by clicking a row twice. Same popup shape
// as AudioFlyout: a grab-focus xdg_popup hung under the pill that opened it,
// with the bar's transparent 6px gap strip below.
import QtQuick
import Quickshell

PopupWindow {
    id: root

    visible: false
    grabFocus: true
    color: "transparent"

    /// the Sys.qml pill — read for the numbers, refreshed on open
    property var pill: null

    readonly property real gap: 6
    readonly property real padH: 8
    readonly property real padV: 8
    readonly property real cell: 132
    /// air between two dials. The card's width reserves room for it AND the
    /// Row spends it — one number, so the dials can't drift off-centre from
    /// the DISK strip and PROCESSES card, which both span the full width.
    readonly property real cellGap: 8
    /// air between the dials and the strip, and the strip's own height
    readonly property real diskGap: 12
    readonly property real diskH: 40

    /// ---------- processes ----------
    /// Which column the PROCESSES list is ordered by, "cpu" or "mem".
    property string sortKey: "cpu"
    /// The pid whose row is waiting for the second click, 0 for none. On the
    /// ROOT, not on the row: `procs` is reassigned every second and a Repeater
    /// rebuilds all its delegates on write, so a delegate holding the armed pid
    /// would lose it on the next poll, one second into a 4s confirm window.
    property int armedPid: 0

    readonly property int procRows: 10
    /// card padding, read by the card's own height binding
    readonly property real procPadV: 7
    /// name | cpu% | mem, in that order, sliced to the rows that fit
    readonly property var sortedProcs: {
        const all = root.pill === null ? [] : (root.pill.procs || [])
        // slice() first: Array.sort() sorts IN PLACE, and the array handed to us
        // is the live one from Sys.qml. Sorting it in place would reorder the
        // script's own output and, since the sort key can differ from the one
        // the script used, the "heaviest first" list would never come back.
        const copy = all.slice()
        const key = root.sortKey
        copy.sort((a, b) => key === "mem"
            ? (b.ram - a.ram) || (b.cpu - a.cpu)
            : (b.cpu - a.cpu) || (b.ram - a.ram))
        return copy.length > root.procRows ? copy.slice(0, root.procRows) : copy
    }

    /// First click arms, second click on the SAME row SIGTERMs it. Any other
    /// click, the 4s timeout, or closing the popup stands down.
    function requestKill(row) {
        if (root.armedPid === row.pid) {
            root.armedPid = 0
            // execDetached, not a Poll: the kill returns in milliseconds and
            // there is nothing to read back. SettingsFlyout.qml's power buttons
            // take the same route.
            Quickshell.execDetached([Tokyo.scriptDir + "/procs-kill.sh",
                                     String(row.pid), row.name])
            killSettle.start()
        } else {
            root.armedPid = row.pid
            killArm.restart()
        }
    }

    function disarm() {
        root.armedPid = 0
    }

    // A row armed and then armed on a different row is not a confirmation of
    // the first, so switching columns drops it.
    function sortBy(key) {
        root.sortKey = key
        root.disarm()
    }

    onVisibleChanged: if (!root.visible) root.disarm()

    implicitWidth: root.cell * 3 + root.cellGap * 2 + root.padH * 2
    implicitHeight: box.height + root.gap

    function toggleFor(item) {
        root.pill = item
        // A dial reading a sample from before the click is a dial showing a lie.
        if (!root.visible && root.pill !== null) root.pill.refresh()
        root.anchor.item = item
        root.anchor.edges = Edges.Bottom
        root.anchor.gravity = Edges.Bottom
        root.visible = !root.visible
    }

    Rectangle {
        id: box
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        // the dials, the disk strip, the air above it, and the process card
        height: row.implicitHeight + root.diskGap + root.diskH
                + root.diskGap + procCard.height + root.padV * 2
        color: Tokyo.bgDark
        radius: Tokyo.pillRadius
        border.color: Tokyo.bgHighlight
        border.width: 1

        Row {
            id: row
            anchors {
                left: parent.left; top: parent.top
                leftMargin: root.padH; topMargin: root.padV
            }
            spacing: root.cellGap

            // ---------- gpu: ring = utilization, middle = VRAM allocated ----------
            Column {
                width: root.cell
                spacing: 4

                Text {
                    width: parent.width
                    text: "GPU"
                    color: Tokyo.purple
                    horizontalAlignment: Text.AlignHCenter
                    font { family: Tokyo.fontFamily; pixelSize: 11; bold: true; letterSpacing: 1.5 }
                }
                Gauge {
                    width: root.cell
                    height: root.cell
                    accent: Tokyo.purple
                    value: root.pill ? root.pill.gpuUtil / 100 : 0
                    centerText: root.gpuVramText
                    caption: "VRAM"
                }
            }

            // ---------- cpu: ring = utilization, middle = current clock ----------
            Column {
                width: root.cell
                spacing: 4

                Text {
                    width: parent.width
                    text: "CPU"
                    color: Tokyo.cyan
                    horizontalAlignment: Text.AlignHCenter
                    font { family: Tokyo.fontFamily; pixelSize: 11; bold: true; letterSpacing: 1.5 }
                }
                Gauge {
                    width: root.cell
                    height: root.cell
                    accent: Tokyo.cyan
                    value: root.pill ? root.pill.cpuUtil / 100 : 0
                    centerText: root.clockText
                    caption: "CLOCK"
                }
            }

            // ---------- ram: allocation in the middle AND in the ring ----------
            Column {
                width: root.cell
                spacing: 4

                Text {
                    width: parent.width
                    text: "RAM"
                    color: Tokyo.green
                    horizontalAlignment: Text.AlignHCenter
                    font { family: Tokyo.fontFamily; pixelSize: 11; bold: true; letterSpacing: 1.5 }
                }
                Gauge {
                    width: root.cell
                    height: root.cell
                    accent: Tokyo.green
                    value: root.pill ? root.pill.ramPct / 100 : 0
                    centerText: root.ramText
                    caption: "USED"
                }
            }
        }

        // ---------- disk: free space, and what is moving across it ----------
        Rectangle {
            id: strip
            anchors {
                left: parent.left; right: parent.right; top: row.bottom
                leftMargin: root.padH; rightMargin: root.padH; topMargin: root.diskGap
            }
            height: root.diskH
            radius: Tokyo.pillRadius
            // `bg`, not `pane`: the popup's own fill is bgDark, so `pane`
            // (#394161) put a card almost 2 stops lighter than the surface it
            // sits on — brighter than the RAM dial's ring right above it. `bg`
            // (#1e2030) is one small step up from bgDark and reads as the same
            // widget, and `bgHighlight` for the border is a real step against
            // that fill, which is what makes the card a card.
            color: Tokyo.bg
            border.color: Tokyo.bgHighlight
            border.width: 1

            // Two separately anchored rows, not one row with a spacer between
            // them: the air between the free-space figure and the rates is
            // whatever is left after the text is measured, which is the width
            // the font actually renders at rather than a number guessed once.
            Row {
                anchors {
                    left: parent.left; verticalCenter: parent.verticalCenter
                    leftMargin: 10
                }
                spacing: 10

                Text {
                    text: "DISK"
                    color: Tokyo.yellow
                    font { family: Tokyo.fontFamily; pixelSize: 10; bold: true; letterSpacing: 1.5 }
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    spacing: 1
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: root.diskFreeText
                        color: Tokyo.yellow
                        font { family: Tokyo.fontFamily; pixelSize: 13; bold: true }
                    }
                    // The percentage is spelled out here rather than drawn as a
                    // fill bar: the strip is 376px of inner width, the two
                    // rates alone can take 200 of them, and a bar would only
                    // have repeated the number printed under it.
                    Text {
                        text: root.diskTotalText
                        color: Tokyo.dim
                        font { family: Tokyo.fontFamily; pixelSize: 9; letterSpacing: 1.2 }
                    }
                }
            }

            Row {
                anchors {
                    right: parent.right; verticalCenter: parent.verticalCenter
                    rightMargin: 10
                }
                spacing: 12

                Text {
                    text: root.diskRateText("\uf063", root.pill ? root.pill.diskRead : 0)
                    color: Tokyo.cyan
                    font { family: Tokyo.fontFamily; pixelSize: 12; bold: true }
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    // \uf063 / \uf062 are Font Awesome's arrow-down / arrow-up — the same
                    // set the rest of the bar draws from. Read is the download
                    // direction, so it takes the down arrow.
                    text: root.diskRateText("\uf062", root.pill ? root.pill.diskWrite : 0)
                    color: Tokyo.magenta
                    font { family: Tokyo.fontFamily; pixelSize: 12; bold: true }
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ---------- processes: the heaviest pids, sortable, killable ----------
        Rectangle {
            id: procCard
            anchors {
                left: parent.left; right: parent.right; top: strip.bottom
                leftMargin: root.padH; rightMargin: root.padH
                topMargin: root.diskGap
            }
            // Rows are a fixed 15px each, so the card's height is arithmetic on
            // the count rather than a binding on a Column's implicitHeight —
            // which would make the card resize every time the process count
            // changes, under the pointer.
            height: root.procPadV * 2 + procCol.implicitHeight
            // Same fill and border as the DISK strip above: two cards in a row
            // should read as the same widget twice, not as two kinds of card.
            color: Tokyo.bg
            border.color: Tokyo.bgHighlight
            border.width: 1
            radius: Tokyo.pillRadius

            // Behind everything (z: 0) and below the Column (z: 1), so a click
            // on the card's padding disarms an armed kill instead of falling
            // through to the popup.
            MouseArea {
                anchors.fill: parent
                onClicked: root.disarm()
            }

            Column {
                id: procCol
                z: 1
                anchors {
                    left: parent.left; right: parent.right; top: parent.top
                    leftMargin: 6; rightMargin: 6
                    topMargin: root.procPadV
                }
                spacing: 5

                // Header + the two sort buttons on one line. The sort state is
                // drawn as the column's own colour plus a caret, not just a
                // weight change: at 9px bold/regular is nearly invisible, and an
                // unmarked sort column looks identical to a dead one.
                Item {
                    id: procHead
                    width: parent.width
                    height: 12

                    Text {
                        anchors {
                            left: parent.left; verticalCenter: parent.verticalCenter
                        }
                        text: "PROCESSES"
                        color: Tokyo.yellow
                        font {
                            family: Tokyo.fontFamily; pixelSize: 10
                            bold: true; letterSpacing: 1.5
                        }
                    }

                    // The two sort buttons take the same column widths, right
                    // margins and spacing as the ProcRow below them (40/10/46),
                    // so each one sits flush over the numbers it sorts. Sized
                    // by the ROW's geometry rather than by what is left of it:
                    // the header used to be a right-anchored Row of
                    // natural-width labels, which put CPU a "MEM"'s width to
                    // the right of the cpu% column it heads.
                    Row {
                        anchors {
                            right: parent.right; verticalCenter: parent.verticalCenter
                        }
                        spacing: 10

                        Text {
                            width: 40
                            text: "CPU" + (root.sortKey === "cpu" ? " ▾" : "")
                            color: root.sortKey === "cpu" ? Tokyo.cyan : Tokyo.dim
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            font {
                                family: Tokyo.fontFamily; pixelSize: 9; bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sortBy("cpu")
                            }
                        }
                        Text {
                            width: 46
                            text: "MEM" + (root.sortKey === "mem" ? " ▾" : "")
                            color: root.sortKey === "mem" ? Tokyo.green : Tokyo.dim
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                            font {
                                family: Tokyo.fontFamily; pixelSize: 9; bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.sortBy("mem")
                            }
                        }
                    }
                }

                Repeater {
                    id: procList
                    model: root.sortedProcs
                    delegate: ProcRow {
                        width: procHead.width
                        height: 15
                    }
                }

                // Empty state rather than a bare gap: the pill was clicked in
                // the first second of startup, before procs.sh has written once.
                Text {
                    visible: procList.count === 0
                    width: parent.width
                    height: 15
                    text: "no processes"
                    color: Tokyo.dim
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font { family: Tokyo.fontFamily; pixelSize: 10 }
                }
            }
        }
    }

    // One row of the PROCESSES list. Inline component rather than a
    // `component ProcRow` inside the card so it is declared once at file scope,
    // the way SettingsFlyout.qml declares Toggle/Tile/DeviceRow.
    //
    // Column widths are anchored, never computed: `anchors.right` on a
    // QQuickAnchorLine has no usable numeric value, so `parent.width - x.right`
    // is NaN, the row lays out at width 0 and the text silently vanishes. Each
    // Text here therefore has an explicit `width` AND `elide`, so a long name
    // loses its tail instead of overflowing the card.
    component ProcRow: Item {
        id: row
        required property var modelData

        readonly property bool armed: root.armedPid === row.modelData.pid

        // The armed row tints and its name becomes a question, so the second
        // click is aimed at something that looks like a decision rather than at
        // an unchanged row.
        Rectangle {
            anchors.fill: parent
            anchors { leftMargin: -6; rightMargin: -6 }
            radius: 4
            color: row.armed ? Qt.rgba(0.85, 0.30, 0.35, 0.22) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        Text {
            id: nameText
            anchors {
                left: parent.left; right: cpuText.left
                verticalCenter: parent.verticalCenter
                rightMargin: 8
            }
            height: 14
            text: row.armed
                ? row.modelData.name + " (kill?)"
                : row.modelData.name
            color: row.armed ? Tokyo.red : Tokyo.fg
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignLeft
            font {
                family: Tokyo.fontFamily
                pixelSize: 11
                bold: row.armed
            }
        }

        Text {
            id: cpuText
            anchors {
                right: memText.left; verticalCenter: parent.verticalCenter
                rightMargin: 10
            }
            width: 40
            height: 14
            // >100 is real: a process burning three threads is over one core.
            // Elided rather than capped at 100 — a list that clamps cannot show
            // which of two processes is actually busier.
            text: row.modelData.cpu.toFixed(0) + "%"
            color: row.armed ? Tokyo.dim : Tokyo.cyan
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            font { family: Tokyo.fontFamily; pixelSize: 10 }
        }

        Text {
            id: memText
            anchors {
                right: parent.right; verticalCenter: parent.verticalCenter
            }
            width: 46
            height: 14
            text: Math.round(row.modelData.ram) + "M"
            color: row.armed ? Tokyo.dim : Tokyo.green
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            font { family: Tokyo.fontFamily; pixelSize: 10 }
        }

        MouseArea {
            anchors.fill: parent
            anchors { leftMargin: -6; rightMargin: -6 }
            cursorShape: Qt.PointingHandCursor
            onClicked: root.requestKill(row.modelData)
        }
    }

    // Two deferred beats, both borrowed from Settings.qml's `confirm`/`settle`
    // pair: 4s to change your mind about a kill, 900ms for the kill to have
    // actually removed the row before the next poll.
    Timer {
        id: killArm
        interval: 4000
        onTriggered: root.disarm()
    }
    Timer {
        id: killSettle
        interval: 900
        onTriggered: if (root.pill) root.pill.refresh()
    }

    // VRAM total is worth the pixels only while the card is reporting it.
    readonly property string gpuVramText: root.pill === null
        ? "-"
        : (root.pill.gpuVram > 0
              ? root.pill.gpuVram + "/" + root.pill.gpuVramTotal + " GB"
              : "n/a")

    readonly property string clockText: root.pill === null || root.pill.cpuGhz <= 0
        ? "-"
        : root.pill.cpuGhz.toFixed(2) + " GHz"

    readonly property string ramText: root.pill === null
        ? "-"
        : root.pill.ramUsed.toFixed(1) + " GB"

    // GB to one decimal below 100, whole above it: "9.8 GB" while it is moving,
    // "718 GB" once the decimal is noise on a 26px-tall strip.
    function gbText(gb) {
        return gb >= 100 ? Math.round(gb) : gb.toFixed(1)
    }

    /// "718 GB FREE", and "OF 841 GB (15%)" under it — the total and the
    /// percentage together, because either alone leaves a division to do.
    readonly property string diskFreeText: root.pill === null
        ? "-"
        : gbText(root.pill.diskFree) + " GB FREE"

    readonly property string diskTotalText: root.pill === null
        ? ""
        : "OF " + gbText(root.pill.diskTotal) + " GB (" + Math.round(root.pill.diskPct) + "%)"

    /// One rate, with its glyph: B/s under a KiB, then KiB/s, MiB/s, GiB/s —
    /// the same ladder and the same "B vs iB" spelling `network-monitor.sh`'s
    /// `format_rate` uses for the link rates, so a 3 MiB/s download and a
    /// 3 MiB/s disk write read identically on two panels.
    function diskRateText(glyph, bytesPerSec) {
        if (bytesPerSec < 1024) return glyph + " " + Math.round(bytesPerSec) + " B/s"
        if (bytesPerSec < 1048576) return glyph + " " + (bytesPerSec / 1024).toFixed(1) + " KiB/s"
        if (bytesPerSec < 1073741824) return glyph + " " + (bytesPerSec / 1048576).toFixed(1) + " MiB/s"
        return glyph + " " + (bytesPerSec / 1073741824).toFixed(1) + " GiB/s"
    }
}
