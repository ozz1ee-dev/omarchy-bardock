const test = require("node:test")
const assert = require("node:assert/strict")
const Model = require("../Model.js")

function config() {
  return {
    bar: {
      position: "top",
      centerAnchor: "omarchy.clock",
      layout: {
        left: [
          "demo.keys",
          { id: "omarchy.clock", format: "HH:mm" },
          "demo.indicators"
        ],
        center: [],
        right: [
          { id: "demo.mail", url: "http://home" },
          { id: "demo.notes" },
          { id: "ozz1ee.bardock" },
          { id: "omarchy.system-update" }
        ]
      }
    },
    plugins: [
      { id: "demo.shot", captureMode: "selection" },
      { id: "demo.stage" }
    ],
    disabledPlugins: ["omarchy.media"],
    version: 1
  }
}

const own = (doc) => Model.findEntry(doc, "ozz1ee.bardock").entry
const parked = (doc) => Model.idsOf(doc.plugins)

test("dockedEntries is empty until something is docked", () => {
  assert.deepEqual(Model.dockedEntries(config(), "ozz1ee.bardock"), [])
})

test("dockInto lifts the entry off the bar, settings and all", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")

  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.notes", "ozz1ee.bardock", "omarchy.system-update"])
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.mail"])
  assert.equal(Model.dockedEntries(doc, "ozz1ee.bardock")[0].url, "http://home")
})

test("dockInto parks the entry in plugins[] so the shell keeps the widget enabled", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")

  assert.deepEqual(parked(doc), ["demo.shot", "demo.stage", "demo.mail"])
  assert.equal(Model.findEntry(doc, "demo.mail").kind, "plugin")
})

test("dockInto ignores an id that is nowhere", () => {
  const doc = config()
  assert.equal(Model.dockInto(doc, "ozz1ee.bardock", "nope.not-here"), null)
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), [])
})

test("dockInto never docks the dock itself", () => {
  const doc = config()
  assert.equal(Model.dockInto(doc, "ozz1ee.bardock", "ozz1ee.bardock"), null)
})

test("dockInto does not duplicate an already docked id", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  assert.equal(Model.dockInto(doc, "ozz1ee.bardock", "demo.mail"), null)
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.mail"])
  assert.deepEqual(parked(doc), ["demo.shot", "demo.stage", "demo.mail"])
})

test("undockFrom puts the entry back where it was asked to", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "right", "demo.notes")

  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.mail", "demo.notes", "ozz1ee.bardock", "omarchy.system-update"])
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), [])
  assert.deepEqual(parked(doc), ["demo.shot", "demo.stage"])
})

test("undockFrom lands in front of the chevron when the anchor is gone", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "right", "someone.removed")

  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.notes", "demo.mail", "ozz1ee.bardock", "omarchy.system-update"])
})

test("a widget that is already parked can still be docked", () => {
  const doc = config()
  assert.equal(Model.isOnBar(doc, "demo.shot"), false)   // parked from the start

  assert.ok(Model.dockInto(doc, "ozz1ee.bardock", "demo.shot"))
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.shot"])
  assert.equal(Model.dockInto(doc, "ozz1ee.bardock", "demo.shot"), null)  // no duplicate
})

test("docked entries carry a marker, and a bare entry adopts them back", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")
  Model.sweepDockMarkers(doc, "ozz1ee.bardock")

  assert.equal(own(doc).docked.every((e) => e.dockedBy === "ozz1ee.bardock"), true)
  assert.equal(Model.adoptableDocked(doc, "ozz1ee.bardock").length, 2)

  // the disable/enable cycle: the bar entry comes back bare, the parked entries keep
  // their markers
  own(doc).docked = []
  assert.equal(Model.adoptDocked(doc, "ozz1ee.bardock"), 2)
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.mail", "demo.notes"])
})

test("the marker is dropped when an icon leaves the drawer", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.sweepDockMarkers(doc, "ozz1ee.bardock")

  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "right", "demo.notes")
  Model.sweepDockMarkers(doc, "ozz1ee.bardock")

  const onBar = Model.sectionEntries(Model.layoutOf(doc), "right")
    .find((e) => Model.entryId(e) === "demo.mail")
  assert.equal(Model.entryId(onBar), "demo.mail")
  assert.equal("dockedBy" in onBar, false)
})

