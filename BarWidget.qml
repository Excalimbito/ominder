import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TimeParser.js" as TimeParser

// Bell with the number of upcoming reminders, and the host for the
// management panel. Reads reminders.json directly; bin/ominder owns writes.
BarWidget {
  id: root
  moduleName: "io.github.excalimbito.ominder"

  readonly property string ominder: Qt.resolvedUrl("bin/ominder").toString().replace(/^file:\/\//, "")
  readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/ominder/reminders.json"
  property string stateText: "[]"

  // Upcoming reminders with `at` moved to the next fire time, soonest first.
  readonly property var reminders: {
    var list = []
    try { list = JSON.parse(root.stateText || "[]") } catch (e) { list = [] }
    var now = clock.date
    return list.map(function(entry) {
      var next = Object.assign({}, entry)
      if (entry.onCalendar) {
        var parsed = TimeParser.parse(entry.when, now)
        if (!parsed.error) next.at = parsed.at
      } else if (entry.everySeconds > 0 && entry.at * 1000 < now.getTime()) {
        // ponytail: assumes the interval kept ticking from creation; suspend drift is ignored
        next.at += Math.ceil((now.getTime() / 1000 - entry.at) / entry.everySeconds) * entry.everySeconds
      }
      return next
    }).filter(function(entry) {
      return entry.onCalendar || entry.everySeconds > 0 || entry.at * 1000 > now.getTime()
    }).sort(function(a, b) { return a.at - b.at })
  }

  function run(args) {
    Quickshell.execDetached([root.ominder].concat(args))
  }

  // ---- Panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  // With no reminders the bell is dimmed, or hidden when emptyBell is "hidden".
  readonly property bool hidden: root.reminders.length === 0 && root.setting("emptyBell", "dimmed") === "hidden"

  visible: !root.hidden
  implicitWidth: root.hidden ? 0 : button.implicitWidth
  implicitHeight: root.hidden ? 0 : button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  Component.onCompleted: root.run(["hypr-stub"])

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  FileView {
    id: stateFileView
    path: root.stateFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.stateText = text()
    onLoadFailed: root.stateText = "[]"
  }

  // The sweep also creates reminders.json, which the view cannot watch until it exists.
  Process {
    running: true
    command: [root.ominder, "sweep"]
    onExited: stateFileView.reload()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      item.reminders = Qt.binding(function() { return root.reminders })
      item.now = Qt.binding(function() { return clock.date })
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // `ominder panel` and the Super+Ctrl+Alt+R binding open the panel here.
  IpcHandler {
    target: "io.github.excalimbito.ominder"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.reminders.length > 0 && root.setting("showCount", true) ? "󰢌 " + root.reminders.length : "󰢌"
    dimmed: root.reminders.length === 0
    tooltipText: root.reminders.length === 1 ? "1 reminder" : root.reminders.length + " reminders"
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }
  }
}
