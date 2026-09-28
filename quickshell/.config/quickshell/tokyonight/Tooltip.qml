// Tooltip.qml — hover tooltip popup styled like the waybar `tooltip` CSS rule.
//
//   tooltip { background-color: #16161e; border: 1px solid #2f334d;
//             border-radius: 8px; color: #c8d3f5; }
//
// One instance per bar (created in Bar.qml); every module shares it through
// `tooltipHost`. Anchored below the hovered module via PopupAnchor.item.
// The 6px gap is transparent padding at the popup's top — avoids QML Margins
// struct assignment issues.
import QtQuick
import Quickshell

PopupWindow {
    id: root

    visible: false
    color: "transparent"

    readonly property real gap: 6
    readonly property real padH: 20
    readonly property real padV: 14

    property string text: ""

    implicitWidth: label.implicitWidth + padH
    implicitHeight: label.implicitHeight + padV + gap

    Rectangle {
        id: box
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: root.height - gap
        color: Tokyo.bgDark
        radius: Tokyo.pillRadius
        border.color: Tokyo.bgHighlight
        border.width: 1

        Text {
            id: label
            anchors { fill: parent; margins: 7 }
            text: root.text
            color: Tokyo.fg
            font { family: Tokyo.fontFamily; pixelSize: Tokyo.fontSize }
            wrapMode: Text.NoWrap
        }
    }

    /// anchor below the given item and show the tooltip
    function showFor(item, txt) {
        root.text = txt
        root.anchor.item = item
        root.anchor.edges = Edges.Bottom
        root.anchor.gravity = Edges.Bottom
        root.visible = true
    }

    function hide() {
        root.visible = false
    }
}