test("a decided dock is kept in the entry until it is settled", () => {
  const doc = config()
  assert.equal(Model.pendingDock(doc, "ozz1ee.bardock"), null)

  assert.equal(Model.setPendingDock(doc, "ozz1ee.bardock", "demo.mail"), true)
  assert.equal(own(doc).pendingDock.id, "demo.mail")
  assert.equal(Model.pendingDock(doc, "ozz1ee.bardock", 6000), "demo.mail")

  assert.equal(Model.clearPendingDock(doc, "ozz1ee.bardock"), true)
  assert.equal(Model.pendingDock(doc, "ozz1ee.bardock"), null)
})

test("a stale pending dock is ignored", () => {
  const doc = config()
  Model.setPendingDock(doc, "ozz1ee.bardock", "demo.mail")
  own(doc).pendingDock.at = Date.now() - 60000

  assert.equal(Model.pendingDock(doc, "ozz1ee.bardock", 6000), null)
  assert.equal(Model.pendingDock(doc, "ozz1ee.bardock"), "demo.mail")
})

test("an icon with no remembered home lands in front of the chevron", () => {
  const doc = config()
  // hand-built state: docked without a home (pre-0.3 layout), nothing after us
  doc.bar.layout.right = [{ id: "ozz1ee.bardock", docked: [{ id: "demo.mail" }] }]

  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "", "")
  // In front of us, never past us: the chevron guards the corner of the bar.
  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.mail", "ozz1ee.bardock"])
})

test("undockFrom can put a docked widget back in another section", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "left", "omarchy.clock")

  assert.deepEqual(Model.idsOf(doc.bar.layout.left), ["demo.keys", "demo.mail", "omarchy.clock", "demo.indicators"])
})

test("undockFrom falls back to the right section for a bogus one", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "nonsense", "")

  assert.deepEqual(
    Model.idsOf(doc.bar.layout.right),
    ["demo.notes", "demo.mail", "ozz1ee.bardock", "omarchy.system-update"],
  )
})

test("dock then undock round-trips the layout", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "right", "demo.notes")

  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.mail", "demo.notes", "ozz1ee.bardock", "omarchy.system-update"])
  assert.deepEqual(parked(doc), ["demo.shot", "demo.stage"])
  assert.deepEqual(own(doc).docked, [])
})

test("visibleDocked hides a widget the bar is drawing again", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")

  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.mail", "demo.notes"])

  // the bar's own drag puts one back beside the chevron without telling us
  doc.bar.layout.right.splice(2, 0, { id: "demo.mail" })
  assert.deepEqual(Model.visibleDocked(doc, "ozz1ee.bardock").map(Model.entryId), ["demo.notes"])
})

test("needsPrune is quiet until docked[] goes stale", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  assert.equal(Model.needsPrune(doc, "ozz1ee.bardock"), false)

  doc.bar.layout.right.splice(2, 0, { id: "demo.mail" })
  assert.equal(Model.needsPrune(doc, "ozz1ee.bardock"), true)
})

test("pruneDocked drops entries that are back on the bar and reports the rest", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")
  doc.bar.layout.right.splice(2, 0, { id: "demo.mail" })
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.notes", "right", "")
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")

  assert.deepEqual(Model.pruneDocked(doc, "ozz1ee.bardock").map(Model.entryId), ["demo.notes"])
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.notes"])
  assert.deepEqual(Model.pruneDocked(doc, "ozz1ee.bardock"), [])
})

test("landedAdjacentTo names the entry the bar just dropped beside us", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  assert.equal(Model.landedAdjacentTo(doc, "ozz1ee.bardock", previous), "")
})

test("landedAdjacentTo sees a widget dropped from elsewhere onto the chevron", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  doc.bar.layout.right.splice(2, 0, { id: "demo.tidy" })
  assert.equal(Model.landedAdjacentTo(doc, "ozz1ee.bardock", previous), "demo.tidy")
})

test("landedAdjacentTo sees an entry arriving after the chevron too", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  doc.bar.layout.right.splice(3, 0, { id: "demo.audio" })
  assert.equal(Model.landedAdjacentTo(doc, "ozz1ee.bardock", previous), "demo.audio")
})

test("landedAdjacentTo ignores changes somewhere else on the bar", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  doc.bar.layout.right.unshift({ id: "demo.sysmon" })
  assert.equal(Model.landedAdjacentTo(doc, "ozz1ee.bardock", previous), "")
})

