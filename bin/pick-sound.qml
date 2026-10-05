import QtQml
import QtQuick.Dialogs

// Sound file chooser, run as its own process so the dialog stays out of the shell:
//   qml6 bin/pick-sound.qml -- "<folder>"
// Prints the chosen path through the Qt message handler; prints nothing when cancelled.
QtObject {
  property FileDialog dialog: FileDialog {
    title: "Choose a reminder sound"
    nameFilters: ["Sounds (*.oga *.ogg *.wav *.flac *.mp3)", "All files (*)"]
    currentFolder: {
      var args = Qt.application.arguments
      return "file://" + String(args[args.length - 1]).split("/").map(encodeURIComponent).join("/")
    }
    onAccepted: {
      console.warn("PATH " + decodeURIComponent(selectedFile.toString().replace(/^file:\/\//, "")))
      Qt.quit()
    }
    onRejected: Qt.quit()
    Component.onCompleted: open()
  }
}
