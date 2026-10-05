import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "TimeParser.js" as TimeParser

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string editId: ""
  property string fontFamily: Style.font.menuFamily
  readonly property string ominder: Qt.resolvedUrl("bin/ominder").toString().replace(/^file:\/\//, "")

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  readonly property int cornerRadius: Style.cornerRadius
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(root.floating ? 480 : 380), panel.width - Style.gapsOut * 2)
  readonly property int drumSize: Style.font.displayLarge * 3
  property int cardHeight: contentMargin * 2 + form.implicitHeight

  readonly property var parsed: TimeParser.parse(whenField.text, clock.date)
  readonly property bool valid: !parsed.error

  // Settings come from the plugin's shell.json entry, read the same way bin/ominder reads them.
  readonly property string shellConfigFile: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
  property var settings: ({})
  readonly property bool floating: root.settings.style !== "classic"
  readonly property bool animate: root.settings.performanceMode !== true

  // Floating style: the drum shows the parsed time, the last valid one while the text is invalid,
  // and the current time while it is empty. +1 / -1 while a scroll step rolls the drum.
  property var lastValid: null
  property int stepDirection: 0
  readonly property bool hasText: whenField.text.trim() !== ""
  readonly property date drumDate: !root.parsed.error ? new Date(root.parsed.at * 1000) : (root.hasText && root.lastValid ? root.lastValid : clock.date)
  readonly property bool drumLive: !root.parsed.error && !root.parsed.everySeconds

  onParsedChanged: if (!root.parsed.error) root.lastValid = new Date(root.parsed.at * 1000)

  function readSettings(text) {
    var config = ({})
    try { config = JSON.parse(text) } catch (e) { return }
    var id = (root.manifest && root.manifest.id) || "io.github.excalimbito.ominder"
    var layout = (config.bar && config.bar.layout) || {}
    var entries = [].concat(layout.left || [], layout.center || [], layout.right || [], config.plugins || [])
    for (var i = 0; i < entries.length; i++)
      if (entries[i] && entries[i].id === id) { root.settings = entries[i]; return }
    root.settings = ({})
  }

  // Moves the when text by `minutes`; interval repeats and unrecognized text stay put.
  function step(minutes) {
    var next = TimeParser.shift(whenField.text, minutes, clock.date)
    if (next === null) return
    root.stepDirection = minutes > 0 ? 1 : -1
    whenField.text = next
    root.stepDirection = 0
  }

  // Up / Down step a minute, with Shift an hour.
  function stepKey(event) {
    if (!root.floating || (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down)) return
    root.step((event.key === Qt.Key_Up ? 1 : -1) * (event.modifiers & Qt.ShiftModifier ? 60 : 1))
    event.accepted = true
  }

  // `omarchy-shell shell call <id> parse "<when>"` — bin/ominder resolves times here.
  function parse(when) {
    var result = TimeParser.parse(when)
    result.preview = TimeParser.describe(result)
    return JSON.stringify(result)
  }

  // Payload: {} to create, {id, when, message} to edit.
  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    root.editId = payload.id || ""
    root.lastValid = null
    whenField.text = payload.when || ""
    messageField.text = payload.message || ""
    root.opened = true

    Qt.callLater(function() { whenField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "omarchy.reminders")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function clearOrDismiss(field) {
    if (field.text) field.text = ""
    else root.dismiss()
  }

  function submit() {
    if (!root.valid) {
      whenField.forceActiveFocus()
      return
    }

    var args = root.editId ? [root.ominder, "edit", root.editId] : [root.ominder]
    args.push(whenField.text.trim())
    if (messageField.text.trim()) args.push(messageField.text.trim())
    root.dismiss()
    Quickshell.execDetached(args)
  }

  SystemClock {
    id: clock
    enabled: root.opened
    precision: SystemClock.Minutes
  }

  FileView {
    path: root.shellConfigFile
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readSettings(text())
  }

  // One column of the floating drum: the value with its neighbours dimmed above and below.
  // The wheel steps it by `minutes`; a step rolls the column toward the new value.
  component DrumColumn: Item {
    id: drum

    property int value: 0
    property int count: 60
    property int minutes: 1
    property real offset: 0
    property real wheelDelta: 0

    implicitWidth: metrics.advanceWidth("00")
    implicitHeight: metrics.height * 2
    clip: true

    onValueChanged: {
      if (root.stepDirection === 0 || !root.animate) return
      roll.stop()
      drum.offset = root.stepDirection * metrics.height
      roll.start()
    }

    FontMetrics {
      id: metrics
      font.family: root.fontFamily
      font.pixelSize: root.drumSize
    }

    NumberAnimation {
      id: roll
      target: drum
      property: "offset"
      to: 0
      duration: 120
      easing.type: Easing.OutCubic
    }

    Column {
      y: drum.offset - metrics.height * 1.5
      width: parent.width

      Repeater {
        model: 5

        Text {
          required property int index
          width: parent.width
          height: metrics.height
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: ("0" + (drum.value + index - 2 + drum.count) % drum.count).slice(-2)
          color: root.foreground
          opacity: index === 2 ? 1 : 0.25
          font.family: root.fontFamily
          font.pixelSize: root.drumSize
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onWheel: function(wheel) {
        drum.wheelDelta += wheel.angleDelta.y
        while (Math.abs(drum.wheelDelta) >= 120) {
          var direction = drum.wheelDelta > 0 ? 1 : -1
          drum.wheelDelta -= direction * 120
          root.step(direction * drum.minutes)
        }
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-reminders"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    // Classic style draws the card; floating style leaves the fields on the scrim.
    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.floating ? "transparent" : root.background
      borderSpec: root.floating ? Border.none() : root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: form
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        Row {
          visible: root.floating
          anchors.horizontalCenter: parent.horizontalCenter
          opacity: root.drumLive ? 1 : 0.45

          DrumColumn {
            value: root.drumDate.getHours()
            count: 24
            minutes: 60
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: ":"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.drumSize
          }

          DrumColumn {
            value: root.drumDate.getMinutes()
            count: 60
            minutes: 1
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: root.floating ? Text.AlignHCenter : Text.AlignLeft
          textFormat: Text.PlainText
          text: root.floating
            ? (root.hasText ? TimeParser.describe(root.parsed, clock.date, true) : "")
            : whenField.text.trim()
              ? "→ " + TimeParser.describe(root.parsed, clock.date)
              : "30 · 1h30m · 14:30 · tomorrow 9:00 · fri 14:00 · every day 8:00"
          color: root.hasText && !root.valid ? Color.urgent : root.foreground
          opacity: root.hasText ? 1 : 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        TextField {
          id: whenField
          width: parent.width
          placeholderText: "When"
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          horizontalAlignment: root.floating ? TextInput.AlignHCenter : TextInput.AlignLeft
          background.visible: !root.floating
          KeyNavigation.tab: messageField
          KeyNavigation.backtab: messageField
          Keys.onPressed: function(event) { root.stepKey(event) }
          Keys.onEscapePressed: root.clearOrDismiss(whenField)
          onAccepted: if (root.valid) messageField.forceActiveFocus()

          Underline { field: whenField }
        }

        TextField {
          id: messageField
          width: parent.width
          placeholderText: "Message"
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          horizontalAlignment: root.floating ? TextInput.AlignHCenter : TextInput.AlignLeft
          background.visible: !root.floating
          KeyNavigation.tab: whenField
          KeyNavigation.backtab: whenField
          Keys.onPressed: function(event) { root.stepKey(event) }
          Keys.onEscapePressed: root.clearOrDismiss(messageField)
          onAccepted: root.submit()

          Underline { field: messageField }
        }
      }
    }
  }

  component Underline: Rectangle {
    property Item field
    visible: root.floating
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: Math.max(1, Style.space(field.activeFocus ? 2 : 1))
    color: field.activeFocus ? Color.accent : root.foreground
    opacity: field.activeFocus ? 1 : 0.35
  }
}
