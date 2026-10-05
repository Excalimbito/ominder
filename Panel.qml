import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "TimeParser.js" as TimeParser

// Management panel with two views. The list: upcoming reminders with edit /
// delete, Clear and Reset. Settings: the plugin settings.
// Keys: j/k move, Enter edits, x deletes, n creates, s / l open settings,
// h / Esc return to the list.
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
  property bool showSettings: false

  readonly property string ominder: Qt.resolvedUrl("bin/ominder").toString().replace(/^file:\/\//, "")
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() {
    root.confirmReset = false
    root.showSettings = false
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

  // Scrolls the list just enough to show the cursor row.
  function revealCursor() {
    var row = rows.itemAt(root.cursor)
    if (!row) return
    if (row.y < listFlick.contentY) listFlick.contentY = row.y
    else if (row.y + row.height > listFlick.contentY + listFlick.height)
      listFlick.contentY = row.y + row.height - listFlick.height
  }

  onRemindersChanged: if (root.cursor >= root.reminders.length) root.cursor = root.reminders.length - 1
  onCursorChanged: root.revealCursor()
  onShowSettingsChanged: root.confirmReset = false

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
      onCloseRequested: {
        if (root.showSettings) root.showSettings = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.showSettings = dx > 0
        else if (!root.showSettings && root.reminders.length > 0)
          root.cursor = Math.max(0, Math.min(root.reminders.length - 1, root.cursor + dy))
      }
      onActivateRequested: if (!root.showSettings) root.edit(root.cursor)
      onDeleteRequested: if (!root.showSettings) root.remove(root.cursor)
      onTextKey: function(text) {
        if (text === "n") root.summonOverlay({})
        else if (text === "s") root.showSettings = true
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.spacing.md

        Item {
          width: parent.width
          implicitHeight: newButton.implicitHeight

          PanelSectionHeader {
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.confirmReset
            text: root.showSettings ? "Settings" : "Reminders"
            foreground: root.barForeground
            fontFamily: root.fontFamily
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.showSettings && !root.confirmReset
            spacing: Style.spacing.xs

            PanelActionButton {
              visible: root.reminders.length > 0
              iconText: "󰃢"
              tooltipText: "Clear: delete one-time reminders"
              foreground: root.barForeground
              onClicked: root.run(["clear"])
            }

            PanelActionButton {
              visible: root.reminders.length > 0
              iconText: "󰗩"
              tooltipText: "Reset: delete every reminder, including repeating ones"
              foreground: root.barForeground
              hoverColor: Color.urgent
              onClicked: root.confirmReset = true
            }

            PanelActionButton {
              id: newButton
              iconText: "󰐕"
              tooltipText: "New reminder (n)"
              foreground: root.barForeground
              onClicked: root.summonOverlay({})
            }

            PanelActionButton {
              iconText: "󰒓"
              tooltipText: "Settings (s)"
              foreground: root.barForeground
              onClicked: root.showSettings = true
            }
          }

          PanelActionButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showSettings
            iconText: "󰅖"
            tooltipText: "Back to reminders (Esc)"
            foreground: root.barForeground
            onClicked: root.showSettings = false
          }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.confirmReset
            spacing: Style.spacing.md

            Button {
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
              text: "Cancel"
              bordered: true
              foreground: root.barForeground
              fontFamily: root.fontFamily
              onClicked: root.confirmReset = false
            }
          }
        }

        Text {
          visible: !root.showSettings && root.reminders.length === 0
          width: parent.width
          textFormat: Text.PlainText
          text: "No upcoming reminders"
          color: root.barForeground
          opacity: 0.58
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        // ponytail: fixed cap of about six rows; derive it from the screen if panels get tall
        Flickable {
          id: listFlick
          visible: !root.showSettings && root.reminders.length > 0
          width: parent.width
          height: Math.min(contentHeight, Style.space(330))
          contentWidth: width
          contentHeight: rowColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: rowColumn
            width: listFlick.width

            Repeater {
              id: rows
              model: root.reminders
              CursorSurface {
                id: row
                required property var modelData
                required property int index
                width: rowColumn.width
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
          }
        }

        Column {
          id: settingsColumn
          visible: root.showSettings
          width: parent.width
          spacing: Style.spacing.md

          Toggle {
            width: settingsColumn.width
            label: "Sound"
            description: "Play a sound when a reminder fires"
            checked: root.setting("sound", true)
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.saveSetting("sound", !checked)
          }

          TextField {
            id: soundFileField
            width: settingsColumn.width
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

          Row {
            spacing: Style.spacing.md

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Style"
              color: root.barForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ButtonGroup {
              options: [
                { value: "floating", label: "Floating" },
                { value: "classic", label: "Classic" }
              ]
              value: root.setting("style", "floating")
              foreground: root.barForeground
              fontFamily: root.fontFamily
              focusable: false
              onChanged: function(value) { root.saveSetting("style", value) }
            }
          }

          SettingSlider {
            label: "Blur"
            key: "blur"
            fallback: 0.67
          }

          SettingSlider {
            label: "Dim"
            key: "dim"
            fallback: 0
          }

          Toggle {
            width: settingsColumn.width
            visible: root.setting("style", "floating") !== "classic"
            label: "Performance mode"
            description: "Disable animations"
            checked: root.setting("performanceMode", false)
            foreground: root.barForeground
            fontFamily: root.fontFamily
            onClicked: root.saveSetting("performanceMode", !checked)
          }
        }
      }
    }
  }

  // A 0 to 1 floating-style setting, shown as a percentage and saved when the slider is released.
  component SettingSlider: Row {
    property string label
    property string key
    property real fallback

    visible: root.setting("style", "floating") !== "classic"
    width: settingsColumn.width
    spacing: Style.spacing.md

    Text {
      id: sliderLabel
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(48)
      textFormat: Text.PlainText
      text: parent.label
      color: root.barForeground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    PanelSlider {
      id: slider
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - sliderLabel.width - sliderValue.width - parent.spacing * 2
      bar: root.bar
      value: root.setting(parent.key, parent.fallback)
      onReleased: function(value) { root.saveSetting(parent.key, Math.round(value * 100) / 100) }
    }

    Text {
      id: sliderValue
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(40)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: Math.round(slider.liveValue * 100) + "%"
      color: root.barForeground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }
}
