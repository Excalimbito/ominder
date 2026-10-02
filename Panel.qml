import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "TimeParser.js" as TimeParser

// Management panel: upcoming reminders with edit / delete, Clear and Reset,
// and the plugin settings. Keys: j/k move, Enter edits, x deletes, n creates.
Panel {
  id: root
  moduleName: "io.github.excalimbito.ominder"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var reminders: []
  property date now: new Date()
  property int cursor: -1
  property bool confirmReset: false

  readonly property string ominder: Qt.resolvedUrl("bin/ominder").toString().replace(/^file:\/\//, "")
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.confirmReset = false
    root.cursor = root.reminders.length > 0 ? 0 : -1
    root.run(["sweep"])
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function run(args) {
    Quickshell.execDetached([root.ominder].concat(args))
  }

  function summonOverlay(payload) {
    root.close()
    if (root.bar && root.bar.shell) root.bar.shell.summon(root.moduleName, JSON.stringify(payload))
  }

  function edit(index) {
    var entry = root.reminders[index]
    if (entry) root.summonOverlay({ id: entry.id, when: entry.when, message: entry.message })
  }

  function remove(index) {
    var entry = root.reminders[index]
    if (entry) root.run(["rm", entry.id])
  }

  function saveSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  onRemindersChanged: if (root.cursor >= root.reminders.length) root.cursor = root.reminders.length - 1

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: soundFileField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dy !== 0 && root.reminders.length > 0)
          root.cursor = Math.max(0, Math.min(root.reminders.length - 1, root.cursor + dy))
      }
      onActivateRequested: root.edit(root.cursor)
      onDeleteRequested: root.remove(root.cursor)
      onTextKey: function(text) { if (text === "n") root.summonOverlay({}) }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.md

        Item {
          width: parent.width
          implicitHeight: newButton.implicitHeight

          PanelSectionHeader {
            anchors.verticalCenter: parent.verticalCenter
            text: "Reminders"
            foreground: root.barForeground
            fontFamily: root.fontFamily
          }

          PanelActionButton {
            id: newButton
            anchors.right: parent.right
            iconText: "󰐕"
            tooltipText: "New reminder (n)"
            foreground: root.barForeground
            onClicked: root.summonOverlay({})
          }
        }

        Text {
          visible: root.reminders.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No upcoming reminders"
          color: root.barForeground
          opacity: 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Repeater {
          model: root.reminders

          CursorSurface {
            id: row
            required property var modelData
            required property int index
            width: content.width
            implicitHeight: rowContent.implicitHeight + Style.spacing.md * 2
            hasCursor: root.cursor === index
            foreground: root.barForeground

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onContainsMouseChanged: if (containsMouse) root.cursor = row.index
              onClicked: root.edit(row.index)
            }

            Row {
              id: rowContent
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              anchors.leftMargin: Style.spacing.rowPaddingX
              spacing: Style.spacing.sm

              Column {
                width: parent.width - editButton.width - deleteButton.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xs

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: (row.modelData.repeat ? "󰑖 " : "") + row.modelData.message
                  color: root.barForeground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: TimeParser.describe(row.modelData, root.now)
                  color: root.barForeground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              PanelActionButton {
                id: editButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰏫"
                tooltipText: "Edit"
                foreground: root.barForeground
                onClicked: root.edit(row.index)
              }

              PanelActionButton {
                id: deleteButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰆴"
                tooltipText: "Delete (x)"
                foreground: root.barForeground
                hoverColor: Color.urgent
                onClicked: root.remove(row.index)
              }
            }
          }
        }

        Row {
          spacing: Style.spacing.md

          Button {
            visible: !root.confirmReset
            text: "Clear"
            tooltipText: "Delete one-time reminders"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.run(["clear"])
          }

          Button {
            visible: !root.confirmReset
            text: "Reset"
            tooltipText: "Delete every reminder, including repeating ones"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.confirmReset = true
          }

          Button {
            visible: root.confirmReset
            text: "Delete all reminders"
            bordered: true
            foreground: Color.urgent
            fontFamily: root.fontFamily
            onClicked: {
              root.confirmReset = false
              root.run(["reset", "--yes"])
            }
          }

          Button {
            visible: root.confirmReset
            text: "Cancel"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.confirmReset = false
          }
        }

        PanelSeparator { foreground: root.barForeground }

        PanelSectionHeader {
          text: "Settings"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        Toggle {
          width: parent.width
          label: "Sound"
          description: "Play a sound when a reminder fires"
          checked: root.setting("sound", true)
          foreground: root.barForeground
          fontFamily: root.fontFamily
          onClicked: root.saveSetting("sound", !checked)
        }

        TextField {
          id: soundFileField
          width: parent.width
          visible: root.setting("sound", true)
          text: root.setting("soundFile", "/usr/share/sounds/freedesktop/stereo/complete.oga")
          placeholderText: "Sound file"
          foreground: root.barForeground
          font.family: root.fontFamily
          Keys.onEscapePressed: keyCatcher.forceActiveFocus()
          onEditingFinished: if (text !== root.setting("soundFile", "")) root.saveSetting("soundFile", text)
        }

        Row {
          spacing: Style.spacing.md

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Snooze"
            color: root.barForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ButtonGroup {
            options: [
              { value: "5", label: "5m" },
              { value: "10", label: "10m" },
              { value: "15", label: "15m" },
              { value: "30", label: "30m" }
            ]
            value: String(root.setting("snoozeMinutes", 5))
            foreground: root.barForeground
            fontFamily: root.fontFamily
            focusable: false
            onChanged: function(value) { root.saveSetting("snoozeMinutes", Number(value)) }
          }
        }
      }
    }
  }
}
