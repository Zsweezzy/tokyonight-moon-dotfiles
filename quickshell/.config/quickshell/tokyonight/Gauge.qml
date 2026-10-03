// Gauge.qml — one tachometer: a track arc, a value arc, and the number the
// dial is about in the hole. The ring is always the utilization; `centerText`
// is whatever that number means for this stat (VRAM, clock, RAM used).
//
// 270° of sweep with the gap at the BOTTOM, so the dial reads the way a
// speedometer does: 0 at the bottom-left, 100% at the bottom-right, the empty
// quarter pointing straight down.
//
// Qt measures an angle from +x and counts positive turns CLOCKWISE on screen
// (y grows downward), which is what makes this number 135 and not 225. From
// 135° the arc runs 180° (left), 270° (up), 0° (right) and stops at 45°
// (down-right); the quarter it skips, 45°→135°, is exactly the bottom. From
// 225° — which reads like the same dial on paper — the gap lands on the LEFT.
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    /// 0..1 — how much of the sweep is filled
    property real value: 0
    /// the number in the hole
    property string centerText: ""
    /// what that number is, under it
    property string caption: ""
    property color accent: Tokyo.cyan
    property real thickness: 9

    readonly property real startAngle: 135
    readonly property real sweep: 270

    implicitWidth: 124
    implicitHeight: 124

    Shape {
        id: ring
        anchors.fill: parent

        // A 270° arc is one long slanted curve, so its whole legibility rests on
        // how the edges get resolved. CurveRenderer strokes the path on the GPU
        // with analytic coverage instead of tessellating it into a polygon, and
        // the 4x MSAA layer covers the case where the surface these flyouts are
        // mapped onto has no multisampling of its own — without it the arc reads
        // as a staircase rather than a smooth sweep.
        preferredRendererType: Shape.CurveRenderer
        layer.enabled: true
        layer.samples: 4

        readonly property real radius: Math.min(ring.width, ring.height) / 2 - root.thickness

        ShapePath {
            strokeWidth: root.thickness
            strokeColor: Tokyo.bgHighlight
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: root.startAngle
                sweepAngle: root.sweep
            }
        }

        ShapePath {
            strokeWidth: root.thickness
            strokeColor: root.accent
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                id: valueArc
                centerX: ring.width / 2
                centerY: ring.height / 2
                radiusX: ring.radius
                radiusY: ring.radius
                startAngle: root.startAngle
                sweepAngle: root.sweep * Math.max(0, Math.min(1, root.value))
                // Samples land a second apart; this is what makes that read as a
                // needle settling rather than a number teleporting.
                Behavior on sweepAngle {
                    NumberAnimation {
                        duration: 450
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: 2

        Text {
            width: parent.width
            text: root.centerText
            color: root.accent
            horizontalAlignment: Text.AlignHCenter
            font {
                family: Tokyo.fontFamily
                pixelSize: 15
                bold: true
            }
        }
        Text {
            width: parent.width
            text: root.caption
            color: Tokyo.dim
            horizontalAlignment: Text.AlignHCenter
            font {
                family: Tokyo.fontFamily
                pixelSize: 9
                letterSpacing: 1.2
            }
        }
    }
}