test("drawerGrid keeps the drawer a perfect square", () => {
  const g = (n, bound) => Model.drawerGrid(n, 46, 20, bound, 28)

  assert.deepEqual(g(1, 964), { columns: 1, rows: 1, cell: 46, side: 74 })
  assert.deepEqual(g(4, 964), { columns: 2, rows: 2, cell: 46, side: 120 })
  assert.deepEqual(g(9, 964), { columns: 3, rows: 3, cell: 46, side: 166 })
  // 10..16 icons: a 4x4 square with the last row half full
  assert.deepEqual(g(10, 964), { columns: 4, rows: 3, cell: 46, side: 212 })
  assert.deepEqual(g(16, 964), { columns: 4, rows: 4, cell: 46, side: 212 })

  // square means square: the grid never grows past the square it lives in
  for (let n = 1; n <= 400; n++) {
    const r = g(n, 964)
    assert.ok(r.rows <= r.columns, "rows " + r.rows + " > columns " + r.columns + " at " + n)
    assert.ok(r.columns * r.cell + 28 <= r.side + 1, "grid wider than the square at " + n)
  }
})

test("drawerGrid has no fixed cap: the screen is what stops it", () => {
  // the old release capped the side at 420 px, which pushed icons out of the square
  const big = Model.drawerGrid(100, 46, 20, 964, 28)
  assert.equal(big.columns, 10)
  assert.equal(big.side, 488)
  assert.ok(big.side > 420)

  // grows monotonically with the icon count
  let previous = 0
  for (let n = 1; n <= 200; n++) {
    const side = Model.drawerGrid(n, 46, 20, 964, 28).side
    assert.ok(side >= previous, "side shrank at " + n)
    previous = side
  }
})

test("drawerGrid shrinks the cells before it spills out of the square", () => {
  // 100 icons in a 300 px space: the square stays under 300, the cells get smaller
  const tight = Model.drawerGrid(100, 46, 20, 300, 28)
  assert.ok(tight.side <= 300)
  assert.ok(tight.cell < 46 && tight.cell >= 20)
  assert.ok(tight.columns * tight.cell + 28 <= tight.side + 1)

  // past minCell the span widens instead, and the square is clamped to the room
  const packed = Model.drawerGrid(400, 46, 20, 120, 28)
  assert.equal(packed.cell, 20)
  assert.equal(packed.side, 120)
  assert.equal(packed.columns, 4)
  assert.equal(packed.rows, 100)
})

test("gridRows rounds up", () => {
  assert.equal(Model.gridRows(0, 4), 1)
  assert.equal(Model.gridRows(9, 3), 3)
  assert.equal(Model.gridRows(5, 2), 3)
})

test("nearestSlot picks the closest slot and the side of it", () => {
  const slots = [
    { id: "a", x: 0, y: 0, width: 27, height: 26 },
    { id: "b", x: 27, y: 0, width: 27, height: 26 },
    { id: "c", x: 54, y: 0, width: 27, height: 26 }
  ]
  assert.equal(Model.nearestSlot(slots, { x: 5, y: 13 }, false).slot.id, "a")
  assert.equal(Model.nearestSlot(slots, { x: 20, y: 13 }, false).slot.id, "a")
  assert.equal(Model.nearestSlot(slots, { x: 20, y: 13 }, false).after, true)
  assert.equal(Model.nearestSlot(slots, { x: 40, y: 13 }, false).slot.id, "b")
  assert.equal(Model.nearestSlot(slots, { x: 200, y: 13 }, false).slot.id, "c")
  assert.equal(Model.nearestSlot([], { x: 0, y: 0 }, false), null)
})

test("nearestSlot follows the bar axis on a vertical bar", () => {
  const slots = [
    { id: "a", x: 0, y: 0, width: 26, height: 27 },
    { id: "b", x: 0, y: 27, width: 26, height: 27 }
  ]
  assert.equal(Model.nearestSlot(slots, { x: 13, y: 35 }, true).slot.id, "b")
  assert.equal(Model.nearestSlot(slots, { x: 13, y: 35 }, true).after, false)
  assert.equal(Model.nearestSlot(slots, { x: 13, y: 50 }, true).after, true)
})

test("displayLabel is readable without a registry", () => {
  assert.equal(Model.displayLabel("demo.uptime"), "Uptime")
  assert.equal(Model.displayLabel("demo.mail"), "Mail")
})

test("layoutIds reports every section", () => {
  const ids = Model.layoutIds(config())
  assert.deepEqual(ids.left, ["demo.keys", "omarchy.clock", "demo.indicators"])
  assert.deepEqual(ids.center, [])
  assert.equal(ids.right.length, 4)
})

test("dedupeLayout keeps the first copy of a doubled id", () => {
  const doc = config()
  doc.bar.layout.right.splice(2, 0, { id: "demo.mail" })
  assert.equal(Model.dedupeLayout(doc), 1)
  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.mail", "demo.notes", "ozz1ee.bardock", "omarchy.system-update"])
})

