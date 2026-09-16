// Pure helpers for BarDock. Qt-free so node can test them
// (test/model.test.js); the QML owns everything that touches the bar.
//
// A docked widget keeps its settings and stays "enabled" for the shell, which
// means its layout entry moves to the top-level `plugins` array instead of
// disappearing: PluginRegistry.isEnabled() counts an entry found in either
// place, and only an enabled plugin keeps a live component in
// bar.barWidgetRegistry -- the component the dock renders. Removing the entry
// outright would unregister it and the square would come up empty.

var SECTIONS = ["left", "center", "right"]

function clamp(value, low, high) {
  var n = Number(value)
  if (!isFinite(n)) n = low
  return Math.max(low, Math.min(high, n))
}

// A layout entry is either a bare id string or an object carrying the widget's
// settings; both spellings appear in shell.json.
function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object") return String(entry.id || "")
  return ""
}

function entryObject(entry) {
  if (typeof entry === "string") return { id: entry }
  return entry || null
}

// Human label when no registry metadata is reachable: last dotted segment,
// separators as spaces, first letter upper-cased.
function displayLabel(id) {
  var text = String(id || "")
  var segment = text.substring(text.lastIndexOf(".") + 1).replace(/[-_]+/g, " ").trim()
  if (!segment) return text
  return segment.charAt(0).toUpperCase() + segment.slice(1)
}

function layoutOf(config) {
  if (!config || typeof config !== "object") return null
  return config.bar && typeof config.bar === "object" ? config.bar.layout : null
}

function sectionEntries(layout, section) {
  if (!layout || typeof layout !== "object") return []
  var entries = layout[section]
  return entries && entries.length !== undefined ? entries : []
}

function sectionEntriesMutable(layout, section) {
  if (!layout || typeof layout !== "object") return []
  if (!layout[section] || layout[section].length === undefined) layout[section] = []
  return layout[section]
}

function pluginsList(config) {
  if (!config || typeof config !== "object") return []
  var list = config.plugins
  return list && list.length !== undefined ? list : []
}

function pluginsListMutable(config) {
  if (!config || typeof config !== "object") return []
  if (!config.plugins || config.plugins.length === undefined) config.plugins = []
  return config.plugins
}

function idsOf(entries) {
  var out = []
  if (!entries || entries.length === undefined) return out
  for (var i = 0; i < entries.length; i++) out.push(entryId(entries[i]))
  return out
}

function layoutIds(config) {
  var layout = layoutOf(config)
  var out = {}
  for (var s = 0; s < SECTIONS.length; s++) out[SECTIONS[s]] = idsOf(sectionEntries(layout, SECTIONS[s]))
  return out
}

function findAll(list, wanted) {
  for (var i = 0; i < list.length; i++) {
    if (entryId(list[i]) === wanted) return { section: "", index: i, entry: entryObject(list[i]) }
  }
  return null
}

// Where an entry sits right now: on the bar (kind "bar") or parked in plugins[]
// (kind "plugin", which is what docking does).
function findEntry(config, id) {
  var wanted = String(id || "")
  if (!wanted) return null

  var layout = layoutOf(config)
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = sectionEntries(layout, SECTIONS[s])
    for (var i = 0; i < entries.length; i++) {
      if (entryId(entries[i]) === wanted) {
        return { kind: "bar", section: SECTIONS[s], index: i, entry: entryObject(entries[i]) }
      }
    }
  }

  var parked = findAll(pluginsList(config), wanted)
  if (parked) return { kind: "plugin", section: "", index: parked.index, entry: parked.entry }
  return null
}

function ensureDockHomes(entry) {
  if (!entry) return {}
  if (!entry.dockHomes || typeof entry.dockHomes !== "object") entry.dockHomes = {}
  return entry.dockHomes
}

// Where a docked widget came from, so undocking can put it back instead of
// appending it to the end of the bar. `before` is the id that followed it.
function dockHomeFor(config, ownId, id) {
  var own = findEntry(config, ownId)
  if (!own || !own.entry) return null
  var homes = own.entry.dockHomes
  if (!homes || typeof homes !== "object") return null
  var home = homes[String(id || "")]
  return home && typeof home === "object" ? home : null
}

