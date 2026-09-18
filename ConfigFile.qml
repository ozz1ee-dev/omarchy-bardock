import QtQuick
import Quickshell
import Quickshell.Io

// shell.json as a file, for the generation of the plugin API that does not hand
// a bar widget the whole document.
//
// Why a file: on Omarchy 4.0.3+ a third-party bar widget gets capability-scoped
// facades. `bar.shell.barConfig` is a detached copy of the `bar` half only, and
// `bar.shell.mutateShellConfig()` refuses a widget without the `bar` kind - but
// docking has to move another plugin's entry between `bar.layout` and the
// top-level `plugins[]` array, which only the whole document allows. The file is
// the documented config surface, the shell watches it (its own FileView has
// watchChanges), and `omarchy-shell shell reloadConfig` is there to nudge it.
//
// Root is an Item, not a QtObject: FileView/Timer/Process need a default
// property to live in, and only a visual item type has one.
Item {
  id: configFile

  implicitWidth: 0
  implicitHeight: 0
  visible: false

  readonly property string path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

  // FileView.text() is a function and the type has no textChanged signal, so the
  // content is cached here and refreshed from fileChanged/saved.
  property string text: ""
  readonly property bool ready: text !== ""
  property int writes: 0
  property int failures: 0
  property int refreshes: 0

  // Parsed shell.json, or null while the file is unreadable or garbled.
  readonly property var document: {
    if (!ready) return null
    try {
      var parsed = JSON.parse(text)
      return parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      return null
    }
  }

  function refresh() {
    text = fileView.text() || ""
    refreshes += 1
  }

  // Read-modify-write. `mutator` gets a private copy; returning false from it
  // aborts the write. Returns whether the write was issued.
  function mutate(mutator) {
    if (!ready) {
      failures += 1
      console.log("bardock: cannot write shell.json (not read yet)")
      return false
    }
    var current = document
    if (!current) {
      failures += 1
      console.log("bardock: cannot write shell.json (does not parse)")
      return false
    }
    var next
    try {
      next = JSON.parse(JSON.stringify(current))
    } catch (e) {
      failures += 1
      return false
    }
    if (mutator(next) === false) return false
    next.version = 1
    fileView.setText(JSON.stringify(next, null, 2) + "\n")
    writes += 1
    // The shell's watcher usually picks the file up on its own; asking once more
    // is cheap and covers a dropped inotify event. Not immediate: the file has to
    // have hit the disk first.
    reloadTimer.restart()
    return true
  }

  FileView {
    id: fileView
    path: configFile.path
    watchChanges: true
    atomicWrites: true
    printErrors: true
    onLoaded: configFile.refresh()
    onFileChanged: configFile.refresh()
    onSaved: configFile.refresh()
  }

  // The first read is asynchronous, and a view watching a path that does not
  // exist yet emits neither onLoaded nor onLoadFailed - so the poll is the belt
  // to the brace. It stops the moment the file has been read.
  Timer {
    id: readyPoll
    interval: 400
    repeat: true
    running: !configFile.ready
    onTriggered: configFile.refresh()
  }

  Component.onCompleted: configFile.refresh()

  Timer {
    id: reloadTimer
    interval: 350
    onTriggered: reloadProcess.running = true
  }

  Process {
    id: reloadProcess
    command: ["omarchy-shell", "shell", "reloadConfig"]
    onExited: function(code) {
      if (code !== 0) console.log("bardock: reloadConfig exited " + code)
    }
  }
}
