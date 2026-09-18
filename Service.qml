import QtQuick

// Sidecar for the widget catalogue.
//
// On Omarchy 4.0.3+ a third-party bar widget no longer receives the bar's own
// widget registry (`bar.barWidgetRegistry` was replaced by a capability-scoped
// facade that only carries scalar bar state). A *service* instance of the same
// plugin still receives it, because the host hands the catalogue to any
// entry-point instance that declares a `barWidgetRegistry` property.
//
// So this file exists to hold that one reference. The drawer asks for it through
// `bar.shell.serviceFor("ozz1ee.bardock").barWidgetRegistry` and renders the
// docked icons from it, exactly as it renders them from `bar.barWidgetRegistry`
// on 4.0.0-4.0.2. Everything else about docked widgets is unaffected by this
// instance: it runs no process, holds no state, touches no file and does no I/O.
Item {
  id: root

  // Injected by the host (raw registry on <=4.0.2, a detached catalogue snapshot
  // with `{id: {component, metadata}}` on 4.0.3+).
  property var barWidgetRegistry: null
}