// A dock that has been decided but not yet written. The bar writes the layout right
// after a drop *and* rebuilds the widget instances, so an in-memory timer set at
// release time dies with the instance and the dock never happens (the icon stays
// wherever the bar put it). This marker lives in our own entry, which the instance
// built right after the rebuild reads, so any instance can finish the job.
function setPendingDock(config, ownId, id) {
  var own = findEntry(config, ownId)
  if (!own || !own.entry) return false
  own.entry.pendingDock = { id: String(id || ""), at: Date.now() }
  return true
}

function pendingDock(config, ownId, maxAgeMs) {
  var own = findEntry(config, ownId)
  if (!own || !own.entry || !own.entry.pendingDock) return null
  var marker = own.entry.pendingDock
  var id = String(marker.id || "")
  if (!id) return null
  var age = Date.now() - Number(marker.at || 0)
  if (maxAgeMs && age > Number(maxAgeMs)) return null
  return id
}

function clearPendingDock(config, ownId) {
  var own = findEntry(config, ownId)
  if (!own || !own.entry || !own.entry.pendingDock) return false
  delete own.entry.pendingDock
  return true
}

function ensureDocked(entry) {
  if (!entry) return []
  if (!entry.docked || entry.docked.length === undefined) entry.docked = []
  return entry.docked
}

function dockedEntries(config, ownId) {
  var own = findEntry(config, ownId)
  if (!own || !own.entry) return []
  var list = own.entry.docked
  return list && list.length !== undefined ? list : []
}

function dockedIds(config, ownId) {
  return idsOf(dockedEntries(config, ownId))
}

// What the square actually shows: a widget that is back on the bar (dragged out
// by the bar's own drag, or restored by hand) is not docked any more, whatever
// docked[] still says.
function visibleDocked(config, ownId) {
  var list = dockedEntries(config, ownId)
  var out = []
  for (var i = 0; i < list.length; i++) {
    var id = entryId(list[i])
    if (!id) continue
    var where = findEntry(config, id)
    if (where && where.kind !== "plugin") continue
    out.push(list[i])
  }
  return out
}

// Move an entry off the bar and into docked[], keeping the whole entry object
// (so the widget keeps its settings) and parking it in plugins[] so the shell
// still counts the plugin as enabled.
function dockInto(config, ownId, id) {
  var own = findEntry(config, ownId)
  var wanted = String(id || "")
  if (!own || !own.entry || !wanted || wanted === String(ownId)) return null

  var source = findEntry(config, wanted)
  if (!source) return null
  // Already parked in plugins[]: nothing to move.
  if (source.kind === "plugin") return null

  var entries = sectionEntriesMutable(layoutOf(config), source.section)
  var nextId = entryId(entries[source.index + 1])
  entries.splice(source.index, 1)
  ensureDockHomes(own.entry)[wanted] = { section: source.section, before: nextId }
  pluginsListMutable(config).push(source.entry)

  // An entry can be on the bar and still listed in docked[] (it was dragged out
  // by the bar's own drag, or put back by hand). Re-park it without duplicating
  // the list entry - that is what "dropped on the chevron again" means.
  var list = ensureDocked(own.entry)
  var present = false
  for (var i = 0; i < list.length; i++) if (entryId(list[i]) === wanted) { present = true; break }
  if (!present) list.push(source.entry)
  return source.entry
}

