// SysFlyout.qml — click flyout for the combined gpu/cpu/ram pill.
//
// One tachometer per stat, ring = utilization, hole = the figure that dial is
// about: GPU allocates VRAM in the middle, CPU shows its current clock, RAM
// shows the same allocation in both (there is no second, separate number to
// ring for it). Under them, a DISK strip: what is left of / and what is moving
// across it. Same popup shape as AudioFlyout: a grab-focus xdg_popup hung
// under the pill that opened it, with the bar's transparent 6px gap strip below.
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
    readonly property real padH: 16
    readonly property real padV: 14
    readonly property real cell: 132
    /// air between the dials and the strip, and the strip's own height
    readonly property real diskGap: 12
    readonly property real diskH: 40

    implicitWidth: root.cell * 3 + root.padH * 2
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
        // the dials, plus the disk strip and the air above it
        height: row.implicitHeight + root.diskGap + root.diskH + root.padV * 2
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
            spacing: 8

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
