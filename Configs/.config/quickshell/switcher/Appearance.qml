import QtQuick
import qs.Commons as Commons

QtObject {
  readonly property real cornerRadius: Commons.Style.cornerRadius
  readonly property real borderWidth: Commons.Style.normalBorderWidth
  readonly property int fadeDuration: 160
  readonly property bool showScratchpads: true
}