// Put a docked entry back on the bar, before `beforeName` (or at the end of the
// section when that id is empty or missing).
function undockFrom(config, ownId, id, section, beforeName) {
  var own = findEntry(config, ownId)
  var wanted = String(id || "")
  if (!own || !own.entry || !wanted) return null

  var list = ensureDocked(own.entry)
  var index = -1
  for (var i = 0; i < list.length; i++) {
    if (entryId(list[i]) === wanted) {
      index = i
      break
    }
  }
  if (index === -1) return null

  var home = dockHomeFor(config, ownId, wanted)
  var wantedSection = String(section || "")
  var wantedBefore = String(beforeName || "")
  if (wantedSection === "" && home) {
    wantedSection = String(home.section || "")
    wantedBefore = String(home.before || "")
  }
  var target = SECTIONS.indexOf(wantedSection) === -1 ? "right" : wantedSection
  var entry = list.splice(index, 1)[0]
  var homes = ensureDockHomes(own.entry)
  delete homes[wanted]

  var parked = pluginsList(config)
  for (var p = parked.length - 1; p >= 0; p--) {
    if (entryId(parked[p]) === wanted) parked.splice(p, 1)
  }

  var entries = sectionEntriesMutable(layoutOf(config), target)
  var at = -1
  var before = wantedBefore
  if (before && before !== String(ownId)) {
    for (var j = 0; j < entries.length; j++) {
      if (entryId(entries[j]) === before) {
        at = j
        break
      }
    }
  }
  if (at !== -1) {
    entries.splice(at, 0, entry)
  } else if (target === own.section) {
    // No anchor we can use: either one was never recorded (the icon was parked)
    // or the remembered one is docked too. Land in front of us instead of
    // appending to the far end of the bar - an undocked icon belongs next to the
    // drawer it came out of, and pushing it past the chevron would also push the
    // chevron itself out of the corner it is supposed to sit in.
    entries.splice(Math.min(own.index, entries.length), 0, entry)
  } else {
    entries.push(entry)
  }
  return entry
}

// Would pruning change anything? True when docked[] holds an id that Prune
// would drop (it is on the bar again, or empty).
function needsPrune(config, ownId) {
  var list = dockedEntries(config, ownId)
  for (var i = 0; i < list.length; i++) {
    var id = entryId(list[i])
    if (!id) return true
    var where = findEntry(config, id)
    if (where && where.kind !== "plugin") return true
  }
  return false
}

// Self-heal: drop docked[] entries that are on the bar again.
function pruneDocked(config, ownId) {
  var own = findEntry(config, ownId)
  if (!own || !own.entry) return []
  if (!needsPrune(config, ownId)) return []
  var kept = []
  var list = ensureDocked(own.entry)
  for (var i = 0; i < list.length; i++) {
    var id = entryId(list[i])
    if (!id) continue
    var where = findEntry(config, id)
    if (where && where.kind !== "plugin") continue
    kept.push(list[i])
  }
  own.entry.docked = kept
  return kept
}

// Neighbours of `ownId` in a plain id list.
function neighbourIds(ids, ownId) {
  var index = ids.indexOf(String(ownId))
  if (index === -1) return []
  var out = []
  if (index > 0) out.push(ids[index - 1])
  if (index + 1 < ids.length) out.push(ids[index + 1])
  return out
}

// The drop that counts as "on the chevron". The bar resolves a drag to one slot
// while the pointer moves and remembers it as `barDragTarget` until release, so
// the plugin can read which slot the drop actually landed on. A widget that is
// already the chevron's neighbour does not move at all when it is dropped there,
// so position alone can never decide this.
function droppedOnChevron(config, ownId, previousIds, candidate, targetName) {
  var wanted = String(candidate || "")
  if (!wanted) return false
  if (String(targetName || "") !== String(ownId)) return false
  var own = findEntry(config, ownId)
  if (!own || own.kind !== "bar") return false
  return isOnBar(config, wanted)
}

// Which grid cell a point is over, clamped to the icons that exist. Used to
// reorder the dock by dragging a cell onto another one.
function cellIndexForPoint(point, origin, cell, columns, count) {
  var total = Math.max(0, Math.floor(Number(count) || 0))
  if (total === 0) return -1
  var unit = Math.max(1, Math.floor(Number(cell) || 1))
  var cols = Math.max(1, Math.floor(Number(columns) || 1))
  var maxRow = Math.ceil(total / cols) - 1

  var dx = Math.floor((point.x - origin.x) / unit)
  var dy = Math.floor((point.y - origin.y) / unit)
  if (dx < 0) dx = 0
  if (dy < 0) dy = 0
  if (dx > cols - 1) dx = cols - 1
  if (dy > maxRow) dy = maxRow

  var index = dy * cols + dx
  if (index < 0) index = 0
  if (index > total - 1) index = total - 1
  return index
}

