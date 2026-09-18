# Bar dock

## 0.8.1 - beta

- Fix: **an icon restored onto the bar lands in front of the chevron again.** The bar's
  "next visible" lookup skips the plugin's own slot, so a drawer tile released on the
  chevron resolved to the widget behind it: the icon landed *after* the chevron and
  walked the chevron one slot to the left on every restore. Both real-gesture
  resolutions are now covered (a release on the chevron, which resolves to the slot
  before it with `after=true`, and a release on the slot after it, which resolves to
  that widget with `after=false`), and a restore always inserts in front of the plugin's
  own entry - the 0.7.5 rule, the chevron stays in the corner. Verified with a real
  pointer over two dock/undock cycles on the 4.0.0-4.0.2 generation; the 4.0.3+ path is
  unaffected because without slot geometry it never resolves a slot candidate.

## 0.8.0 - beta

- **Runs on both plugin API generations.** Omarchy 4.0.0-4.0.2 hands a third-party
  bar widget the real bar object; 4.0.3 replaced that with capability-scoped
  facades that carry no shell config, no widget catalogue and no slot geometry.
  The plugin now detects which one it is talking to by asking for the members it
  uses - never by a version string - and keeps one code path for both. On the
  newer releases the drawer used to come up empty with the docked icons still
  parked in `shell.json`.
- **The icons keep their faces on 4.0.3+.** Where the bar no longer publishes its
  widget catalogue to a widget, this plugin's own `service` instance receives it
  (the host injects it into any entry-point instance that declares the property)
  and the drawer reads the catalogue from there. `Service.qml` exists for that
  one reference: it runs no process, holds no state and touches no file.
- **The config is written through whichever surface is available.** On
  4.0.0-4.0.2 that is the host's own `mutateShellConfig`; on 4.0.3+ the facade
  refuses a plain bar widget a config mutation, so the plugin reads and writes
  `~/.config/omarchy/shell.json` itself (the file the shell watches) and asks the
  shell to re-read it. Only the entry being docked, undocked or reordered is
  touched, and the write is verified against the file afterwards.
