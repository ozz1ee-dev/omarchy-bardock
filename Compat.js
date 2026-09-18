// Which plugin API generation we are running on.
//
// Omarchy 4.0.0-4.0.2 injected the *real* bar object into a third-party bar
// widget: `bar.shell` was the host ShellRoot (with shellConfig) and
// `bar.barWidgetRegistry` the live widget catalogue. 4.0.3 replaced that with
// capability-scoped facades (Ui/PluginBarApi.qml + services/PluginShellApi.qml)
// that carry neither the shell config, nor the widget catalogue, nor the slot
// geometry the drop zone is built from.
//
// Detection asks for the members we actually use, never for a version string:
// a probe that guesses a version is wrong again on the next release, a probe
// that asks for what it needs is right for as long as the API keeps its shape.
//
// Qt-free on purpose, so `node --test` can exercise it.

var SECTIONS = ["left", "center", "right"]

function member(target, name) {
  return !!target && target[name] !== undefined && target[name] !== null
}

// The real Bar instance: only it has the slot list the drop zone is hit-tested
// against.
function hasLegacyHost(bar) {
  return member(bar, "moduleSlots")
}

// The live widget catalogue, as only the real bar exposes it.
function hasHostCatalogue(bar) {
  return member(bar, "barWidgetRegistry")
}

// The whole shell.json through the host. On 4.0.3+ the facade's
// mutateShellConfig() exists but answers `false` for a plain bar widget (it
// needs the `bar` kind), and its barConfig is only the `bar` half of the file,
// so the plugin treats the host as a writer only when this is true.
function hasHostConfig(bar) {
  return !!(bar && bar.shell && bar.shell.shellConfig !== undefined)
}

function canHostMutate(bar) {
  return hasHostConfig(bar)
}

// {id: {component, metadata}} or null. `ownServiceRegistry` is the
// registry handed to this plugin's own service instance, which is the only
// route to the catalogue on 4.0.3+.
function catalogue(bar, ownServiceRegistry) {
  if (hasHostCatalogue(bar)) return bar.barWidgetRegistry.widgets || null
  if (ownServiceRegistry && ownServiceRegistry.widgets) return ownServiceRegistry.widgets
  return null
}

// A layout entry is either an id string or an object carrying one; both
// spellings appear in shell.json (Model.entryId is the same rule).
function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry && typeof entry === "object" && entry.id !== undefined) return String(entry.id)
  return ""
}

// Ids sitting on the bar, in bar order. `layoutConfig` exists in both
// generations: the host Bar exposes it and the facade mirrors a detached copy.
function onBarIds(layoutConfig, selfId) {
  var out = []
  if (!layoutConfig || typeof layoutConfig !== "object") return out
  for (var s = 0; s < SECTIONS.length; s++) {
    var entries = layoutConfig[SECTIONS[s]]
    if (!entries || entries.length === undefined) continue
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      if (!id || id === String(selfId || "")) continue
      if (out.indexOf(id) === -1) out.push(id)
    }
  }
  return out
}

// What a dock picker may offer: on the bar, not us, not already hidden.
function dockableIds(layoutConfig, selfId, docked) {
  var have = docked || []
  return onBarIds(layoutConfig, selfId).filter(function(id) {
    return have.indexOf(id) === -1
  })
}

if (typeof module !== "undefined") {
  module.exports = {
    hasLegacyHost: hasLegacyHost,
    hasHostCatalogue: hasHostCatalogue,
    hasHostConfig: hasHostConfig,
    canHostMutate: canHostMutate,
    catalogue: catalogue,
    onBarIds: onBarIds,
    dockableIds: dockableIds
  }
}