test("dedupeLayout removes entries with no id at all", () => {
  const doc = config()
  doc.bar.layout.left.push({})
  assert.equal(Model.dedupeLayout(doc), 1)
  assert.equal(Model.idsOf(doc.bar.layout.left).length, 3)
})

test("dedupeLayout is a no-op on a clean layout", () => {
  assert.equal(Model.dedupeLayout(config()), 0)
})

test("isOnBar is false for a parked entry and true for a laid-out one", () => {
  const doc = config()
  assert.equal(Model.isOnBar(doc, "demo.mail"), true)
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  assert.equal(Model.isOnBar(doc, "demo.mail"), false)
  assert.equal(Model.isOnBar(doc, "nope"), false)
})

test("landedAdjacentTo needs exactly one arrival and no departure", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  // a widget moving inside the section is a reorder, not an arrival
  doc.bar.layout.right.splice(2, 0, doc.bar.layout.right.splice(0, 1)[0])
  assert.equal(Model.landedAdjacentTo(doc, "ozz1ee.bardock", previous), "")
})

test("droppedOnChevron accepts a widget the bar dropped on our slot", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  // the common case: it was already next to the chevron, so nothing moves
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "demo.notes", "ozz1ee.bardock"), true)
})

test("droppedOnChevron accepts a widget that moved next to us", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  const entry = doc.bar.layout.right.splice(0, 1)[0]
  doc.bar.layout.right.splice(2, 0, entry)
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "demo.mail", "ozz1ee.bardock"), true)
})

test("droppedOnChevron refuses a drop on any other slot", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "demo.mail", "omarchy.network"), false)
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "demo.mail", ""), false)
})

test("droppedOnChevron refuses a candidate that is not on the bar", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "demo.mail", "ozz1ee.bardock"), false)
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "", "ozz1ee.bardock"), false)
})

test("droppedOnChevron accepts a widget arriving from another section", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  const entry = doc.bar.layout.left.splice(0, 1)[0]
  doc.bar.layout.right.splice(2, 0, entry)
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "demo.keys", "ozz1ee.bardock"), true)
})

test("droppedOnChevron ignores an unrelated config write", () => {
  const doc = config()
  const previous = Model.idsOf(doc.bar.layout.right)
  // nothing moved, and no drop targeted us
  assert.equal(Model.droppedOnChevron(doc, "ozz1ee.bardock", previous, "demo.mail", ""), false)
})

test("pointInRect is inclusive on both edges", () => {
  const rect = { x: 10, y: 10, width: 20, height: 20 }
  assert.equal(Model.pointInRect({ x: 10, y: 10 }, rect), true)
  assert.equal(Model.pointInRect({ x: 30, y: 30 }, rect), true)
  assert.equal(Model.pointInRect({ x: 9, y: 20 }, rect), false)
  assert.equal(Model.pointInRect({ x: 20, y: 31 }, rect), false)
})

test("dockZoneRects is the chevron's own slot, so the bar can be reordered untouched", () => {
  const square = { x: 1427, y: 31, width: 168, height: 168 }
  const rects = Model.dockZoneRects(1548, 0, 34, 26, 1600, square, 0)

  assert.equal(Model.pointInAnyRect({ x: 1565, y: 13 }, rects), true)   // on the chevron
  assert.equal(Model.pointInAnyRect({ x: 1549, y: 2 }, rects), true)    // its top edge
  assert.equal(Model.pointInAnyRect({ x: 1530, y: 13 }, rects), false)  // 18px to the left: a neighbour
  assert.equal(Model.pointInAnyRect({ x: 1590, y: 13 }, rects), false)  // past the slot
  assert.equal(Model.pointInAnyRect({ x: 1500, y: 120 }, rects), true)  // over the open drawer
  assert.equal(Model.pointInAnyRect({ x: 800, y: 13 }, rects), false)   // middle of the bar
})

test("dockZoneRects honours a requested pocket on both sides", () => {
  const rects = Model.dockZoneRects(1548, 0, 34, 26, 1600, null, 24)

  assert.equal(Model.pointInAnyRect({ x: 1526, y: 13 }, rects), true)   // 22px left, inside the pocket
  assert.equal(Model.pointInAnyRect({ x: 1518, y: 13 }, rects), false)  // 30px left, outside it
  assert.equal(Model.pointInAnyRect({ x: 1580, y: 13 }, rects), true)   // 32px right, still inside
})

