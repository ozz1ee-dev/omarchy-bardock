const test = require("node:test")
const assert = require("node:assert/strict")
const Compat = require("../Compat.js")
const fixtures = require("./fixtures/host-api.json")

// The host API differs between Quattro releases, and the plugin has to work on
// all of them. These tests run the detection against the *recorded* member lists
// of both generations (test/fixtures/host-api.json), so a release that changes
// the injected object cannot quietly flip the plugin onto the wrong path.
function valueOf(kind) {
  switch (kind) {
    case "function": return function () { return null }
    case "object": return {}
    case "array": return []
    case "number": return 0
    case "bool": return false
    case "string": return ""
    default: return null
  }
}

function hostFrom(members) {
  const host = {}
  for (const member of members) host[member.name] = valueOf(member.kind)
  return host
}

function barOf(generation) {
  const spec = fixtures.generations[generation]
  const bar = hostFrom(spec.bar)
  bar.shell = hostFrom(spec.shell)
  bar.barSize = 34
  bar.vertical = false
  return bar
}

function shellOf(generation) {
  return hostFrom(fixtures.generations[generation].shell)
}

for (const generation of Object.keys(fixtures.generations)) {
  const expected = fixtures.generations[generation].expected

  test(generation + ": detection matches the recorded host shape", () => {
    const bar = barOf(generation)
    assert.equal(Compat.hasLegacyHost(bar), expected.hasLegacyHost)
    assert.equal(Compat.hasHostCatalogue(bar), expected.hasHostCatalogue)
    assert.equal(Compat.hasHostConfig(bar), expected.hasHostConfig)
    assert.equal(Compat.canHostMutate(bar), expected.canHostMutate)
  })

  test(generation + ": the drawer offers the picker only without slot geometry", () => {
    const bar = barOf(generation)
    assert.equal(Compat.hasLegacyHost(bar) === false, expected.pickerAvailable)
  })

  test(generation + ": every host member the plugin reads exists on the shell object", () => {
    // bar.shell is read for the config on <=4.0.2 and for serviceFor() on all
    // releases; the scoped facade has no shellConfig, which is exactly why the
    // config falls back to the file there.
    const bar = barOf(generation)
    assert.equal(typeof bar.shell.serviceFor, "function")
    if (expected.hasHostConfig) assert.equal(typeof bar.shell.mutateShellConfig, "function")
  })
}

test("a missing bar is not mistaken for either generation", () => {
  assert.equal(Compat.hasLegacyHost(null), false)
  assert.equal(Compat.hasHostCatalogue(null), false)
  assert.equal(Compat.hasHostConfig(null), false)
  assert.equal(Compat.canHostMutate(null), false)
  assert.equal(Compat.catalogue(null, null), null)
})

test("the catalogue comes from the host bar when it has one", () => {
  const bar = barOf("legacy")
  bar.barWidgetRegistry = { widgets: { "demo.clock": { component: {}, metadata: {} } } }
  const widgets = Compat.catalogue(bar, { widgets: { "from.service": {} } })
  assert.deepEqual(Object.keys(widgets), ["demo.clock"])
})

test("the catalogue comes from our own service when the host has none", () => {
  const bar = barOf("scoped")
  const widgets = Compat.catalogue(bar, { widgets: { "demo.clock": { component: {} } } })
  assert.deepEqual(Object.keys(widgets), ["demo.clock"])
})

test("no catalogue anywhere is null, not an empty catalogue", () => {
  assert.equal(Compat.catalogue(barOf("scoped"), null), null)
  assert.equal(Compat.catalogue(barOf("scoped"), {}), null)
})

test("onBarIds walks left, center, right and skips us", () => {
  const layout = {
    left: [{ id: "demo.keys" }, "demo.indicators"],
    center: [{ id: "ozz1ee.bardock" }],
    right: [{ id: "omarchy.clock" }, { id: "harshith.system-monitor" }]
  }
  assert.deepEqual(Compat.onBarIds(layout, "ozz1ee.bardock"),
    ["demo.keys", "demo.indicators", "omarchy.clock", "harshith.system-monitor"])
})

test("onBarIds tolerates a missing or malformed layout", () => {
  assert.deepEqual(Compat.onBarIds(null, "ozz1ee.bardock"), [])
  assert.deepEqual(Compat.onBarIds({}, "ozz1ee.bardock"), [])
  assert.deepEqual(Compat.onBarIds({ left: null, right: [] }, "ozz1ee.bardock"), [])
})

test("dockableIds leaves out what is already hidden", () => {
  const layout = { left: [{ id: "a.one" }], center: [], right: [{ id: "b.two" }] }
  assert.deepEqual(Compat.dockableIds(layout, "ozz1ee.bardock", ["b.two"]), ["a.one"])
  assert.deepEqual(Compat.dockableIds(layout, "ozz1ee.bardock", []), ["a.one", "b.two"])
})

test("dockableIds does not offer a widget twice when a layout entry repeats", () => {
  const layout = { left: [{ id: "a.one" }], center: [], right: [{ id: "a.one" }] }
  assert.deepEqual(Compat.dockableIds(layout, "ozz1ee.bardock", []), ["a.one"])
})