// Move a docked icon to another slot in docked[], which is the order the square
// draws them in.
function reorderDocked(config, ownId, id, targetIndex) {
  var own = findEntry(config, ownId)
  if (!own || !own.entry) return false
  var list = ensureDocked(own.entry)
  var wanted = String(id || "")

  var from = -1
  for (var i = 0; i < list.length; i++) {
    if (entryId(list[i]) === wanted) {
      from = i
      break
    }
  }
  if (from === -1) return false

  var to = Math.round(Number(targetIndex))
  if (!isFinite(to)) return false
  to = Math.max(0, Math.min(list.length - 1, to))
  if (to === from) return false

  var entry = list.splice(from, 1)[0]
  list.splice(to, 0, entry)
  return true
}


function pointInRect(point, rect) {
  if (!point || !rect) return false
  return point.x >= rect.x && point.x <= rect.x + rect.width
    && point.y >= rect.y && point.y <= rect.y + rect.height
}

// Any of `rects` contains `point`.
function pointInAnyRect(point, rects) {
  if (!rects || rects.length === undefined) return false
  for (var i = 0; i < rects.length; i++) {
    if (pointInRect(point, rects[i])) return true
  }
  return false
}

// The generous landing area for the dock gesture: the bar strip from the left
// edge of the chevron's slot (which grows during a drag) to the screen edge,
// plus the square itself, so a drop aimed roughly at the corner counts wherever
// the bar's own nearest-slot resolution happened to land.
// Where a drop counts as docking: the chevron's own slot, optionally widened by
// `slack` on every side, plus the square when the drawer is open.
//
// An earlier revision ran the bar part of the zone from the chevron's slot all the
// way to the screen edge, which also covered the last widget or two on the bar. That
// is wrong in use: dragging an icon along the bar opened the drawer and could dock the
// icon when the pointer was still over a neighbour, so ordinary reordering felt
// unreliable. The zone is the slot itself unless the user asks for a bigger pocket
// (`dockZoneSlack`, 0 by default).
function dockZoneRects(slotScreenX, slotScreenY, slotWidth, slotHeight, screenWidth, squareRect, slack) {
  var pad = Math.max(0, Math.floor(Number(slack) || 0))
  var slotX = Math.max(0, Math.floor(Number(slotScreenX) || 0))
  var slotY = Math.max(0, Math.floor(Number(slotScreenY) || 0))
  var slotW = Math.max(1, Math.floor(Number(slotWidth) || 0))
  var slotH = Math.max(1, Math.floor(Number(slotHeight) || 0))
  var left = Math.max(0, slotX - pad)
  var width = slotW + pad * 2
  var screen = Math.floor(Number(screenWidth) || 0)
  if (screen > 0 && left + width > screen) width = Math.max(1, screen - left)
  var rects = [{
    x: left,
    y: Math.max(0, slotY - pad),
    width: width,
    height: slotH + pad * 2
  }]
  if (squareRect) rects.push(squareRect)
  return rects
}

function isOnBar(config, id) {
  var where = findEntry(config, id)
  return !!(where && where.kind === "bar")
}

// Repair helper: the bar renders an entry per list slot, so a duplicated id
// shows the widget twice. Keep the first occurrence in each section.
function dedupeLayout(config) {
  var layout = layoutOf(config)
  if (!layout) return 0
  var seen = {}
  var removed = 0
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = sectionEntriesMutable(layout, SECTIONS[s])
    var kept = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (!id || seen[id]) {
        removed++
        continue
      }
      seen[id] = true
      kept.push(entries[i])
    }
    if (kept.length !== entries.length) layout[SECTIONS[s]] = kept
  }
  return removed
}

// The bar's own drag places a widget next to its drop target, so the entry that
// was dropped on the chevron is the single entry that appeared beside us and
// was not in the section before. Requiring exactly one arrival and no departure
// keeps a stale or wrong baseline from docking something by accident.
function landedAdjacentTo(config, ownId, previousIds) {
  var own = findEntry(config, ownId)
  if (!own || own.kind !== "bar") return ""
  var entries = sectionEntries(layoutOf(config), own.section)
  var current = idsOf(entries)
  var previous = previousIds && previousIds.length !== undefined ? previousIds : []
  if (previous.length === 0) return ""

  var added = []
  var removed = 0
  for (var i = 0; i < current.length; i++) {
    if (previous.indexOf(current[i]) === -1) added.push(current[i])
  }
  for (var j = 0; j < previous.length; j++) {
    if (current.indexOf(previous[j]) === -1) removed++
  }
  if (added.length !== 1 || removed !== 0) return ""

  for (var step = -1; step <= 1; step += 2) {
    var index = own.index + step
    if (index < 0 || index >= entries.length) continue
    var id = entryId(entries[index])
    if (id && id === added[0]) return id
  }
  return ""
}