test("dockZoneRects works without a square (closed) and never goes negative", () => {
  const rects = Model.dockZoneRects(10, 0, 34, 26, 1600, null, 24)
  assert.equal(rects.length, 1)
  assert.equal(rects[0].x, 0)
  assert.equal(Model.pointInAnyRect({ x: 5, y: 13 }, rects), true)
})

test("dockZoneRects never runs past the screen edge", () => {
  const rects = Model.dockZoneRects(1580, 0, 34, 26, 1600, null, 40)
  assert.equal(rects[0].x + rects[0].width <= 1600, true)
  assert.equal(Model.pointInAnyRect({ x: 1599, y: 13 }, rects), true)
})

test("undocking with no target puts the widget back where it came from", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")        // first in right
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.mail", "demo.notes"])

  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "", "")
  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.mail", "ozz1ee.bardock", "omarchy.system-update"])

  Model.undockFrom(doc, "ozz1ee.bardock", "demo.notes", "", "")
  assert.deepEqual(Model.idsOf(doc.bar.layout.right), ["demo.mail", "demo.notes", "ozz1ee.bardock", "omarchy.system-update"])
})

test("an explicit drop target beats the remembered home", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "left", "")
  assert.deepEqual(Model.idsOf(doc.bar.layout.left).slice(-1)[0], "demo.mail")
  assert.equal(Model.dockHomeFor(doc, "ozz1ee.bardock", "demo.mail"), null)
})

test("a home is remembered per widget and cleared on undock", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  assert.deepEqual(Model.dockHomeFor(doc, "ozz1ee.bardock", "demo.mail"), { section: "right", before: "demo.notes" })
  Model.undockFrom(doc, "ozz1ee.bardock", "demo.mail", "", "")
  assert.equal(Model.dockHomeFor(doc, "ozz1ee.bardock", "demo.mail"), null)
})

test("cellIndexForPoint maps a point to a grid cell, clamped to the icons", () => {
  const origin = { x: 100, y: 50 }
  assert.equal(Model.cellIndexForPoint({ x: 100, y: 50 }, origin, 46, 2, 4), 0)
  assert.equal(Model.cellIndexForPoint({ x: 146, y: 50 }, origin, 46, 2, 4), 1)
  assert.equal(Model.cellIndexForPoint({ x: 100, y: 96 }, origin, 46, 2, 4), 2)
  assert.equal(Model.cellIndexForPoint({ x: 146, y: 96 }, origin, 46, 2, 4), 3)
  // outside the grid clamps to the nearest cell
  assert.equal(Model.cellIndexForPoint({ x: 20, y: 20 }, origin, 46, 2, 4), 0)
  assert.equal(Model.cellIndexForPoint({ x: 400, y: 400 }, origin, 46, 2, 4), 3)
  // a half-filled last row clamps to the last icon
  assert.equal(Model.cellIndexForPoint({ x: 146, y: 96 }, origin, 46, 2, 3), 2)
  assert.equal(Model.cellIndexForPoint({ x: 0, y: 0 }, origin, 46, 2, 0), -1)
})

test("reorderDocked moves an icon to another slot", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")
  Model.dockInto(doc, "ozz1ee.bardock", "omarchy.system-update")

  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.mail", "demo.notes", "omarchy.system-update"])

  assert.equal(Model.reorderDocked(doc, "ozz1ee.bardock", "omarchy.system-update", 0), true)
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["omarchy.system-update", "demo.mail", "demo.notes"])

  assert.equal(Model.reorderDocked(doc, "ozz1ee.bardock", "omarchy.system-update", 2), true)
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.mail", "demo.notes", "omarchy.system-update"])
})

test("reorderDocked is a no-op for the same slot and clamps the rest", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")

  assert.equal(Model.reorderDocked(doc, "ozz1ee.bardock", "demo.mail", 0), false)
  assert.equal(Model.reorderDocked(doc, "ozz1ee.bardock", "demo.mail", 99), true)
  assert.deepEqual(Model.dockedIds(doc, "ozz1ee.bardock"), ["demo.notes", "demo.mail"])
  assert.equal(Model.reorderDocked(doc, "ozz1ee.bardock", "nope.not-here", 0), false)
})

test("reordering keeps each entry's settings with it", () => {
  const doc = config()
  Model.dockInto(doc, "ozz1ee.bardock", "demo.mail")
  Model.dockInto(doc, "ozz1ee.bardock", "demo.notes")
  Model.reorderDocked(doc, "ozz1ee.bardock", "demo.mail", 1)

  assert.deepEqual(Model.dockedEntries(doc, "ozz1ee.bardock")[1], { id: "demo.mail", url: "http://home" })
})

