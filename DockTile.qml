import QtQuick
import qs.Commons
import "Model.js" as Model

// One docked icon. The real widget component comes from the bar's own registry
// (bar.barWidgetRegistry), instantiated here with the same three properties the
// bar injects into a slot, so a docked widget keeps its clicks, its popovers and
// its timers. Widgets that render nothing (several report 0x0 until they have
// data) fall back to a labelled plate instead of an empty cell.
//
// The entry arrives as a plain property rather than a `required` delegate role:
// a required property redeclared in the delegate instantiation shadows the
// component's own and leaves it uninitialized, which fails the whole delegate.
Item {
  id: tile

  property var entry: null
  property QtObject barHost: null
  property var registry: null
  property int cellSize: 46
  property color foreground: "#000000"
  property string fontFamily: ""
  // Where docked widgets point their own popups. Their panels position
  // themselves from `anchorItem`'s window, so an anchor inside this little square
  // window puts every panel in the top-left corner of the screen. Pointing the
  // anchor at the chevron (a bar item) makes them open where a bar widget's would.
  property var anchorHost: null

  // Stay on the widget's own face instead of guessing with a timer: whatever the
  // widget reads from its service or its settings can arrive after load.
  Connections {
    target: widgetLoader.item
    ignoreUnknownSignals: true
    function onVisibleChanged() { tile.decideFace() }
    function onImplicitWidthChanged() { tile.decideFace() }
    function onImplicitHeightChanged() { tile.decideFace() }
  }

  // The drawer opening is the moment the tree becomes measurable. The call lands
  // after the surface is up, so the widget already reports its real size.
  Timer {
    id: faceTimer
    interval: 80
    repeat: false
    onTriggered: tile.decideFace()
  }

  // Opening the drawer makes the widget measurable; closing it says nothing.
  onVisibleChanged: {
    if (visible) faceTimer.start()
  }
  property bool draggingTile: false
  // Whether the pointer handler inside this tile still owns a gesture. The dock
  // watches this to tell a live drag from an orphaned one.
  readonly property bool pointerActive: pointer.active
  property bool reorderTarget: false
  property string itemProbe: ""
  // Shared with the dock: widget id -> whether it has a face, remembered across
  // tile rebuilds. Docking an icon rebuilds the tiles after it, and a fresh tile
  // whose widget is still loading has nothing to show yet.
  property var faceMemory: null
  // Whether a measurement has actually concluded for the widget currently loaded.
  // The label plate is only for widgets that really have none, so it must not
  // appear while the widget is loading or being re-measured: that was the flash of
  // plugin names when an icon was dropped into the drawer.
  property bool faceChecked: false
  // Whether the widget has a face to show. Decided only while the drawer is
  // drawn (QML's `visible` reads *effective* visibility, so any measurement taken
  // in a hidden tree is a lie) and remembered in between.
  property bool faceVisible: false

  signal dragStarted(string id, real x, real y, int ghostWidth, int ghostHeight)
  signal dragMoved(string id, real x, real y)
  signal dragFinished(string id, real x, real y, bool dragged)

  readonly property string tileId: Model.entryId(entry)
  readonly property string registryKey: barHost && typeof barHost.canonicalWidgetId === "function"
    ? barHost.canonicalWidgetId(tileId)
    : tileId
  readonly property var registryEntry: {
    if (!registry) return null
    if (registry[registryKey]) return registry[registryKey]
    return registry[tileId] || null
  }
  readonly property var widgetComponent: registryEntry ? registryEntry.component : null
  readonly property var metadata: registryEntry ? registryEntry.metadata : null
  readonly property string label: metadata && metadata.displayName
    ? String(metadata.displayName)
    : Model.displayLabel(tileId)
  readonly property bool liveLoaded: widgetLoader.item !== null
  readonly property real liveWidth: widgetLoader.item ? (widgetLoader.item.implicitWidth || 0) : 0
  readonly property real liveHeight: widgetLoader.item ? (widgetLoader.item.implicitHeight || 0) : 0
  readonly property bool liveVisible: liveLoaded && tile.faceVisible
  readonly property real naturalWidth: widgetLoader.item ? (widgetLoader.item.implicitWidth || 1) : 1
  readonly property real fitScale: naturalWidth > cellSize * 0.86 ? (cellSize * 0.86) / naturalWidth : 1

  property url ghostUrl: ""

  width: cellSize
  height: cellSize

  // A widget can be on the bar with no face at all: uptime hides itself while
  // every watched site answers, an integration with nothing to show reports 0x0.
  // On the bar that is the point; in the drawer the icon was asked for, so the
  // hidden face is revealed - and a face is also what makes the icon clickable,
  // since the widget's own MouseArea is inside it. Only this instance is
  // touched: the bar builds a fresh one with its binding intact.
  property int revealCalls: 0

  // Read the widget's face as it is right now (the load-time probe is only a
  // snapshot, so reordering or revealing would not show up in it).
  function probeNow() {
    var item = widgetLoader.item
    if (!item) return "no-item"
    try {
      var chain = []
      var cur = item
      var depth = 0
      while (cur && depth < 8) {
        var nm = String(cur).indexOf("(") > 0 ? String(cur).split("(")[0] : String(cur)
        chain.push(nm + " v=" + (cur.visible === undefined ? "n/a" : cur.visible) + " op=" + (cur.opacity === undefined ? "?" : cur.opacity))
        cur = cur.parent
        depth += 1
      }
      return JSON.stringify({
        chain: chain,
        visible: item.visible,
        iw: Math.round(item.implicitWidth),
        ih: Math.round(item.implicitHeight),
        w: Math.round(item.width),
        h: Math.round(item.height),
        reveals: tile.revealCalls
      })
    } catch (e) {
      return "probeNow error: " + String(e)
    }
  }

  // One reading of 0x0 is not proof of no face: docking an icon changes the grid
  // (the column count follows the icon count), so every tile is relaid out and a
  // widget can report nothing for a frame. That single reading used to flip a
  // widget from its face to its name - the flash of plugin names when an icon
  // landed in the drawer. A "no face" reading is therefore re-checked before it is
  // believed, and any positive reading wins immediately.
  Timer {
    id: faceSettle
    interval: 120
    repeat: false
    property int tries: 0
    onTriggered: {
      var hasFace = tile.measureFace()
      if (hasFace === null) { stop(); return }
      if (hasFace === true || tries >= 3) {
        stop()
        tile.commitFace(hasFace === true)
        return
      }
      tries += 1
      restart()
    }
  }

  // A rebuilt tile starts from what the dock remembers about this widget, so a
  // known icon never falls back to its name for the frames the widget is loading.
  function seedFace() {
    if (!tile.faceMemory) return
    var remembered = tile.faceMemory[tile.tileId]
    if (remembered === undefined) {
      tile.faceChecked = false
      return
    }
    tile.faceChecked = true
    tile.faceVisible = remembered === true
  }

  Component.onCompleted: seedFace()
  onEntryChanged: seedFace()

  // Read the widget's size as it is right now. null means there is nothing to
  // measure yet (no item, or the drawer is not drawn: measurements in a hidden
  // tree are a lie because QML's `visible` is effective visibility).
  function measureFace() {
    var item = widgetLoader.item
    if (!item) return null
    if (tile.visible !== true) return null
    // A widget that hides itself while everything is healthy (uptime with
    // hideWhenHealthy) has no face and therefore nothing to click. In the drawer
    // the icon was asked for, so give it one. Only this instance: the bar builds
    // its own when the icon goes home.
    if (item.visible === false) item.visible = true
    var width = item.implicitWidth > 0 ? item.implicitWidth : item.width
    var height = item.implicitHeight > 0 ? item.implicitHeight : item.height
    return width > 0 && height > 0
  }

  function commitFace(hasFace) {
    tile.faceVisible = hasFace
    tile.faceChecked = true
    if (tile.faceMemory) tile.faceMemory[tile.tileId] = hasFace
  }

  function decideFace() {
    var hasFace = measureFace()
    if (hasFace === null) return
    tile.revealCalls += 1

    if (hasFace === true) {
      faceSettle.stop()
      faceSettle.tries = 0
      tile.commitFace(true)
      return
    }
    // A widget we believe has a face keeps it until several readings agree that
    // it is gone; a widget with no face is labelled at once.
    if (tile.faceVisible === true && !faceSettle.running) {
      faceSettle.tries = 0
      faceSettle.start()
      return
    }
    if (!faceSettle.running) tile.commitFace(false)
  }

  function injectWidget() {
    var item = widgetLoader.item
    if (!item) return
    if ("bar" in item) item.bar = tile.barHost
    if ("moduleName" in item) item.moduleName = tile.tileId
    if ("settings" in item) item.settings = tile.entry
    if (tile.anchorHost) tile.retargetAnchors(item, 8)
    faceTimer.start()
  }

  // A docked widget builds its popup somewhere below itself and hands it an
  // `anchorItem` of its own. Re-pointing that at the chevron keeps the panel
  // maths identical to the bar's (same window, same screen edge).
  property int anchorsRetargeted: 0

  function retargetAnchors(item, depth) {
    if (!item || depth <= 0) return
    // `data`, not `children`: a widget's panel is a PanelWindow (a window, so not
    // a visual child) and only shows up among the object's data.
    var kids = item.data
    if (!kids || kids.length === undefined) kids = item.children
    if (!kids) return
    for (var i = 0; i < kids.length; i++) {
      var kid = kids[i]
      if (!kid) continue
      if ("anchorItem" in kid) {
        try {
          kid.anchorItem = tile.anchorHost
          tile.anchorsRetargeted += 1
        } catch (e) { }
      }
      tile.retargetAnchors(kid, depth - 1)
    }
  }

  // The drag ghost shows this glyph instead of a grabbed bitmap: grabToImage on
  // an item inside the popup window never completes (its callback does not run),
  // so the ghost draws the widget's own icon character.
  readonly property string glyph: tile.liveLoaded && ("text" in widgetLoader.item)
    ? String(widgetLoader.item.text || "")
    : ""

  Rectangle {
    id: plate
    anchors.fill: parent
    anchors.margins: Style.space(1)
    radius: Math.max(2, Style.cornerRadius)
    color: hover.hovered ? Style.hoverFillFor(tile.foreground, tile.foreground) : "transparent"
    border.width: tile.reorderTarget ? Math.max(1, Style.space(1)) : 0
    border.color: Color.accent
  }

  // The icon being dragged dims, so the cell it will land in reads clearly.
  opacity: tile.draggingTile ? 0.35 : 1

  Behavior on opacity {
    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
  }

  Loader {
    id: widgetLoader
    anchors.centerIn: parent
    active: tile.widgetComponent !== null
    // Never hide the widget by making its ancestor invisible: QML's `visible`
    // reads *effective* visibility, and widgets like uptime compute their face
    // from it (`implicitWidth: visible ? button.implicitWidth : 0`). Hiding the
    // loader would leave such a widget reporting 0x0 for ever and the tile would
    // fall back to a label. Fade it instead: opacity does not touch visibility.
    visible: true
    opacity: tile.liveVisible ? 1 : 0
    sourceComponent: tile.widgetComponent
    scale: tile.fitScale
    onLoaded: {
      tile.faceChecked = false
      tile.injectWidget()
    }
  }

  Text {
    anchors.fill: parent
    anchors.margins: Style.space(3)
    // No component at all means the widget is not available: name it at once.
    // Otherwise wait for a concluded measurement, so a loading tile shows a bare
    // cell rather than flashing the plugin name.
    visible: tile.widgetComponent === null ? true : (tile.faceChecked && !tile.faceVisible)
    text: tile.label
    textFormat: Text.PlainText
    color: tile.foreground
    font.family: tile.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    wrapMode: Text.WordWrap
    maximumLineCount: 3
    elide: Text.ElideRight
  }

  HoverHandler {
    id: hover
  }

  // A DragHandler, not a MouseArea: a MouseArea sitting on top of the widget
  // swallows every click, so the icon could be dragged but never pressed. The
  // handler only takes the grab once the pointer moves past the drag threshold,
  // which leaves plain clicks to the widget's own MouseArea underneath.
  DragHandler {
    id: pointer
    target: null
    acceptedButtons: Qt.LeftButton
    dragThreshold: Style.space(4)
    // Take the drag away from the widget's own MouseArea once the pointer really
    // moves; leave it alone otherwise so clicks keep working.
    grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType

    property bool dragging: false

    function scenePoint(position) {
      return pointer.parent.mapToItem(null, position.x, position.y)
    }

    onActiveChanged: {
      if (active) {
        dragging = true
        var start = scenePoint(centroid.position)
        tile.dragStarted(tile.tileId, start.x, start.y, Math.ceil(tile.width), Math.ceil(tile.height))
        return
      }
      if (!dragging) return
      dragging = false
      var released = scenePoint(centroid.position)
      tile.dragFinished(tile.tileId, released.x, released.y, true)
    }

    onCentroidChanged: {
      if (!dragging) return
      var moved = scenePoint(centroid.position)
      tile.dragMoved(tile.tileId, moved.x, moved.y)
    }

    onCanceled: {
      dragging = false
      tile.dragFinished(tile.tileId, 0, 0, false)
    }
  }
}
