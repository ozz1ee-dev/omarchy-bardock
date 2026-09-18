import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "Compat.js" as Compat

// A chevron in the corner of the bar and a square dock behind it.
//
// Docking an icon does not disable its plugin: the entry moves out of
// bar.layout.* into the top-level plugins[] array, which PluginRegistry counts
// as enabled, so the widget keeps a live component in bar.barWidgetRegistry --
// the component the square renders. Deleting the entry instead would unregister
// it and the square would come up empty.
//
// Undocking is the reverse, and is done by dragging: the bar's own drag
// machinery never reaches outside its own window, so a drag that starts in the
// square draws its own ghost and hit-tests root.hostSlots itself.
BarWidget {
  id: root
  moduleName: "ozz1ee.bardock"

  // ---- settings ------------------------------------------------------------
  readonly property int cell: Math.round(Model.clamp(Number(setting("cell", 46)), 28, 96))
  readonly property int minSide: Math.round(Model.clamp(Number(setting("minSide", 168)), 120, 800))
  // Cells may shrink below `cell` when a lot of icons have to fit the screen; this
  // is how small they are allowed to get.
  readonly property int minCell: Math.round(Model.clamp(Number(setting("minCell", 20)), 8, 96))
  // 0 means "as big as the screen allows" - there is no cap on the drawer itself.
  readonly property int userSideCap: Math.round(Model.clamp(Number(setting("maxSide", 0)), 0, 4000))
  readonly property bool dockOnDrop: setting("dockOnNeighbourDrop", true) !== false
  readonly property int armMs: Math.round(Model.clamp(Number(setting("armMs", 2500)), 300, 10000))

  // widget id -> whether the widget has a face, shared with the tiles so a rebuilt
  // tile does not flash its plugin name while its widget is loading.
  property var faceMemory: ({})

  // Last-resort guard for a drag whose release never reached us: a drag that has
  // not moved for this long is not a drag. It is deliberately generous, because a
  // real hand pauses while aiming - cancelling that was a regression. The orphan
  // check below is what normally clears a lost drag, and it fires immediately.
  readonly property int dragStallMs: Math.round(Model.clamp(Number(setting("dragStallMs", 10000)), 1000, 60000))
  // A release within this margin around the chevron docks. The drawer itself only
  // opens on the chevron, so a generous margin here is safe: it makes the drop easy
  // to hit without the drawer popping up during an ordinary bar drag.
  readonly property int dockZoneSlack: Math.round(Model.clamp(Number(setting("dockZoneSlack", 32)), 0, 400))

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- host API generation -------------------------------------------------
  // Omarchy 4.0.0-4.0.2 injects the real bar object into a third-party widget;
  // 4.0.3 replaced it with capability-scoped facades (PluginBarApi /
  // PluginShellApi) that carry no shell config, no widget catalogue and no slot
  // geometry. Every host access below goes through Compat, so one code path
  // serves both generations. Detection asks for the members we use, never for a
  // version string - see Compat.js.
  readonly property bool legacyHost: Compat.hasLegacyHost(bar)
  readonly property bool hostConfig: Compat.hasHostConfig(bar)
  // Our own service instance is the only route to the widget catalogue on 4.0.3+
  // (see Service.qml); on 4.0.0-4.0.2 the bar carries it directly.
  readonly property var ownService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var ownServiceRegistry: ownService && ownService.barWidgetRegistry
    ? ownService.barWidgetRegistry : null

  // The whole shell.json: bar.layout for the bar, plugins[] for what is parked.
  readonly property var config: hostConfig ? bar.shell.shellConfig : shellConfigFile.document
  readonly property var layout: Model.layoutOf(config)
  readonly property var registryWidgets: Compat.catalogue(bar, ownServiceRegistry)

  ConfigFile { id: shellConfigFile }

  // Who writes the config: the host when it hands us the document, the file
  // otherwise. 4.0.3+ has mutateShellConfig, but it answers `false` for a widget
  // without the `bar` kind, so the facade is never treated as a writer.
  readonly property bool canWrite: hostConfig || shellConfigFile.ready

  function mutate(mutator) {
    if (!root.canWrite) return false
    if (root.hostConfig) {
      bar.shell.mutateShellConfig(mutator)
      return true
    }
    return shellConfigFile.mutate(mutator)
  }

  // Bar geometry the drop zone is hit-tested against, and the drag state the bar
  // publishes while the user drags an icon along it. 4.0.3+ exposes neither, so
  // the drag-to-dock gesture is legacy-only and these stay empty there.
  readonly property var hostSlots: legacyHost && bar.moduleSlots ? bar.moduleSlots : []
  readonly property var hostDragSource: legacyHost && bar.barDragSource ? bar.barDragSource : null
  readonly property var hostDragTarget: legacyHost && bar.barDragTarget ? bar.barDragTarget : null
  readonly property real hostDragX: legacyHost && bar.barDragScreenX !== undefined ? bar.barDragScreenX : 0
  readonly property real hostDragY: legacyHost && bar.barDragScreenY !== undefined ? bar.barDragScreenY : 0

  function hostDropMarkerRect(slot, after) {
    return legacyHost && bar.dropMarkerRect ? bar.dropMarkerRect(slot, after) : null
  }

  function hostNextVisibleName(region, name, ownSlot) {
    return legacyHost && bar.nextVisibleModuleName ? bar.nextVisibleModuleName(region, name, ownSlot) : ""
  }

  // ---- dock picker (the generations without slot geometry) ------------------
  // Without slot geometry an icon cannot be dragged onto the chevron any more, so
  // the drawer offers what is on the bar instead: right-click the chevron (or
  // `omarchy-shell ozz1ee.bardock picker`) opens the list, one click docks.
  property bool pickerOpen: false
  readonly property bool pickerAvailable: bar !== null && !root.legacyHost
  readonly property var dockableIds: Compat.dockableIds(
    bar ? bar.layoutConfig : null,
    moduleName,
    Model.dockedIds(config, moduleName))

  readonly property var dockedList: Model.visibleDocked(config, moduleName)
  readonly property int dockedCount: dockedList.length

  // ---- square popup --------------------------------------------------------
  property bool popupOpen: false

  readonly property int popupMargin: Style.gapsOut
  readonly property int popupInset: Style.spacing.popupPadding * 2

  // The drawer grows with its contents and is only ever stopped by the screen: the
  // largest square that fits between the bar and the bottom edge is the ceiling,
  // with `maxSide` as an optional user cap on top of it (0 = no cap).
  readonly property int drawerBound: {
    var screen = dockSurface.screen
    var barHeight = bar ? bar.barSize : Style.bar.sizeHorizontal
    var room = screen
      ? Math.min(screen.width, screen.height - barHeight) - 2 * popupMargin
      : 420
    var bound = userSideCap > 0 ? Math.min(room, userSideCap) : room
    return Math.max(minSide, Math.round(bound))
  }

  readonly property var drawerGrid: Model.drawerGrid(Math.max(1, dockedCount), cell, minCell, drawerBound, popupInset)
  readonly property int popupSide: drawerGrid.side
  readonly property int popupColumns: drawerGrid.columns
  readonly property int popupRows: drawerGrid.rows
  // What the tiles are actually drawn at: the setting, or smaller when the screen
  // is the thing running out.
  readonly property int cellUsed: drawerGrid.cell

  function openPopup() { popupOpen = true }
  function closePopup() {
    if (dragActive) return
    popupOpen = false
    pickerOpen = false
  }
  function togglePopup() { popupOpen ? closePopup() : openPopup() }

  // PopupCard's owner protocol (outside click, popout switching).
  function close() { closePopup() }
  function closeForPopoutSwitch() { closePopup() }

  // ---- what we intended, and did it stick ---------------------------------
  // shell.json writes are asynchronous and the shell re-reads the file, so a
  // second write issued right after a drop can be overtaken by the first one and
  // the icon comes back. The intent is therefore remembered until the config
  // agrees, with a bounded number of retries.
  property string intentKind: ""
  property string intentId: ""
  property string intentSection: ""
  property string intentBefore: ""
  property int intentTries: 0
  // A write is optimistic in memory, so the first check can pass while the file
  // is still being rewritten. Only after a few consecutive checks does the
  // intent count as settled.
  property int intentChecks: 0

  // A dock decided at release is not written from here: the bar rebuilds its widget
  // instances when the layout changes, so anything kept in this instance (a timer, a
  // latch) is destroyed before it can run. The decision goes into our own entry as a
  // pending dock instead, and whichever instance exists next settles it - see
  // markPendingDock / settlePendingDock.

  readonly property bool intentPending: intentKind !== ""

  Timer {
    id: intentTimer
    interval: 1200
    onTriggered: root.settleIntent()
  }

  property int intentIndex: -1

  function rememberIntent(kind, id, section, beforeName, index) {
    intentKind = kind
    intentId = String(id)
    intentSection = String(section || "")
    intentBefore = String(beforeName || "")
    intentIndex = (index === undefined || index === null) ? -1 : Math.round(Number(index))
    intentTries = 1
    intentChecks = 0
    intentTimer.restart()
  }

  function intentSatisfied() {
    if (intentKind === "reorder") {
      return Model.dockedIds(config, moduleName).indexOf(intentId) === intentIndex
    }
    var where = Model.findEntry(config, intentId)
    if (intentKind === "dock") return where !== null && where.kind === "plugin"
    if (intentKind === "undock") return where !== null && where.kind === "bar"
    return true
  }

  function settleIntent() {
    if (!intentPending) return

    if (!intentSatisfied()) {
      intentChecks = 0
      if (intentTries >= 5) {
        console.log("bardock: gave up on " + intentKind + " " + intentId + " after " + intentTries + " tries")
        intentKind = ""
        intentId = ""
        intentTries = 0
        return
      }
      intentTries += 1
      console.log("bardock: re-applying " + intentKind + " " + intentId + " (try " + intentTries + ")")
      if (intentKind === "dock") dock(intentId)
      else if (intentKind === "reorder") reorder(intentId, intentIndex)
      else undock(intentId, intentSection, intentBefore)
      intentTimer.restart()
      return
    }

    intentChecks += 1
    if (intentChecks < 3) {
      intentTimer.restart()
      return
    }
    intentKind = ""
    intentId = ""
    intentTries = 0
    intentChecks = 0
  }

  // ---- dock / undock -------------------------------------------------------
  // Keep a decided dock in the config until it actually lands.
  function markPendingDock(id) {
    if (!root.canWrite) return false
    var ok = false
    root.mutate(function(document) {
      ok = Model.setPendingDock(document, root.moduleName, id)
    })
    return ok
  }

  function clearPendingDock(id) {
    if (!root.canWrite) return false
    root.mutate(function(document) {
      Model.clearPendingDock(document, root.moduleName)
    })
    return true
  }

  // Finish a dock that was decided earlier: run at every instance start (the bar
  // rebuilds widgets on a layout change, so the instance that decided the dock is
  // usually gone), and again after every config change as a free retry.
  function settlePendingDock() {
    var id = Model.pendingDock(root.config, root.moduleName, 6000)
    if (!id) return false
    if (Model.dockedIds(root.config, root.moduleName).indexOf(id) !== -1) {
      root.clearPendingDock(id)
      return false
    }
    console.log("bardock: settling a pending dock of " + id)
    return root.dock(id)
  }

  function dock(id) {
    if (!root.canWrite) {
      return false
    }
    var moved = false
    root.mutate(function(document) {
      moved = Model.dockInto(document, root.moduleName, id) !== null
      Model.sweepDockMarkers(document, root.moduleName)
      Model.clearPendingDock(document, root.moduleName)
    })
    console.log("bardock: dock " + id + " moved=" + moved)
    if (moved) root.rememberIntent("dock", id, "", "")
    return moved
  }

  // `beforeName` empty means "at the end of that section".
  function undock(id, section, beforeName) {
    if (!root.canWrite) return false
    var moved = false
    root.mutate(function(document) {
      moved = Model.undockFrom(document, root.moduleName, id, section, beforeName) !== null
      Model.sweepDockMarkers(document, root.moduleName)
    })
    console.log("bardock: undock " + id + " moved=" + moved + " before=" + beforeName)
    if (moved) root.rememberIntent("undock", id, section, beforeName)
    return moved
  }

  // One write for the whole thing: a mutate per entry reloads the shell config
  // per entry and the IPC call can outlive its own timeout.
  // Drag inside the square: docked[] is the draw order, so moving the id in that
  // list is the whole operation.
  function reorder(id, index) {
    if (!root.canWrite) return false
    var moved = false
    root.mutate(function(document) {
      moved = Model.reorderDocked(document, root.moduleName, id, index)
    })
    console.log("bardock: reorder " + id + " -> " + index + " moved=" + moved)
    if (moved) root.rememberIntent("reorder", id, "", "", index)
    return moved
  }

  function undockAll() {
    var ids = Model.dockedIds(config, moduleName)
    if (ids.length === 0) return 0
    if (!root.canWrite) return 0
    root.mutate(function(document) {
      while (Model.dockedIds(document, root.moduleName).length > 0) {
        var next = Model.dockedIds(document, root.moduleName)[0]
        Model.undockFrom(document, root.moduleName, next, "right", "")
      }
    })
    return ids.length
  }

  // ---- the chevron as the bar's own drop target ----------------------------
  readonly property var ownSlot: {
    if (!bar || !root.hostSlots) return null
    var slots = root.hostSlots
    for (var i = 0; i < slots.length; i++) {
      var slot = slots[i]
      if (slot && slot.activeItem === root) return slot
    }
    return null
  }

  readonly property bool barDragOverMe: !!(bar && root.hostDragTarget && ownSlot !== null && root.hostDragTarget === ownSlot)
  // The widget the bar is dragging right now (its source slot's id). Read while
  // the drag hovers the chevron: the bar clears it on release, before it writes
  // the new layout, so this is the only moment the id is available.
  readonly property string dragSourceName: {
    if (!bar || !root.hostDragSource) return ""
    return String(root.hostDragSource.moduleName || "")
  }
  // The slot the bar resolved the current drag to. It is cleared on release, so
  // the last non-empty value is where the drop landed.
  readonly property string dragTargetName: {
    if (!bar || !root.hostDragTarget) return ""
    return String(root.hostDragTarget.moduleName || "")
  }
  property string lastDropTarget: ""

  // Only a live bar drag makes these signals mean anything: at startup (or after the
  // bar rebuilds itself) a stale drag target would otherwise arm a dock that nobody
  // asked for, and the next unrelated config write would dock that widget.
  readonly property bool barDragLive: !!(bar && root.hostDragSource)
  onDragTargetNameChanged: if (dragTargetName !== "" && root.barDragLive) lastDropTarget = dragTargetName
  onDragSourceNameChanged: {
    // A new drag starts: forget the previous drop so a stale target can never
    // dock something on a later, unrelated config write.
    if (dragSourceName !== "") {
      lastDropTarget = ""
      pendingDockId = ""
    }
  }

  readonly property bool barDragInFlight: !!(bar && root.hostDragSource) && !barDragOverMe

  // The bar publishes the drag's pointer position while it runs and clears
  // everything on release, so both the id being dragged and the release point are
  // latched here and used to decide the drop.
  readonly property var barDragPoint: (bar && root.hostDragSource)
    ? { x: root.hostDragX, y: root.hostDragY }
    : null
  property string barDragId: ""
  property real barDragX: 0
  property real barDragY: 0

  onBarDragPointChanged: {
    if (!barDragPoint) return
    barDragId = dragSourceName
    barDragX = barDragPoint.x
    barDragY = barDragPoint.y

    // Only the chevron itself opens the drawer; anything else on the bar stays an
    // ordinary drag. Once open it stays open across the whole drop zone, so moving
    // from the chevron down into the square keeps the target alive.
    var point = { x: barDragX, y: barDragY }
    var onChevron = Model.pointInAnyRect(point, openZoneRects())
    var canDrop = Model.pointInAnyRect(point, dockZoneRects())
    if (onChevron && !popupOpen) openPopup()
    else if (!canDrop && popupOpen && !dragActive) closePopup()
  }

  readonly property var ownSlotScreenRect: {
    var slot = root.ownSlot
    var window = barWindow()
    if (!slot || !window || !window.contentItem) return null
    var scene = { x: slot.x, y: slot.y }
    try { scene = slot.mapToItem(null, 0, 0) } catch (e) { }
    var screen = bar && typeof bar.windowScreenPoint === "function"
      ? bar.windowScreenPoint(scene, window)
      : scene
    return {
      x: screen.x,
      y: screen.y,
      width: Math.max(root.slotWidth, Math.round(slot.width)),
      height: Math.max(1, Math.round(slot.height))
    }
  }

  // Two thresholds, deliberately different:
  //   - the DROP zone (dockZoneRects) is the chevron's slot plus `dockZoneSlack`, and
  //     the open drawer. This is the target the user actually aims at, so it has to be
  //     forgiving: a release a few pixels off the glyph still docks.
  //   - the OPEN trigger (openZoneRects) is the chevron's slot alone. Popping the
  //     drawer open while an icon is dragged along the bar disrupts reordering, so the
  //     drawer only appears once the dragged icon is really on the chevron.
  // A release outside the drop zone is an ordinary bar drop.
  function dockZoneRects() {
    return zoneRectsWith(root.dockZoneSlack)
  }

  function openZoneRects() {
    return zoneRectsWith(0)
  }

  function zoneRectsWith(slack) {
    var slotRect = ownSlotScreenRect
    if (!slotRect) return []
    var window = barWindow()
    var screenWidth = window ? window.width : slotRect.x + slotRect.width
    var square = (root.popupOpen && squareCard.width > 0)
      ? {
        x: squareCard.x + root.surfaceOrigin.x,
        y: squareCard.y + root.surfaceOrigin.y,
        width: squareCard.width,
        height: squareCard.height
      }
      : null
    return Model.dockZoneRects(slotRect.x, slotRect.y, slotRect.width, slotRect.height,
      screenWidth, square, slack)
  }

  // The drop half of the bar's drag: the bar's own nearest-slot resolution is
  // ignored on purpose, because it snaps to whichever slot is nearest - so this
  // decides from the release point instead, and only a release over the chevron (or
  // in the open drawer) docks.
  function finishBarDrag(id, screenX, screenY) {
    var wanted = String(id || "")
    root.barDragId = ""
    if (wanted === "" || wanted === root.moduleName) return false
    if (!root.dockOnDrop) return false
    if (!Model.isOnBar(root.config, wanted)) return false
    if (!Model.pointInAnyRect({ x: screenX, y: screenY }, dockZoneRects())) return false
    // Decide now, and leave the decision in our own entry: the bar writes the layout
    // right after the release and rebuilds the widget instances, so anything we keep
    // in memory (a timer, a latch) is gone by the time the write would happen. The
    // marker is read by whichever instance exists next, including the fresh one.
    root.markPendingDock(wanted)
    root.settlePendingDock()
    return true
  }

  // The bar publishes its drag state only on the generations that inject the real
  // bar. A Connections whose target cannot resolve the handler name logs a QML
  // warning on every rebuild, so the element is only built where it can work.
  Loader {
    active: root.legacyHost

    sourceComponent: Component {
      Connections {
        target: root.bar
        function onBarDragSourceChanged() {
          if (root.bar && root.hostDragSource) return
          if (root.barDragId !== "") root.finishBarDrag(root.barDragId, root.barDragX, root.barDragY)
        }
      }
    }
  }
  // The chevron is a bar slot, and a bar slot is the only thing the bar will
  // drop onto - so the slot itself is the drop target. Its width is fixed on
  // purpose: an earlier revision grew it while a drag was in flight, which moved
  // every neighbouring slot out from under the cursor and made reordering icons on
  // the bar feel unreliable. The landing pad below is a highlight only, drawn
  // inside the same width, so nothing on the bar ever shifts.
  readonly property int baseWidth: Style.space(34)
  // `testDrag` is a terminal seam: the landing pad highlight only shows while the
  // bar is dragging, which a script cannot start without a mouse.
  property bool testDrag: false
  // The pad is a highlight, not a resize: it only shows when a drop here would
  // actually dock - the bar is dragging something and the pointer is inside the
  // dock zone (the chevron's slot plus `dockZoneSlack`, or the drawer). The slot
  // itself keeps `baseWidth`, so no other slot on the bar ever moves.
  readonly property bool dragNear: barDragInFlight && bar
    && Model.pointInAnyRect({ x: root.hostDragX, y: root.hostDragY }, dockZoneRects())
  readonly property bool padShown: dragNear || barDragOverMe || testDrag
  readonly property int slotWidth: baseWidth

  property bool armed: false
  property string pendingDockId: ""
  property var previousIds: []
  property string previousSection: ""
  // The host injects `bar` after this widget completes, so the baseline layout
  // cannot be read at startup: seed it as soon as the bar is there, and only
  // ever move it forward from inside handleConfigChange().
  property bool seeded: false
  property int configChanges: 0
  property string lastLanded: ""

  Timer {
    id: armTimer
    interval: root.armMs
    onTriggered: root.armed = false
  }

  onBarDragOverMeChanged: {
    if (barDragOverMe && barDragLive) {
      // The square opens under the cursor so the drop has somewhere to land.
      // Which widget is coming is knowable only now: the bar drops its drag
      // state on release, before it writes the layout.
      armed = true
      pendingDockId = dragSourceName
      armTimer.restart()
      // The bar's nearest-slot resolution can point at this slot while the pointer is
      // still over the neighbouring icon, and opening the drawer there is what used to
      // disturb reordering. Open only when the pointer itself is on the chevron.
      if (!popupOpen && Model.pointInAnyRect({ x: root.hostDragX, y: root.hostDragY }, openZoneRects())) {
        openPopup()
      }
      return
    }
    // The drag moved off the chevron onto another slot: whatever gets dropped
    // now is not going into the dock.
    if (barDragInFlight) {
      armed = false
      pendingDockId = ""
    }
  }

  // Anything that stops moving is not a drag: this is the second half of the freeze
  // fix, so a lost release heals itself instead of holding the desktop hostage.
  // A drag with no live pointer behind it is an orphan: the tile that owned the
  // gesture is gone (rebuilt mid-drag) or the release was lost. Clearing it is what
  // unfreezes the desktop, and unlike a "it stopped moving" timer it cannot fire
  // while the user is simply holding still with the button down.
  function anyTileDragging() {
    for (var i = 0; i < tileRepeater.count; i++) {
      var item = tileRepeater.itemAt(i)
      if (item && item.pointerActive === true) return true
    }
    return false
  }

  Timer {
    id: orphanCheck
    interval: 250
    repeat: true
    running: root.dragActive
    onTriggered: {
      if (!root.dragActive) return
      if (root.anyTileDragging()) return
      console.log("bardock: drag has no pointer behind it, clearing it")
      root.reset("orphan")
    }
  }

  Timer {
    id: dragWatchdog
    interval: root.dragStallMs
    onTriggered: {
      if (!root.dragActive) return
      console.log("bardock: drag idle for " + root.dragStallMs + "ms, clearing it")
      root.reset("stall")
    }
  }

  onDragScreenXChanged: if (dragActive) dragWatchdog.restart()
  onDragScreenYChanged: if (dragActive) dragWatchdog.restart()

  // Everything a lost pointer release can leave behind, undone in one call. Also
  // the escape hatch from a terminal: `omarchy-shell ozz1ee.bardock reset` works
  // even when the desktop looks frozen, because it needs no pointer.
  function reset(reason) {
    var wasDragging = dragActive
    dragWatchdog.stop()
    resetDockDrag()
    armed = false
    pendingDockId = ""
    barDragId = ""
    testDrag = false
    // Only writable properties here: `barDragOverMe` and `barDragInFlight` are
    // readonly bindings onto the bar, and assigning to one throws, which used to
    // abort this function halfway (leaving the drawer open).
    closePopup()
    console.log("bardock: reset (wasDragging=" + wasDragging + ", reason=" + (reason || "?") + ")")
  }

  function refreshSnapshot() {
    var document = root.config
    var own = document ? Model.findEntry(document, moduleName) : null
    var onBar = own && own.kind === "bar"
    root.previousSection = onBar ? own.section : ""
    // Read the layout off the same document findEntry just looked at: the
    // bound `layout` property can still hold an older value while a change is
    // being processed, and an empty baseline would blind the drop detection.
    var entries = onBar ? Model.sectionEntries(Model.layoutOf(document), own.section) : []
    root.previousIds = Model.idsOf(entries)
    root.seeded = onBar && root.previousIds.length > 0
  }

  // The only place the snapshot moves forward. Keeping it out of a separate
  // onConfigChanged handler matters: that handler runs first and would record
  // the post-drop layout as "previous", so the drop would look like no change.
  function handleConfigChange() {
    var document = root.config
    if (!document) return
    if (!root.seeded) {
      root.refreshSnapshot()
      return
    }
    root.configChanges += 1

    // Who was dragged: the id read off the bar's drag while it hovered the
    // chevron (`pendingDockId`), or - for a widget arriving from another section
    // - the single new id that landed beside us. Whether it counts is decided by
    // one thing only: the bar's drop resolved to this slot.
    var candidate = root.pendingDockId
    if (candidate === "" && root.previousSection !== "") {
      candidate = Model.landedAdjacentTo(document, root.moduleName, root.previousIds)
    }
    var landed = Model.droppedOnChevron(document, root.moduleName, root.previousIds, candidate, root.lastDropTarget)
      ? candidate
      : ""
    root.lastLanded = landed
    root.lastDropTarget = ""
    root.pendingDockId = ""
    console.log("bardock: config change #" + root.configChanges
      + " section=" + root.previousSection
      + " previousIds=" + root.previousIds.length
      + " landed=\"" + landed + "\"")

    var own = Model.findEntry(document, root.moduleName)
    var onBar = own && own.kind === "bar"
    root.previousSection = onBar ? own.section : ""
    root.previousIds = onBar ? Model.idsOf(Model.sectionEntries(Model.layoutOf(document), own.section)) : []

    if (landed !== "" && root.dockOnDrop) {
      root.armed = false
      armTimer.stop()
      // Deferred on purpose: this handler runs inside the shell's own file-change
      // callback, and a shell.json write issued from there is lost (the shell's
      // FileView is busy with the write that triggered us). Let it settle first.
      root.markPendingDock(landed)
      root.settlePendingDock()
      return
    }

    // A widget the bar put back on its own (dragged out of the square and left
    // there, or restored by hand) must not stay in docked[] as well.
    if (root.canWrite
        && Model.needsPrune(document, root.moduleName)) {
      root.mutate(function(next) {
        Model.pruneDocked(next, root.moduleName)
      })
    }
  }

  // Same rule for the config signal: only the real ShellRoot has it. On 4.0.3+
  // the ConfigFile's own file watcher is what reports a change (onConfigChanged).
  Loader {
    active: root.hostConfig

    sourceComponent: Component {
      Connections {
        target: root.bar.shell
        function onShellConfigChanged() { root.handleConfigChange() }
      }
    }
  }

  Component.onCompleted: root.refreshSnapshot()

  // A plugin that was disabled and enabled again comes back with a bare entry: the bar
  // removed ours from shell.json (and with it the `docked` list) while the docked entries
  // stayed parked in plugins[]. Adopt them back from their markers, in their parked order,
  // instead of showing an empty drawer.
  // Marked entries that are parked but not in the drawer yet: those are what a bare
  // entry (a disable/enable cycle) has to take back.
  function pendingAdoption() {
    var marked = Model.adoptableDocked(root.config, root.moduleName)
    var have = Model.dockedIds(root.config, root.moduleName)
    var missing = []
    for (var i = 0; i < marked.length; i++) {
      var id = Model.entryId(marked[i])
      if (id !== "" && have.indexOf(id) === -1) missing.push(id)
    }
    return missing
  }

  function adoptDockedEntries() {
    if (!root.canWrite) return 0
    if (root.pendingAdoption().length === 0) return 0
    var adopted = 0
    root.mutate(function(document) {
      adopted = Model.adoptDocked(document, root.moduleName)
      Model.sweepDockMarkers(document, root.moduleName)
    })
    if (adopted > 0) console.log("bardock: adopted " + adopted + " docked icon(s) from the parked list")
    return adopted
  }
  // `bar` arrives after Component.onCompleted (the host injects it from its own
  // onLoaded), so anything that needs it has to wait for the first bar change.
  onBarChanged: {
    root.refreshSnapshot()
    root.adoptDockedEntries()
  }
  // The bar is injected after completion; if the config arrives even later, seed
  // on the first change we see instead of reading it as a drop.
  onConfigChanged: {
    // On the file-backed generations the config source *is* the file, so a change
    // here is the same event the shell's own shellConfigChanged is on <=4.0.2.
    // On legacy the ordering matters and handleConfigChange stays on the shell
    // signal only (it would otherwise see the post-drop layout as "previous").
    if (!root.hostConfig) root.handleConfigChange()
    else if (!root.seeded) root.refreshSnapshot()
    root.adoptDockedEntries()
  }

  // ---- dragging a docked icon back onto the bar ---------------------------
  property bool dragActive: false
  property string dragId: ""
  property url dragImageUrl: ""
  property var dragSlot: null
  property bool dragAfter: false
  property var dragMarker: null
  property real dragScreenX: 0
  property real dragScreenY: 0
  property int dragGhostWidth: 27
  property int dragGhostHeight: 26
  property int ghostWindows: 0
  property string dragGlyph: ""
  // Reordering inside the square: which cell the dragged icon is over, and where
  // it started.
  property int reorderIndex: -1
  property int dragFromIndex: -1
  property var ghostList: []

  function registerGhost(ghost) {
    var next = root.ghostList.slice()
    next.push(ghost)
    root.ghostList = next
  }

  function unregisterGhost(ghost) {
    root.ghostList = root.ghostList.filter(function(item) { return item !== ghost })
  }

  // Points inside the square are screen points: the surface spans the screen and
  // the bar is a layer surface of its own, so a screen point is converted into
  // the bar's coordinate space by subtracting the bar's origin.
  // The dock surface is sized to the square now, so a point inside it is *not* a
  // screen point any more. Everything outside the surface - the bar, the dock zone,
  // the ghost windows - works in screen coordinates, so crossing that boundary goes
  // through here.
  readonly property var surfaceOrigin: {
    var screen = dockSurface.screen
    var width = dockSurface.width
    return { x: screen ? Math.max(0, Math.round(screen.width - width)) : 0, y: 0 }
  }

  function toScreen(scenePoint) {
    return { x: scenePoint.x + surfaceOrigin.x, y: scenePoint.y + surfaceOrigin.y }
  }

  function barWindow() {
    return chevron.QsWindow ? chevron.QsWindow.window : null
  }

  function dragGeometry(screenPoint) {
    var window = barWindow()
    var scene = { x: screenPoint.x, y: screenPoint.y }
    if (window && window.contentItem) {
      try {
        var origin = window.contentItem.mapToItem(null, 0, 0)
        scene = { x: screenPoint.x - origin.x, y: screenPoint.y - origin.y }
      } catch (e) { }
    }
    return { bar: scene, scene: scene, screen: screenPoint, inside: insideBarStrip(scene, window) }
  }

  function insideBarStrip(barPoint, window) {
    if (!window) return false
    if (barPoint.x < 0 || barPoint.x > window.width) return false
    var size = bar ? bar.barSize : Style.bar.sizeHorizontal
    var slack = Style.space(8)
    return barPoint.y >= -slack && barPoint.y <= size + slack
  }

  function slotCandidates() {
    var out = []
    if (!bar || !root.hostSlots) return out
    var mine = root.ownSlot
    for (var i = 0; i < root.hostSlots.length; i++) {
      var slot = root.hostSlots[i]
      if (!slot || slot === mine || !slot.activeItem) continue
      if (slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
      // A slot mid-destruction (a widget just docked) reports an empty id; it is
      // not a place anything can be dropped.
      if (!String(slot.moduleName || "") || !String(slot.region || "")) continue
      var point = { x: slot.x, y: slot.y }
      try { point = slot.mapToItem(null, 0, 0) } catch (e) { }
      out.push({
        slot: slot,
        region: slot.region,
        name: slot.moduleName,
        x: point.x,
        y: point.y,
        width: slot.width,
        height: slot.height
      })
    }
    return out
  }

  function gridOrigin() {
    try {
      return dockGrid.mapToItem(null, 0, 0)
    } catch (e) {
      return { x: 0, y: 0 }
    }
  }

  function pointInsideSquare(point) {
    if (squareCard.width <= 0 || squareCard.height <= 0) return false
    return point.x >= squareCard.x && point.x <= squareCard.x + squareCard.width
      && point.y >= squareCard.y && point.y <= squareCard.y + squareCard.height
  }

  function dropTargetAt(screenPoint) {
    var geometry = dragGeometry(screenPoint)
    if (!geometry.inside) return null
    return Model.nearestSlot(slotCandidates(), geometry.scene, bar ? bar.vertical : false)
  }

  // `popupScenePoint` is local to the dock surface; the ghost and the bar work in
  // screen coordinates.
  function beginDockDrag(id, popupScenePoint, ghostWidth, ghostHeight) {
    dragId = id
    dragFromIndex = Model.dockedIds(config, moduleName).indexOf(String(id))
    reorderIndex = dragFromIndex
    dragImageUrl = ""
    dragGhostWidth = Math.max(1, ghostWidth)
    dragGhostHeight = Math.max(1, ghostHeight)
    dragActive = true
    dragWatchdog.restart()
    var tile = tileFor(id)
    dragGlyph = tile ? tile.glyph : ""
    updateDockDrag(popupScenePoint)
  }

  // `nearestSlot` answers with one of `slotCandidates()`'s own entries: the bar
  // slot item is nested under `.slot`, while `.name`/`.region` are the copies
  // this widget reads. Use those two for the layout math and the nested item
  // only for the bar's marker geometry.
  function updateDockDrag(popupScenePoint) {
    if (!dragActive) return
    var geometry = dragGeometry(toScreen(popupScenePoint))
    dragScreenX = geometry.screen.x
    dragScreenY = geometry.screen.y

    if (geometry.inside) {
      // Over the bar: leaving the dock.
      var target = Model.nearestSlot(slotCandidates(), geometry.scene, bar ? bar.vertical : false)
      var candidate = target ? target.slot : null
      dragSlot = candidate && candidate.slot ? candidate.slot : null
      dragAfter = target ? target.after : false
      dragMarker = candidate && dragSlot && bar && typeof bar.dropMarkerRect === "function"
        ? root.hostDropMarkerRect(dragSlot, target.after)
        : null
      reorderIndex = -1
      return
    }

    // Still in the square: reordering. The grid cell under the cursor is the slot
    // the icon will take.
    dragSlot = null
    dragAfter = false
    dragMarker = null
    reorderIndex = pointInsideSquare(popupScenePoint)
      ? Model.cellIndexForPoint(popupScenePoint, gridOrigin(), cellUsed, popupColumns, dockedCount)
      : -1
  }

  function finishDockDrag(popupScenePoint) {
    var id = dragId
    var wasActive = dragActive
    var screen = toScreen(popupScenePoint)
    var target = wasActive ? dropTargetAt(screen) : null
    // Without slot geometry there is no candidate to land on, but a release over
    // the bar strip still means "put it back": the entry returns to the end of the
    // right section, where the chevron lives.
    var backOnBar = wasActive && !target && !root.legacyHost && barStripContains(screen)
    var index = reorderIndex
    var fromIndex = dragFromIndex
    resetDockDrag()

    if (id === "") return
    if (target) {
      placeOnBar(id, target.slot, target.after)
      return
    }
    if (backOnBar) {
      root.undock(id, "right", "")
      return
    }
    // Dropped inside the square: take that cell, if it is a different one.
    if (wasActive && index >= 0 && fromIndex >= 0 && index !== fromIndex) root.reorder(id, index)
  }

  // Is this screen point over the bar surface? The drag-out gesture on the
  // generations that expose no slot geometry needs it: the bar's own slot
  // positions are unknown, the bar's screen rectangle is not.
  function barStripContains(screenPoint) {
    var window = barWindow()
    var screen = window ? window.screen : null
    if (!screen) return false
    var size = bar ? bar.barSize : Style.bar.sizeHorizontal
    var slack = Style.space(8)
    return screenPoint.x >= screen.x && screenPoint.x <= screen.x + screen.width
      && screenPoint.y >= screen.y - slack && screenPoint.y <= screen.y + size + slack
  }

  // The layout half of a drop: put `id` back in the section the candidate lives
  // in, before the candidate or before the next visible widget after it.
  function placeOnBar(id, candidate, after) {
    if (!candidate) return false
    var name = String(candidate.name || "")
    var region = String(candidate.region || "")
    if (!name || !region) return false

    var beforeName = name
    if (after && root.legacyHost) {
      beforeName = bar.nextVisibleModuleName(region, name, root.ownSlot)
    }
    return root.undock(id, region, beforeName)
  }

  function resetDockDrag() {
    dragActive = false
    reorderIndex = -1
    dragFromIndex = -1
    dragId = ""
    dragImageUrl = ""
    dragSlot = null
    dragAfter = false
    dragMarker = null
  }

  // ---- state for the terminal ---------------------------------------------
  function registryJson() {
    var widgets = root.registryWidgets
    if (!widgets) return JSON.stringify({ available: false, count: 0, widgets: [] })
    var out = []
    for (var key in widgets) {
      var entry = widgets[key]
      out.push({ id: key, component: !!(entry && entry.component), metadata: !!(entry && entry.metadata) })
    }
    return JSON.stringify({ available: true, count: out.length, widgets: out })
  }

  function ghostsJson() {
    var out = []
    for (var i = 0; i < root.ghostList.length; i++) {
      var child = root.ghostList[i]
      if (!child) continue
      out.push({
        active: child.active === true,
        visible: child.visible === true,
        screenMatches: child.screenMatches === true,
        screen: child.screen ? String(child.screen.name || "") : "",
        ghostScreen: child.ghostScreen ? String(child.ghostScreen.name || "") : "",
        image: String(child.imageUrl || "") !== "",
        marker: child.markerRect !== null,
        width: Math.round(child.width || 0),
        height: Math.round(child.height || 0)
      })
    }
    return out
  }

  function tilesJson() {
    var out = []
    for (var i = 0; i < tileRepeater.count; i++) {
      var tile = tileRepeater.itemAt(i)
      if (!tile) {
        out.push({ index: i, missing: true })
        continue
      }
      out.push({
        index: i,
        id: tile.tileId,
        label: tile.label,
        hasEntry: tile.registryEntry !== null,
        component: tile.widgetComponent !== null,
        liveLoaded: tile.liveLoaded,
        liveWidth: Math.round(tile.liveWidth),
        liveHeight: Math.round(tile.liveHeight),
        liveVisible: tile.liveVisible,
        itemProbe: tile.itemProbe,
        probeNow: tile.liveLoaded ? tile.probeNow() : "not-loaded",
        anchors: tile.anchorsRetargeted,
        x: Math.round(tile.x),
        y: Math.round(tile.y),
        width: Math.round(tile.width),
        height: Math.round(tile.height)
      })
    }
    return out
  }

  function stateJson() {
    var document = root.config
    return JSON.stringify({
      open: root.popupOpen,
      docked: Model.dockedIds(document, root.moduleName),
      visibleDocked: root.dockedList.map(Model.entryId),
      dockedCount: root.dockedCount,
      side: root.popupSide,
      columns: root.popupColumns,
      cellUsed: root.cellUsed,
      minCell: root.minCell,
      drawerBound: root.drawerBound,
      rows: root.popupRows,
      cell: root.cell,
      surfaceWidth: Math.round(dockSurface.width),
      surfaceOrigin: root.surfaceOrigin,
      surfaceHeight: Math.round(dockSurface.height),
      windowWidth: Math.round(squareCard.width),
      windowHeight: Math.round(squareCard.height),
      windowSquare: Math.round(squareCard.width) === Math.round(squareCard.height),
      popupOrigin: { x: Math.round(squareCard.x), y: Math.round(squareCard.y) },
      armed: root.armed,
      pendingDockId: root.pendingDockId,
      seeded: root.seeded,
      previousSection: root.previousSection,
      previousCount: root.previousIds.length,
      configChanges: root.configChanges,
      lastLanded: root.lastLanded,
      barDragOverMe: root.barDragOverMe,
      dragActive: root.dragActive,
      dragTarget: dragSlot ? String(dragSlot.moduleName || "") : "",
      tiles: tilesJson(),
      sections: Model.layoutIds(document),
      parked: Model.idsOf(Model.pluginsList(document)),
      registryKnown: root.registryWidgets !== null,
      hostGeneration: root.legacyHost ? "legacy" : (root.bar ? "scoped" : "absent"),
      configSource: root.hostConfig ? "host" : (shellConfigFile.ready ? "file" : "none"),
      canWrite: root.canWrite,
      serviceRegistry: root.ownServiceRegistry !== null,
      dockable: root.dockableIds.length,
      pickerOpen: root.pickerOpen,
      configFileWrites: shellConfigFile.writes,
      configTextLength: shellConfigFile.text.length,
      configRefreshes: shellConfigFile.refreshes,
      configFailures: shellConfigFile.failures,
      configPath: shellConfigFile.path,
      instances: bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(root.moduleName).length : -1,
      slots: bar && root.hostSlots ? root.hostSlots.length : -1,
      ghostWindows: root.ghostWindows,
      instances: bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(root.moduleName).length : 0,
      tileDragging: root.anyTileDragging(),
      slotWidth: root.slotWidth,
      padShown: root.padShown,
      dragNear: root.dragNear,
      dragStallMs: root.dragStallMs,
      dockZone: dockZoneRects(),
      openZone: openZoneRects(),
      barDragId: root.barDragId,
      reorderIndex: root.reorderIndex,
      dragFromIndex: root.dragFromIndex,
      ghosts: ghostsJson()
    })
  }

  // ---- test seams ----------------------------------------------------------
  // A real drag needs a mouse; these drive the same code paths from a terminal.
  // `simulateLanding` reproduces what the bar does when a widget is dropped on
  // the chevron: arm on the source id (the hover would have set it), then move
  // that entry to sit beside us.
  function simulateLanding(id) {
    if (!root.canWrite) return false
    var own = Model.findEntry(config, moduleName)
    if (!own || own.kind !== "bar") return false
    armed = true
    pendingDockId = String(id)
    // The bar's drop resolution, reproduced: the release point resolved to this
    // slot, which is what makes the drop count.
    lastDropTarget = String(root.moduleName)
    armTimer.restart()
    root.mutate(function(document) {
      var existing = Model.findEntry(document, id)
      if (!existing) return
      var moved = existing.entry
      if (existing.kind === "bar") {
        Model.sectionEntries(Model.layoutOf(document), existing.section).splice(existing.index, 1)
      }
      var parked = Model.pluginsList(document)
      for (var p = parked.length - 1; p >= 0; p--) {
        if (Model.entryId(parked[p]) === id) parked.splice(p, 1)
      }
      var ownNow = Model.findEntry(document, root.moduleName)
      if (!ownNow || ownNow.kind !== "bar") return
      Model.sectionEntries(Model.layoutOf(document), ownNow.section).splice(ownNow.index, 0, moved || { id: id })
    })
    return true
  }

  // Arm the drop window on an id without moving anything: reproduces "the drag
  // hovered the chevron, then something unrelated wrote shell.json".
  function armOnly(id) {
    armed = true
    pendingDockId = String(id)
    armTimer.restart()
    return true
  }

  // Why a drop did or did not count, as JSON, for the terminal.
  function explainDrop(candidate) {
    var document = root.config
    var own = Model.findEntry(document, root.moduleName)
    var current = own && own.kind === "bar"
      ? Model.idsOf(Model.sectionEntries(Model.layoutOf(document), own.section))
      : []
    var before = root.previousIds
    return JSON.stringify({
      armed: root.armed,
      pending: root.pendingDockId,
      candidate: String(candidate || ""),
      ownKind: own ? own.kind : "missing",
      ownSection: own ? own.section : "",
      ownIndex: own ? own.index : -1,
      currentCount: current.length,
      previousCount: before.length,
      currentNeighbours: Model.neighbourIds(current, root.moduleName),
      previousNeighbours: Model.neighbourIds(before, root.moduleName),
      candidateOnBar: Model.isOnBar(document, candidate),
      candidateInSection: current.indexOf(String(candidate || "")) !== -1,
      neighbourBefore: Model.neighbourIds(before, root.moduleName).indexOf(String(candidate || "")) !== -1,
      isNeighbourNow: Model.neighbourIds(current, root.moduleName).indexOf(String(candidate || "")) !== -1,
      result: Model.droppedOnChevron(document, root.moduleName, before, candidate)
    })
  }

  // The drop half of dragging out of the square, addressed in bar coordinates.
  // Returns a JSON line so a terminal test can see what the hit test decided.
  function dropOnBar(id, barX, barY) {
    var window = barWindow()
    if (!window) return JSON.stringify({ error: "no-bar-window" })
    var barPoint = { x: barX, y: barY }
    if (!insideBarStrip(barPoint, window)) return JSON.stringify({ error: "outside-bar" })
    var scene = window.contentItem ? window.contentItem.mapToItem(null, barPoint.x, barPoint.y) : barPoint
    var target = Model.nearestSlot(slotCandidates(), scene, bar ? bar.vertical : false)
    if (!target) return JSON.stringify({ error: "no-target" })

    var candidate = target.slot
    var moved = placeOnBar(id, candidate, target.after)
    return JSON.stringify({
      id: id,
      region: String(candidate.region || ""),
      target: String(candidate.name || ""),
      after: target.after,
      moved: moved
    })
  }

  // Show the drag ghost (and the bar's insertion marker) at a screen point
  // without a mouse, so the drag layer can be photographed from a terminal.
  function ghostAt(id, screenX, screenY) {
    dragId = String(id)
    dragActive = true
    dragWatchdog.restart()
    var dragTile = tileFor(id)
    dragGlyph = dragTile ? dragTile.glyph : ""
    dragScreenX = screenX
    dragScreenY = screenY
    var target = Model.nearestSlot(slotCandidates(), { x: screenX, y: screenY }, bar ? bar.vertical : false)
    var candidate = target ? target.slot : null
    dragSlot = candidate && candidate.slot ? candidate.slot : null
    dragAfter = target ? target.after : false
    dragMarker = dragSlot && bar && typeof bar.dropMarkerRect === "function"
      ? root.hostDropMarkerRect(dragSlot, dragAfter)
      : null
    return dragMarker !== null
  }

  // Pretend a tile drag is in progress at a screen point, so the cell maths can be
  // checked against the live grid from a terminal.
  // Read-only: which cell a screen point resolves to. It used to start a real drag
  // and never clean it up, which is how a forgotten call left the desktop frozen.
  function fakeDrag(id, screenX, screenY) {
    var scene = { x: screenX - root.surfaceOrigin.x, y: screenY - root.surfaceOrigin.y }
    if (!pointInsideSquare(scene)) return -1
    return Model.cellIndexForPoint(scene, gridOrigin(), cellUsed, popupColumns, dockedCount)
  }

  function tileFor(id) {
    for (var i = 0; i < tileRepeater.count; i++) {
      var tile = tileRepeater.itemAt(i)
      if (tile && tile.tileId === String(id)) return tile
    }
    return null
  }

  IpcHandler {
    target: "ozz1ee.bardock"

    function open(): void { root.openPopup() }
    function close(): void { root.closePopup() }
    function show(): void { root.openPopup() }
    function hide(): void { root.closePopup() }
    function toggle(): void { root.togglePopup() }
    function refresh(): void { root.refreshSnapshot() }
    function picker(): void { root.pickerOpen = true; root.openPopup() }
    function dockable(): string { return JSON.stringify(root.dockableIds) }
    function pick(id: string): string { return root.dock(id) ? "ok" : "failed" }
    function dock(id: string): void { root.dock(id) }
    function undock(id: string): void { root.undock(id, "right", "") }
    function undockAll(): void { root.undockAll() }
    function state(): string { return root.stateJson() }
    function registry(): string { return root.registryJson() }
    function simulateLanding(id: string): bool { return root.simulateLanding(id) }
    function armOnly(id: string): bool { return root.armOnly(id) }
    function explainDrop(id: string): string { return root.explainDrop(id) }
    function dropAt(id: string, x: int, y: int): string { return root.dropOnBar(id, x, y) }
    function ghost(id: string, x: int, y: int): bool { return root.ghostAt(id, x, y) }
    function ghosts(): string { return JSON.stringify(root.ghostsJson()) }
    function clearGhost(): void { root.reset() }
    function reset(): void { root.reset() }
    function testDrag(on: bool): void { root.testDrag = on }
    function zoneTest(id: string, x: int, y: int): bool { return root.finishBarDrag(id, x, y) }
    function reorderTest(id: string, index: int): bool { return root.reorder(id, index) }
    // Geometry for any icon count, so growth, squareness and the screen bound can be
    // checked without touching the dock itself.
    function sizeFor(count: int): string {
      var grid = Model.drawerGrid(Math.max(1, count), root.cell, root.minCell, root.drawerBound, root.popupInset)
      return JSON.stringify({ count: count, side: grid.side, columns: grid.columns, rows: grid.rows, cell: grid.cell })
    }
    function fakeDrag(id: string, x: int, y: int): int { return root.fakeDrag(id, x, y) }
    function gridOrigin(): string { return JSON.stringify(root.gridOrigin()) }
    function zoneRects(): string { return JSON.stringify(root.dockZoneRects()) }
    function dedupe(): int {
      var removed = 0
      if (root.canWrite)
        root.mutate(function(document) { removed = Model.dedupeLayout(document) })
      return removed
    }
  }

  implicitWidth: vertical ? barSize : root.slotWidth
  implicitHeight: vertical ? chevron.implicitHeight : barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
  }

  // Landing pad: visible only while the bar is dragging something, so the strip
  // reads as "drop here" instead of as chrome.
  Rectangle {
    id: pad
    anchors.fill: parent
    anchors.margins: Style.space(2)
    radius: Math.max(2, Style.cornerRadius)
    color: root.barDragOverMe ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
    border.width: root.padShown ? 1 : 0
    border.color: Color.accent
    opacity: root.padShown ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
      NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
    }
  }


  BarIconButton {
    id: chevron
    anchors.fill: parent
    bar: root.bar
    slotSize: vertical ? Style.bar.iconSlot : -1
    iconComponent: chevronGlyph
    active: root.barDragOverMe
    tooltipText: (root.dockedCount === 0
      ? "Bar dock"
      : "Bar dock - " + root.dockedCount + " hidden")
      + (root.pickerAvailable ? " (right-click to dock one)" : "")

    onPressed: function(button) {
      if (button === Qt.LeftButton) root.togglePopup()
      else if (button === Qt.RightButton && root.pickerAvailable) {
        root.pickerOpen = !root.pickerOpen
        if (root.pickerOpen) root.openPopup()
      }
    }
  }

  Component {
    id: chevronGlyph

    Item {
      implicitWidth: Style.bar.iconCanvas
      implicitHeight: Style.bar.iconCanvas

      Chevron {
        anchors.centerIn: parent
        color: chevron.active && chevron.useActiveColor ? chevron.activeColor : chevron.foreground
        open: root.popupOpen
      }
    }
  }

  // The square lives in a full-screen, click-through overlay rather than in a
  // small popup window. A docked widget's own panel positions itself from its
  // anchor item's window (`anchorItem.QsWindow.window`), so an anchor inside a
  // 168px window that sits at the screen's right edge makes every panel land in
  // the top-left corner. With the surface spanning the screen, the same maths
  // the bar's widgets do works out: panels open at the top right, under the
  // square. Input is masked to the square, so clicks elsewhere pass through and
  // the focus grab below is what closes it.
  PanelWindow {
    id: dockSurface

    // Anchored to a screen explicitly: without one a layer window keeps its
    // 100x100 default and the square's own coordinate space is useless.
    readonly property var targetScreen: {
      var window = root.barWindow()
      if (window && window.screen) return window.screen
      return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    }

    screen: targetScreen
    visible: root.popupOpen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "ozz1ee-bardock-square"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The surface is only as big as the drawer (a full-screen overlay costs ~7% of
    // a core to composite for nothing). The square starts below the bar, so its
    // height has to include that offset plus a margin on each side - sized to the
    // square alone the bottom edge gets cut off.
    implicitWidth: root.popupSide + 2 * root.popupMargin
    implicitHeight: (bar ? bar.barSize : Style.bar.sizeHorizontal) + root.popupSide + 2 * root.popupMargin

    anchors {
      top: true
      right: true
    }

    mask: Region {
      x: squareCard.x
      y: squareCard.y
      width: squareCard.width
      height: squareCard.height
    }

    Rectangle {
      id: squareCard

      readonly property int edge: Style.space(root.popupMargin)

      x: edge
      y: (bar ? bar.barSize : Style.bar.sizeHorizontal) + edge
      width: root.popupSide
      height: root.popupSide

      color: Color.popups.background
      border.width: Math.max(1, Style.space(1))
      border.color: Color.popups.border
      radius: Style.cornerRadius

      Grid {
        id: dockGrid
        anchors.centerIn: parent
        columns: root.popupColumns
        spacing: 0

        Repeater {
          id: tileRepeater
          model: root.dockedList.length

          delegate: DockTile {
            required property int index

            entry: root.dockedList[index] || null
            barHost: root.bar
            faceMemory: root.faceMemory
            anchorHost: chevron
            registry: root.registryWidgets
            cellSize: root.cellUsed
            foreground: root.foreground
            fontFamily: root.fontFamily
            draggingTile: root.dragActive && root.dragId === tileId
            reorderTarget: root.dragActive && root.reorderIndex >= 0 && index === root.reorderIndex
              && index !== root.dragFromIndex

            onDragStarted: function(id, x, y, ghostWidth, ghostHeight) {
              root.beginDockDrag(id, { x: x, y: y }, ghostWidth, ghostHeight)
            }
            onDragMoved: function(id, x, y) {
              root.updateDockDrag({ x: x, y: y })
            }
            onDragFinished: function(id, x, y, dragged) {
              if (dragged) root.finishDockDrag({ x: x, y: y })
              else root.resetDockDrag()
            }
          }
        }
      }

      // Dock picker. Only on the generations that no longer hand a widget the
      // bar's slot geometry: there an icon cannot be dragged onto the chevron, so
      // the list of what is on the bar is offered instead.
      Rectangle {
        id: pickerPanel
        visible: root.pickerAvailable && root.pickerOpen
        anchors.fill: parent
        color: Color.popups.background
        radius: Style.cornerRadius
        border.width: Math.max(1, Style.space(1))
        border.color: Color.popups.border
        z: 20

        ListView {
          id: pickerListView
          anchors.fill: parent
          anchors.margins: Style.space(6)
          clip: true
          model: root.dockableIds
          spacing: 1

          delegate: Rectangle {
            required property string modelData

            width: pickerListView.width
            height: Style.bar.iconCanvas
            radius: Math.max(2, Style.cornerRadius)
            color: pickerRow.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              verticalAlignment: Text.AlignVCenter
              text: Model.displayLabel(modelData)
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            MouseArea {
              id: pickerRow
              anchors.fill: parent
              hoverEnabled: true
              onClicked: {
                root.dock(modelData)
                root.pickerOpen = false
              }
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.dockableIds.length === 0
          width: parent.width - Style.space(16)
          text: "Every bar widget is already hidden."
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }

      // Trigger for the picker: a small plus in the square's corner. The chevron
      // answers a right-click too, but with every cell full there would be nothing
      // to click otherwise.
      Rectangle {
        id: pickerButton
        visible: !pickerPanel.visible && root.pickerAvailable
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Style.space(3)
        width: Style.space(14)
        height: Style.space(14)
        radius: Math.max(2, Style.cornerRadius)
        color: pickerButtonMouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
        z: 15

        Text {
          anchors.centerIn: parent
          text: "+"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        MouseArea {
          id: pickerButtonMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            root.pickerOpen = true
            root.openPopup()
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.dockedCount === 0 && !pickerPanel.visible
        width: squareCard.width - Style.space(24)
        text: root.barDragOverMe
          ? "Release to dock this icon"
          : (root.pickerAvailable
            ? "Nothing docked yet. Right-click the chevron to dock a bar icon."
            : "Nothing docked yet. Drag a bar icon onto the chevron.")
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        opacity: 0.7
      }
    }
  }

  // Outside click closes the square, the way PopupCard does it: the grab routes
  // input to the square and the bar only, and everything else clears it.
  HyprlandFocusGrab {
    active: root.popupOpen
    windows: [dockSurface, root.barWindow()]
    onCleared: root.closePopup()
  }

  // One drag ghost per screen. `Variants` (not `Repeater`) because the delegate
  // is a PanelWindow, not an Item: a Repeater refuses to create it and the ghost
  // simply never appears.
  Variants {
    model: Quickshell.screens

    delegate: Component {
      DockGhost {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
        active: root.dragActive
        imageUrl: root.dragImageUrl
        glyph: root.dragGlyph
        fontFamily: root.fontFamily
        ghostX: root.dragScreenX
        ghostY: root.dragScreenY
        ghostWidth: root.dragGhostWidth
        ghostHeight: root.dragGhostHeight
        markerRect: root.dragMarker
        foreground: root.foreground
        barBackground: bar && !bar.transparent ? bar.background : "transparent"

        Component.onCompleted: {
          root.ghostWindows += 1
          root.registerGhost(this)
        }
        Component.onDestruction: {
          // On teardown the root can already be gone: `root` resolves to null and
          // reading a property off it throws.
          if (root) {
            root.ghostWindows -= 1
            root.unregisterGhost(this)
          }
        }
      }
    }
  }
}
