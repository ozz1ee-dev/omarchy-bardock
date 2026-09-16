import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Visual-only drag feedback while a docked icon is being dragged back onto the
// bar: the icon under the cursor plus the bar's own insertion marker geometry
// (bar.dropMarkerRect). The input region stays empty so the popup keeps the
// pointer grab.
PanelWindow {
  id: ghostWindow

  required property var ghostScreen

  property bool active: false
  property url imageUrl: ""
  property real ghostX: 0
  property real ghostY: 0
  property int ghostWidth: 27
  property int ghostHeight: 26
  property var markerRect: null
  property color foreground: "#ffffff"
  property string glyph: ""
  property string fontFamily: ""
  property color barBackground: "transparent"

  readonly property bool screenMatches: !ghostScreen || (screen !== null && screen.name === ghostScreen.name)
  readonly property int padding: Style.space(1)

  visible: active && screenMatches
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "ozz1ee-bardock-drag-ghost"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  mask: Region {}

  Item {
    visible: ghostWindow.visible
    x: Math.round(ghostWindow.ghostX - ghostWindow.ghostWidth / 2)
    y: Math.round(ghostWindow.ghostY - ghostWindow.ghostHeight / 2)
    width: ghostWindow.ghostWidth + ghostWindow.padding * 2
    height: ghostWindow.ghostHeight + ghostWindow.padding * 2

    Rectangle {
      anchors.fill: parent
      color: ghostWindow.barBackground
      border.width: 1
      border.color: ghostWindow.foreground
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: 0.94
    }

    Image {
      anchors.fill: parent
      anchors.margins: ghostWindow.padding
      visible: String(ghostWindow.imageUrl) !== ""
      source: ghostWindow.imageUrl
      fillMode: Image.Stretch
      smooth: true
      opacity: 0.84
    }

    // No grabbed bitmap (grabToImage never answers from the popup window): the
    // widget's own icon character, on a plate that matches the bar.
    Text {
      anchors.centerIn: parent
      visible: String(ghostWindow.imageUrl) === ""
      text: ghostWindow.glyph
      textFormat: Text.PlainText
      color: ghostWindow.foreground
      font.family: ghostWindow.fontFamily
      font.pixelSize: Style.font.icon
    }
  }

  Rectangle {
    readonly property var target: ghostWindow.markerRect

    visible: ghostWindow.visible && target !== null
    x: target ? Math.round(target.x) : 0
    y: target ? Math.round(target.y) : 0
    width: target ? Math.round(target.width) : 0
    height: target ? Math.round(target.height) : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
  }
}