// Square popup: one cell per icon in a ceil(sqrt(n)) grid, so the card is a perfect
// square whatever it holds and it grows with its contents. `bound` is the largest
// side the screen can give it: once the icons need more than that, the cells shrink
// (down to `minCell`) instead of the icons spilling out of the square, and only then
// does the span grow. Nothing else caps how big the drawer may become.
function drawerGrid(count, cell, minCell, bound, inset) {
  var n = Math.max(1, Math.floor(Number(count) || 1))
  var unit = Math.max(1, Math.floor(Number(cell) || 1))
  var floorCell = Math.max(8, Math.floor(Number(minCell) || 8))
  var pad = Math.max(0, Math.floor(Number(inset) || 0))
  var limit = Math.max(pad + floorCell, Math.floor(Number(bound) || 0))
  var room = limit - pad

  var span = Math.ceil(Math.sqrt(n))
  var used = unit

  if (span * used > room) {
    used = Math.max(floorCell, Math.floor(room / span))
    if (span * used > room) {
      // Even `minCell` is too wide for that many columns: take the widest span the
      // room allows and let the rows grow instead.
      span = Math.max(1, Math.floor(room / floorCell))
    }
  }

  var rows = Math.ceil(n / span)
  var side = Math.max(span, rows) * used + pad

  return {
    columns: span,
    rows: rows,
    cell: used,
    side: Math.round(Math.min(side, limit))
  }
}

function gridRows(count, columns) {
  var cols = Math.max(1, Math.floor(Number(columns) || 1))
  return Math.max(1, Math.ceil(Math.max(0, Number(count) || 0) / cols))
}

// Nearest bar slot for a drop point, along the bar's axis; `after` when the
// point sits past the slot's middle. Mirrors what the bar does for its own
// reorder drags.
function nearestSlot(slots, point, vertical) {
  if (!slots || slots.length === undefined || slots.length === 0) return null
  var best = null
  for (var i = 0; i < slots.length; i++) {
    var slot = slots[i]
    if (!slot) continue
    var along = vertical ? (slot.y + slot.height / 2) : (slot.x + slot.width / 2)
    var position = vertical ? point.y : point.x
    var distance = Math.abs(position - along)
    if (best === null || distance < best.distance) {
      best = { slot: slot, distance: distance, after: position > along }
    }
  }
  if (best === null) return null
  return { slot: best.slot, after: best.after }
}

if (typeof module !== "undefined") {
  module.exports = {
    SECTIONS: SECTIONS,
    cellIndexForPoint: cellIndexForPoint,
    clamp: clamp,
    dedupeLayout: dedupeLayout,
    displayLabel: displayLabel,
    dockInto: dockInto,
    dockedEntries: dockedEntries,
    dockHomeFor: dockHomeFor,
  setPendingDock: setPendingDock,
  pendingDock: pendingDock,
  clearPendingDock: clearPendingDock,
    dockedIds: dockedIds,
    dockZoneRects: dockZoneRects,
    pointInAnyRect: pointInAnyRect,
    pointInRect: pointInRect,
    droppedOnChevron: droppedOnChevron,
    entryId: entryId,
    findEntry: findEntry,
    drawerGrid: drawerGrid,
    gridRows: gridRows,
    idsOf: idsOf,
    isOnBar: isOnBar,
    landedAdjacentTo: landedAdjacentTo,
    layoutIds: layoutIds,
    layoutOf: layoutOf,
    nearestSlot: nearestSlot,
    needsPrune: needsPrune,
    pluginsList: pluginsList,
    pruneDocked: pruneDocked,
    reorderDocked: reorderDocked,
    sectionEntries: sectionEntries,
    undockFrom: undockFrom,
    visibleDocked: visibleDocked
  }
}
