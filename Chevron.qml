import QtQuick
import QtQuick.Shapes
import qs.Commons

// The whole mark is the arrowhead: two strokes meeting at the tip, no shaft.
// Closed points down (things are tucked away below the bar), open points up.
Item {
  id: root

  property color color: Color.foreground
  property bool open: false
  property real thickness: 1.5

  readonly property real markWidth: Style.space(11)
  readonly property real markHeight: Style.space(6)
  readonly property real half: root.thickness / 2

  implicitWidth: root.markWidth
  implicitHeight: root.markHeight

  Shape {
    id: mark
    anchors.centerIn: parent
    width: Math.ceil(root.markWidth)
    height: Math.ceil(root.markHeight)
    rotation: root.open ? 180 : 0
    antialiasing: true

    Behavior on rotation {
      NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      PathPolyline {
        path: [
          Qt.point(root.half, root.half),
          Qt.point(mark.width / 2, mark.height - root.half),
          Qt.point(mark.width - root.half, root.half)
        ]
      }
    }
  }
}
