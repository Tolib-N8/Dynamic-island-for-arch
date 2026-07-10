import QtQuick
import QtQuick.Shapes

// OpenAgentIsland: concave "shoulder" fillet that flows the notch pill into the
// top screen edge — ported from the island's RoundCorner widget (top corners
// only, no qs dependencies).
Item {
    id: root

    // true → the fillet curves toward the LEFT of the pill (sits on the pill's
    // left side, i.e. a TopRight-style concave corner); false → right side.
    property bool leftSide: true
    property int size: 20
    property color color: "#000000"

    implicitWidth: size
    implicitHeight: size

    Shape {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            id: p
            strokeWidth: 0
            fillColor: root.color
            startX: root.leftSide ? root.size : 0
            startY: 0
            PathAngleArc {
                moveToStart: false
                centerX: root.size - p.startX
                centerY: root.size
                radiusX: root.size
                radiusY: root.size
                startAngle: root.leftSide ? -90 : 180
                sweepAngle: root.leftSide ? 90 : 90
            }
            PathLine { x: p.startX; y: p.startY }
        }
    }
}
