# How Bar dock works

This is the engineering view: what the drawer is made of, why a docked icon is
parked rather than deleted, and which parts exist so the thing can be driven from
a terminal.

## The pieces

| File | What it is |
| --- | --- |
| `manifest.json` | The plugin manifest: id `ozz1ee.bardock`, kind `bar-widget`, entry point `BarDock.qml`, plus the settings schema. |
| `BarDock.qml` | The bar widget itself: the chevron, the drawer surface, the drag handling, the layout mutations, the IPC surface. |
| `DockTile.qml` | One docked icon: instantiates the plugin's own widget component and forwards clicks and drags. |
| `DockGhost.qml` | The drag ghost, a small window that follows the pointer while a tile is dragged out. |
| `Chevron.qml` | The mark: two strokes drawn as a `Shape`/`PathPolyline`, so it is an arrowhead and not a font glyph. |
| `Model.js` | All the logic that has no Qt in it: geometry, layout transforms, drop zones, hit tests. This is what `node --test` exercises. |

## Why a docked icon is parked, not removed

`PluginRegistry.isEnabled()` answers "is this widget on the bar" for a
third-party bar widget, and an entry that is not found anywhere in `shell.json`
is *disabled*: the shell unregisters the widget's component from
`bar.barWidgetRegistry` and the drawer would come up empty. Docking therefore
moves the entry from `bar.layout.right` into the top-level `plugins[]` array,
which `findEntryLocation()` counts as enabled. The plugin keeps its component,
its service (if it ships one) keeps running, and the bar stops drawing an icon
for it.

Each dock also records where the widget came from - the section and the id that
followed it - in the widget's own `dockHomes` map, so undocking returns the icon
to its old neighbours instead of appending it to the far end of the bar.

## Geometry: always a square, limited only by the screen

One cell per icon in a `ceil(sqrt(n))` grid, so the grid is as square as the
count allows and the drawer side is `max(columns, rows) * cell + inset`.

- The side grows with the icon count until it hits the largest square the screen
  can give it (screen height minus the bar, minus a margin each side).
- Past that, the cells shrink down to `minCell` (20 px by default) rather than the
  icons spilling out of the square, and only then does the span widen.
- `maxSide` is an optional cap on top of that; `0` means "no cap, the screen
  decides".
- The reorder hit test uses the cell size the tiles are actually drawn at, so a
  drawer whose cells had to shrink still drops icons into the cell under the
  cursor.

## The drawer surface

The drawer is a `PanelWindow` sized to the square plus a margin, anchored top
right, and masked to the square so input outside it passes through. It is *not* a
full-screen overlay: that would force the compositor to blend a whole screen's
worth of pixels every frame, which measured as several times the cost of the
drawer it contained.

Because the surface is only as big as the drawer, a point inside it is
surface-local, while everything outside it - the bar strip, the drop zone, the
drag ghost windows - is in screen coordinates. The crossing happens in one place
(`surfaceOrigin` / `toScreen`), and the drawer remembers its own position so the
bar-facing maths can convert.

Each tile instantiates the real widget component from `bar.barWidgetRegistry`
with the same `bar`, `moduleName` and `settings` the bar injects into a slot, so
a docked icon still ticks, still opens its panel, and keeps its settings.

Two details that took a while to get right:

- The widget must never sit inside an invisible ancestor. QML's `visible` reads
  *effective* visibility, and widgets legitimately compute their own size from it
  (`implicitWidth: visible ? button.implicitWidth : 0`). Hiding the loader made
  such a widget report 0x0 for ever, so the tile faded the loader with `opacity`
  instead and decides the widget's face only while the drawer is drawn.
- A widget that hides itself while healthy (an uptime widget while every site
  answers) is shown anyway in the drawer: an invisible cell cannot be clicked.

## Docking: the release point decides

The chevron is an ordinary bar-widget slot, so the bar's drag machinery can
target it, and its slot lights up as a landing pad while a drag that could dock
here is in flight. Its width never changes - growing it moved every neighbouring
slot out from under the cursor and made ordinary reordering on the bar unreliable.

The *decision* is made by the plugin, from the release point, not by the bar's
nearest-slot resolution: that resolution snaps to whichever slot is nearest, which
is fine for reordering but wrong for docking.

Two thresholds, deliberately different:

- The **drop zone** is the chevron's slot plus `dockZoneSlack` (32 px by default),
  and the open drawer. This is the target you aim at, so it is forgiving.
