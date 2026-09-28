// PillButton.qml — the small flat button used by the timer surfaces.
//
// Not a QtQuick.Controls button: the flyouts avoid the Basic/Fusion style
// themes (each style ships its own metrics and focus ring) and paint the few
// controls they need, the way AudioFlyout and BrightnessFlyout already do.
// Look: translucent accent fill, accent text, radius 6, 22px tall.
import QtQuick
import Quickshell

Rectangle {
    id: root

    property string text: ""
    /// leading Nerd Font glyph, e.g. "\uf017"
    property string glyph: ""
    property color accent: Tokyo.blue

    /// brief flash on hover-out is not wanted; hover just brightens
    property bool hovered: false

    signal clicked()

    implicitHeight: 22
    implicitWidth: label.implicitWidth + 20
    radius: 6
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.hovered ? 0.30 : 0.16)
    opacity: root.enabled ? 1 : 0.4
    Behavior on color {
        ColorAnimation { duration: 120; easing.type: Easing.OutQuad }
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4

        Text {
            visible: root.glyph !== ""
            text: root.glyph
            color: root.accent
            font { family: Tokyo.fontFamily; pixelSize: 11 }
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            id: label
            visible: root.text !== ""
            text: root.text
            color: root.accent
            font { family: Tokyo.fontFamily; pixelSize: 11; bold: true; letterSpacing: 0.5 }
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        onEntered: root.hovered = true
        onExited: root.hovered = false
        onClicked: root.clicked()
    }
}
