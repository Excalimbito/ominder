import Quickshell
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
  property int cardWidth: Math.min(Style.space(380), panel.width - Style.gapsOut * 2)
  property int cardHeight: contentMargin * 2 + form.implicitHeight

  readonly property var parsed: TimeParser.parse(whenField.text, clock.date)
  readonly property bool valid: !parsed.error

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

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
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

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: whenField.text.trim()
            ? "→ " + TimeParser.describe(root.parsed, clock.date)
            : "30 · 1h30m · 14:30 · tomorrow 9:00 · fri 14:00 · every day 8:00"
          color: whenField.text.trim() && !root.valid ? Color.urgent : root.foreground
          opacity: whenField.text.trim() ? 1 : 0.58
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
          KeyNavigation.tab: messageField
          KeyNavigation.backtab: messageField
          Keys.onEscapePressed: root.clearOrDismiss(whenField)
          onAccepted: if (root.valid) messageField.forceActiveFocus()
        }

        TextField {
          id: messageField
          width: parent.width
          placeholderText: "Message"
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          KeyNavigation.tab: whenField
          KeyNavigation.backtab: whenField
          Keys.onEscapePressed: root.clearOrDismiss(messageField)
          onAccepted: root.submit()
        }
      }
    }
  }
}