- The **open trigger** is the chevron's slot alone. Popping the drawer open while an
  icon is dragged along the bar disrupts reordering, so the drawer only appears once
  the dragged icon is really on the chevron - and that is also the cue that releasing
  now will dock.

A dock decided at release is then written into the widget's own entry as a *pending
dock*, not performed on a timer. That detail matters: the bar rebuilds its widget
instances when the layout changes, so the instance that decided the dock is usually
destroyed before a timer could run, and the dock was silently lost - the icon stayed
wherever the bar had put it, just before or just after the chevron. The entry survives
the rebuild, and whichever instance exists next finishes the job (the fresh instance
settles it at load, and every config change retries it). A pending dock older than a
few seconds is ignored.

A drop docks when the release lands anywhere in:

- the chevron's own slot,
- up to `dockZoneSlack` px to its left along the bar, or
- the drawer itself, below the bar.

The drawer opens as soon as the drag enters that zone, so the target is visible
before the button is released. Anything released outside the zone is left where
it landed.

## Writes that stick

`shell.json` writes are asynchronous and a write issued inside the shell's own
file-change callback is lost, so:

- writes are deferred out of that callback first,
- the intended change is remembered as an *intent* (dock / undock / reorder) and
  re-applied until the config actually agrees,
- a reorder is written once, on release.

## Driving it from a terminal

```bash
omarchy-shell ozz1ee.bardock toggle                 # open/close the drawer
omarchy-shell ozz1ee.bardock open | close
omarchy-shell ozz1ee.bardock dock <plugin-id>       # same as dropping it on the chevron
omarchy-shell ozz1ee.bardock undock <plugin-id>
omarchy-shell ozz1ee.bardock undockAll              # everything back on the bar
omarchy-shell ozz1ee.bardock state | jq             # what the drawer shows
omarchy-shell ozz1ee.bardock registry | jq          # widget catalogue the shell exposes
omarchy-shell ozz1ee.bardock dedupe                 # repair doubled layout entries
omarchy-shell ozz1ee.bardock sizeFor <n>            # drawer geometry for n icons
```

`bin/bardock` wraps these.

Seams for the parts a script cannot do without a pointer (they drive the same
code paths the gestures do):

```bash
omarchy-shell ozz1ee.bardock simulateLanding <id>    # drop <id> on the chevron
omarchy-shell ozz1ee.bardock armOnly <id>            # arm the drop window, move nothing
omarchy-shell ozz1ee.bardock dropAt <id> <x> <y>     # the drop half of a drag out, bar coords
omarchy-shell ozz1ee.bardock ghost <id> <x> <y>      # show the drag ghost + insertion marker
omarchy-shell ozz1ee.bardock clearGhost
omarchy-shell ozz1ee.bardock testDrag true|false     # raise the landing pad without a drag
omarchy-shell ozz1ee.bardock explainDrop <id>        # why a drop did or did not count
omarchy-shell ozz1ee.bardock zoneTest <id> <x> <y>   # run the dock-zone test at a screen point
omarchy-shell ozz1ee.bardock zoneRects               # the landing area, in screen coordinates
omarchy-shell ozz1ee.bardock reorderTest <id> <n>    # move a docked icon to slot n
omarchy-shell ozz1ee.bardock fakeDrag <id> <x> <y>   # which cell a screen point resolves to
omarchy-shell ozz1ee.bardock probeNow <id>           # a docked widget's face + ancestor chain
```

## Known limits

- Widgets whose bar face is wider than a cell (a 90 px system monitor) are
  centred in the cell rather than scaled; raise `cell` if that bothers you.
- Custom layout entries (`type: qml` / `command`, no manifest) have no component
  in the registry and always render as a plate with the entry's name.
- The drag ghost draws the widget's icon character, not a snapshot: Qt refuses
  `grabToImage` for an item inside the popup window, so no grabbed bitmap exists
  to show there.
- Docking is decided by where you let go, so reordering widgets inside the
  right-most stretch of the bar also docks them. Lower `dockZoneSlack` or set
  `dockOnNeighbourDrop` to `false` for the old strictness.

## Tests

`node --test test/*.test.js` covers the pure logic: the dock/undock/reorder transforms on
`shell.json` (settings preserved, `plugins[]` parking, `dockHomes`), the drop
adjacency and drag-source rules, the square/grid maths and its screen ceiling,
and the drop-target hit test. The QML side is verified live, through
`omarchy-shell ozz1ee.bardock state`, the shell's log
(`journalctl -t omarchy-shell | grep bardock`) and the bar's own geometry
(`omarchy-shell shell debugBarGeometry`).
