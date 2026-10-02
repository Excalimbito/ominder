import QtQml
import "../TimeParser.js" as TimeParser

// Fallback for `ominder parse` when the shell is not running:
//   qml6 bin/parse.qml -- "<when>"
// Prints the parse result as JSON through the Qt message handler.
QtObject {
  Component.onCompleted: {
    var args = Qt.application.arguments
    var result = TimeParser.parse(args[args.length - 1])
    result.preview = TimeParser.describe(result)
    console.warn(JSON.stringify(result))
    Qt.quit()
  }
}