- **Docking without slot geometry.** On 4.0.3+ there is no drag state and no slot
  list to hit-test, so an icon cannot be dragged onto the chevron any more:
  right-clicking the chevron (or the small plus in the drawer's corner) opens a
  list of the widgets that are on the bar, and one click docks that widget.
  Dragging a tile out of the drawer and releasing it over the bar still puts it
  back, at the end of the right section. On 4.0.0-4.0.2 every gesture is exactly
  what it always was.
- **Quieter on the newer releases.** The two `Connections` onto the bar (drag
  source, shell config) are only instantiated where those members exist, instead
  of logging a QML warning on every bar rebuild.
- Tests: `test/compat.test.js` (14 tests) runs the detection against the recorded
  host shapes of both generations (`test/fixtures/host-api.json`), so a release
  that changes the injected object cannot quietly flip the plugin onto the wrong
  path. CI now runs both test files.

## 0.7.8 - beta

- Fix: **the drawer survives the plugin being disabled and enabled again.** Disabling a
  plugin removes its bar entry from `shell.json`, and re-enabling it adds a bare one - so
  the `docked` list that named the drawer's icons went with it and the drawer came up
  empty (the docked widgets themselves stayed parked in the shell's plugin list, with all
  their settings). Every docked entry now carries a marker, and a fresh entry adopts the
  marked entries back in their parked order - on the first bar change and on every config
  change, because the bar object arrives before the config does. Nothing is lost, and the
  drawer rebuilds itself.
- Fix: `dock <id>` (and docking in general) now accepts a widget that is already parked in
  the shell's plugin list, not only one sitting on the bar. Parking is a normal state for a
  docked icon, so the command has to be able to put a parked one back into the drawer.


## 0.7.7 - beta

- The development helper script is gone. It only linked a checkout into the shell's
  plugin directory and optionally put the widget on the bar, and the two commands are
  now documented inline in the README. Shipping it meant shipping a file shaped like an
  installer, which parks a submission in a manual security review for no reason: nothing
  in this repository installs anything.


## 0.7.6 - beta

- Fix: dragging an icon onto the chevron now **lands it in the drawer every time**.
  The dock was decided at release and then performed on a short timer, but the bar
  rebuilds its widget instances when the layout changes: the instance that decided the
  dock was destroyed together with its timer and the dock was silently lost. The icon
  stayed wherever the bar had put it - which is why it "sometimes landed in front of
  the chevron and sometimes behind it" and needed several attempts. The decision is now
  kept in the widget's own entry as a pending dock, and whichever instance exists next
  settles it; a pending dock older than a few seconds is ignored.
- Fix: the drop is forgiving again without disturbing anything else. `dockZoneSlack`
  defaults to 32 px around the chevron, while the drawer still opens **only** on the
  chevron itself - so the corner is easy to hit and an ordinary bar drag is untouched.


## 0.7.5 - beta

- Fix: **the drawer only opens when the dragged icon reaches the chevron.** The dock
  zone used to run from the chevron's slot to the screen edge, so dragging any icon
  along the last stretch of the bar opened the drawer under the cursor and a release
  there docked the icon instead of reordering it. The zone is now the chevron's own
  slot (plus `dockZoneSlack`, which defaults to `0` - set it if you want a wider
  pocket), so reordering icons along the bar is never disturbed and the drawer
  opening is the signal that releasing now will dock. `dockZoneSlack` no longer
  reaches towards the screen edge, and the geometry is covered by tests.
- Fix: an icon undocked with no remembered home lands **in front of the chevron**
  instead of at the far end of the bar, so the chevron stays in the corner and the
  icon comes back next to the drawer it came out of.
- Fix: dock arming now requires a live bar drag. A stale drag target (at startup, or
  after the bar rebuilt itself) could arm a dock that nobody asked for, and the next
  unrelated layout write would dock that widget - reproduced and covered.


## 0.7.4 - beta

- Fix: dropping an icon into the drawer no longer flashes plugin names where the
  icons should be. Docking one more icon changes the column count, so the whole
  grid is relaid out and a widget can report 0x0 for a frame; `decideFace()` took
  that single reading as proof that the widget has no face and swapped it for its
  name until the drawer was reopened. A "no face" reading is now re-checked before
  it is believed (up to three checks, 120 ms apart) and any positive reading wins
  immediately. Tiles also remember, per widget, whether it has a face, so a tile
  that the relayout rebuilds starts on the face instead of the name.
- Fix: the chevron's slot now keeps a **fixed width**. It used to widen while a
  drag was in flight, which pushed every neighbouring slot sideways under the
  cursor and made reordering icons along the bar feel unreliable. The landing pad is
  now a highlight drawn inside the same width, so no slot on the bar ever moves.


## 0.7.3 - beta

- Fix: **drag & drop actually works now, in both directions.** The root cause was a
  stale identifier: `dropTargetAt()` looked at `popupScenePoint`, a variable that
  does not exist in its scope, instead of its own `screenPoint` argument. Every
  drop ran into a `ReferenceError` halfway through, so a tile dragged out of the
  drawer never landed on the bar: the icon stayed in the drawer, the drawer stayed
  open holding its focus grab, and the desktop looked frozen. The same call sat on
  the path that reorders tiles inside the square, so reordering was broken too.
  This was present in the first public commit, which means the drop path never
  worked through the real handler; it was only ever exercised through test seams
  that call the model functions directly. All four gestures are now verified end to
  end with a real pointer: drawer to bar, bar to drawer, tile to tile, and back.
- Fix: 0.7.1's freeze guard treated "no pointer movement for 2.5 s" as a lost drag,
  so pausing while aiming aborted the gesture. Corrected in 0.7.2 and kept here:
  the dock checks whether a live pointer handler still owns the drag (every 250 ms)
  and clears only an orphaned one; a hand that holds still keeps its drag.
- The drawer can always be cleared by hand with
  `omarchy-shell ozz1ee.bardock reset`, which needs no pointer at all.


## 0.7.2 - beta

- Fix: **0.7.1 broke dragging out of the drawer, and this is the correction.** Its
  freeze fix cancelled a drag after 2.5 s without pointer movement, so any pause
  while aiming killed the gesture: the drawer briefly froze, then the icon dropped
  back into it. The guard is now about *orphaned* drags instead of idle ones - the
  dock checks every 250 ms whether a live pointer handler still owns the gesture,
  and clears the drag only when none does. A hand that holds still keeps its drag;
  a release that never arrives is cleared within a quarter of a second.
  `dragStallMs` remains as a generous last-resort guard, now 10 s.


## 0.7.1 - beta

- Fix: **a dropped pointer release could freeze the desktop.** If a drag out of the
  drawer ended without us seeing the release, the drag stayed live: the ghost icon
  stayed on screen, the drawer stayed open and its focus grab kept holding input, so
  nothing could be clicked. A drag with no live pointer behind it (checked every
  250 ms) is now cleared immediately, and `omarchy-shell ozz1ee.bardock reset`
  clears it on demand - it works even when the desktop looks frozen, because it
  needs no pointer. `dragStallMs` stays as a generous last-resort guard; an earlier
  revision of this fix used "no movement for 2.5 s", which cancelled real drags
  whenever the hand paused while aiming.
- Fix: **the chevron's slot no longer widens for every bar drag.** It used to open
  into a landing pad for the whole duration of any drag anywhere on the bar, which
  pushed the neighbouring icons sideways under the cursor and made ordinary
  reordering feel wrong. The strip now opens only when a drop there would actually
  dock: while the bar is dragging something *and* the pointer is inside the dock
  zone.
- Fix (development): the `fakeDrag` terminal seam no longer starts a real drag. It
  only reports which cell a screen point resolves to, so a forgotten call cannot
  leave a drag in flight.

## 0.7.0 - beta

- **The drawer has no size limit any more.** 0.6.0 and earlier capped the side at
  `maxSide` (420 px); past that the grid grew in rows while the square stayed put,
  so the icons ended up outside the square. The geometry is now: one cell per icon
  in a ceil(sqrt(n)) grid, the square grows with its contents, and the ceiling is
  the screen itself (the largest square that fits between the bar and the bottom
  edge). Past that ceiling the cells shrink (down to `minCell`, 20 px by default)
  instead of the icons spilling out, and then the span widens. Measured on a
  1600x1000 screen: 16 icons 212 px, 64 icons 396 px, 100 icons 488 px, 225 icons
  718 px - all beyond the old 420 px cap, all exactly square.
- `maxSide` keeps its meaning as an optional user cap, but defaults to 0 = no cap
  beyond the screen. New setting `minCell` says how small the icons may get.
- Fix: the reorder hit test now uses the same cell size the tiles are drawn at, so
  dragging inside a drawer whose cells had to shrink still lands on the cell under
  the cursor.

## 0.6.0 - beta

- **The drawer's surface is only as big as the drawer.** It used to be a
  full-screen transparent overlay, purely so that popup coordinates and screen
  coordinates were the same thing; compositing that every frame cost several times
  more than the drawer it contained. The surface is now the square plus a margin,
  anchored to the top right, and crossing between surface and screen coordinates
  happens in one place (`surfaceOrigin` / `toScreen`). Verified after the change:
  the grid hit test lands on the right cell for all 12 cells, the dock zone still
  accepts a drop 30 px before the chevron, and the card sits at exactly the same
  screen position as before.
- An animated ambient background was built, measured and then dropped at the
  user's request. It was cheap - in one measurement window with everything else
  held constant, `ambient off` read 16.7% of a core and `ambient` on read
  16.9-17.1%, so the wash itself cost ~0.2 pp; the drawer's own surface was the
  real cost, and that is what this release fixes. The ambient code is in the
  history (the commit before this one) if it is ever wanted back.
- Fix: sizing the surface to the square clipped the drawer's bottom edge - the
  square starts below the bar, so the height has to include that offset plus a
  margin each side. Spotted in use, verified by pixel: the bottom border row
  is now drawn in the same colour as the top one.

## 0.5.0 - beta

- **Fix: a widget that hides itself no longer collapses into a label in the
  drawer.** `Item.visible` reads *effective* visibility in QML, so the tile used
  to hide the loader holding the widget; a widget that sizes itself from its own
  visibility (`implicitWidth: visible ? button.implicitWidth : 0`, as uptime
  does) then reported 0x0 for ever and the tile fell back to a text plate. The
  loader now never hides (it fades instead), the face is decided only while the
  drawer is drawn, and the result is remembered between openings. All 13 docked
  icons in the live check render their real widget, so clicks reach the widget
  again. Reported from a real bar with 30+ installed plugins.
- A widget that hides itself while everything is healthy (uptime with
  `hideWhenHealthy`) is revealed in the drawer: an invisible cell has nothing to
  click. The bar rebuilds its own instance with its setting intact.
- Fix: no more `TypeError: Cannot read property 'ghostWindows' of null` when the
  shell tears down while a ghost window exists.
- `probeNow` reports the widget's face and its ancestor chain from the terminal.

## 0.4.0 - beta

- **Icons can be reordered inside the square.** Dragging a tile onto another cell
  changes its place in `docked[]` (which is the draw order). The dragged icon
  dims and the target cell draws an accent outline; the order is written once, on
  release, through the same deferred-write + retry path the dock uses, so it
  survives a restart. The cell under the pointer is resolved against the live grid
  (`Model.cellIndexForPoint`), verified pixel-exact against a 4x3 grid.
- Dropping a tile over the bar still undocks it; the two gestures share one drag
  and are told apart by where the release lands.
- `reorderTest`, `fakeDrag` and `gridOrigin` IPC seams, 48 model tests.

## 0.3.0 - beta

- **Docking no longer depends on the bar's drop resolution.** The bar resolves a
  drag to the nearest slot, so a release a few pixels before the chevron went to
  the neighbouring widget and a release past the end of the bar went nowhere. The
  gesture is now decided by the release point against a dock zone: the chevron's
  slot (84px while dragging), `dockZoneSlack` px to its left (56 by default), and
  the square below it. The square opens as soon as the drag enters the zone.
- The bar's drag id and pointer position are latched while the drag runs
  (`bar.barDragSource`, `bar.barDragScreenX/Y`), so the drop is evaluated on
  release with no dependence on where the bar would have inserted it.
- Docking remembers each widget's home (`section` + the id that followed it);
  `undock`, `undockAll` and dragging out of the square put it back there instead
  of appending it to the end of the bar. A missing anchor lands it in front of
  the chevron.
- New `dockZoneSlack` setting, `zoneTest`/`zoneRects` IPC seams, 44
  model tests.

## 0.2.0 - beta

Three things the first beta got wrong, found by using it:

- **Docking was flaky.** The drop was decided by a layout diff, which cannot see a
  widget that is already next to the chevron, and an unrelated `shell.json` write
  inside the arm window could dock the wrong icon. Docking is now decided by the
  bar's own drop target (`bar.barDragTarget`), and the write is deferred out of
  the shell's file-change callback plus re-applied until the config agrees - the
  earlier write was silently lost, so a docked icon came back on restart.
- **The chevron was a hard target.** The slot grows to 84px and shows a bordered
  landing pad while a bar drag is in flight.
- **Clicks and panels.** The tile's MouseArea swallowed every click (replaced by a
  DragHandler, so the widget's own press survives), and a docked widget's panel
  opened in the top-left corner. It now anchors to the chevron (the panel itself
  is a `PanelWindow`, reachable through the widget's `data`, not its `children`),
  and the square moved into a screen-spanning click-through overlay so panel
  coordinate maths matches the bar's.
- `explainDrop`, `armOnly`, `ghost`, `clearGhost` and `testDrag` IPC seams, 37
  model tests.

## 0.1.0 - beta

First working version, built against Omarchy 4.0.1 / Quickshell 0.3.1.

- Chevron drawn from two strokes in the bar's right corner; click opens the
  square, click again closes it.
- Square popup whose width and height are always the same number; the icon grid
  decides the side, clamped to the screen and to `minSide`/`maxSide`.
- Docked icons are the widgets themselves, instantiated from
  `bar.barWidgetRegistry` with `bar`/`moduleName`/`settings`, with a named plate
  as the fallback for widgets that render nothing.
- Docking parks the layout entry in `plugins[]` so the plugin stays enabled and
  keeps its component and service.
- Drag out of the square onto the bar: own ghost window, hit test against the
  bar's live slots, the bar's own insertion marker, drop lands under the cursor.
- Drag a bar icon onto the chevron to dock it: the square opens while the drag
  hovers the chevron and the dragged widget (read from `bar.barDragSource`) is
  docked on release.
- `undockAll`, `state`, `registry`, `dedupe` over IPC; `bin/bardock` wraps them.
- 31 model tests (`node --test test/`).

Known limits, listed in the README: no services are stopped (the entry stays
enabled), wide widgets are scaled into the cell, and custom `type: qml` /
`command` entries always render as plates.
