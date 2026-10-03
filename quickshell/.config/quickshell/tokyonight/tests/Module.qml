// Module.qml — a Tokyo Night "pill" module.
//
// Geometry matches waybar: radius 8, vertical margin 4px inside a 34px bar
// (so 26px tall), horizontal padding 0 12px, gap between pills 12px
// (3px module margins + 6px bar spacing, GTK box semantics).
//
// Hover behavior is opt-in via `hoverStyle` because waybar only defines
// hover rules for #workspaces (and #taskbar) buttons — the generic pill
// modules like #clock/#cpu stay visually unchanged on hover.
import QtQuick

Rectangle {
    id: root

    // ---------- content ----------
    property string text: ""
    property string tooltip: ""          // shown in the shared Tooltip popup on hover
    property color fg: Tokyo.fg
    property color bg: Tokyo.pillBg

    /// Coloured spans in a row, instead of `text`: a list of { text, color }.
    /// For a pill standing for more than one stat, where each of them keeps the
    /// accent it had as a pill of its own (Sys.qml: gpu purple, cpu cyan, ram
    /// green). One label and one `fg` cannot say that.
    property var fragments: []

    // opt-in hover styling (waybar #workspaces / #taskbar buttons)
    property bool hoverStyle: false
    property color hoverBg: Tokyo.bgHighlight
    property color hoverFg: Tokyo.cyan

    // when false the module ignores hover entirely (e.g. the tray counter)
    property bool interactive: true

    property int hPad: Tokyo.pillHPad

    /// extra letter spacing on the label (waybar `letter-spacing`).
    /// Default 0.2: Pango rounds each glyph advance to an integer pixel at 1x
    /// (JetBrains Mono: 7.8 -> 8.0) while Qt lays out the exact 7.8px, leaving
    /// every pill ~0.2px/char narrower than waybar. Adding 0.2 gives the same
    /// 8.0px advance per glyph. Modules with an explicit waybar letter-spacing
    /// (e.g. date) override this.
    property real letterSpacing: 0.2

    property bool hovered: false
    /// OR'd into `hovered` for the look of it. The pointer can be somewhere this
    /// module cannot hear about: a flyout's own surface is drawn on top of the
    /// pill that opened it, so the bar's MouseArea gets nothing at all while the
    /// panel is up and the widget that opened it cools off under the cursor.
    /// The host module binds this to "its flyout is open" — see Clock.qml, the
    /// only user: the other flyouts' pills are not covered by anything.
    property bool hoveredExtra: false
    /// What the paint reads. Nothing should test `hovered` for appearance —
    /// a module can be lit by a flag the MouseArea never set.
    readonly property bool lit: hovered || hoveredExtra

    // ---------- events ----------
    /// button is one of Qt.LeftButton / Qt.RightButton / Qt.MiddleButton
    signal clicked(int button)
    /// vertical scroll delta (angleDelta.y), e.g. volume control
    signal wheelTick(int yDelta)
    signal hoverChanged(bool hovering)

    implicitHeight: Tokyo.pillHeight
    implicitWidth: (root.fragments.length > 0 ? fragRow.implicitWidth : label.implicitWidth)
                   + hPad * 2
    radius: Tokyo.pillRadius
    color: (interactive && hoverStyle && lit) ? hoverBg : bg
    Behavior on color {
        ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    Text {
        id: label
        anchors.centerIn: parent
        visible: root.fragments.length === 0
        text: root.text
        color: (interactive && hoverStyle && lit) ? root.hoverFg : root.fg
        font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize; letterSpacing: root.letterSpacing }
        Behavior on color {
            ColorAnimation { duration: 150; easing.type: Easing.OutQuad }
        }
    }

    Row {
        id: fragRow
        anchors.centerIn: parent
        spacing: 10
        Repeater {
            model: root.fragments
            delegate: Text {
                required property var modelData
                // a fragment with `visible: false` drops out and the row closes
                // the gap — the net pill is two icons that are not both there
                visible: modelData.visible !== false
                text: modelData.text ?? ""
                color: (root.interactive && root.hoverStyle && root.lit) ? root.hoverFg
                                                                       : (modelData.color ?? root.fg)
                font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize; letterSpacing: root.letterSpacing }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onEntered: {
            if (!root.interactive) return
            root.hovered = true
            root.hoverChanged(true)
        }
        onExited: {
            root.hovered = false
            root.hoverChanged(false)
        }
        onClicked: m => root.clicked(m.button)
        onWheel: w => root.wheelTick(w.angleDelta.y)
    }

    // tooltip wiring (shared popup passed from Bar)
    property var tooltipHost: null
    onHoverChanged: hovering => {
        if (tooltipHost === null) return
        if (hovering && root.tooltip !== "") tooltipHost.showFor(root, root.tooltip)
        else tooltipHost.hide()
    }

    // Network metrics update while the pointer remains over a pill. Keep an
    // already-open tooltip synchronized instead of showing the first sample
    // until the pointer leaves and re-enters.
    onTooltipChanged: {
        if (!lit || tooltipHost === null || root.tooltip === "")
            return
        tooltipHost.showFor(root, root.tooltip)
    }
}