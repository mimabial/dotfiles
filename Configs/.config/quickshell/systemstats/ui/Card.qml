pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Rectangle {
  id: root

  property color foreground: Commons.Color.popups.text
  property real padding: Commons.Style.space(12)
  property real spacing: Commons.Style.space(8)
  default property alias content: column.data

  width: parent ? parent.width : implicitWidth
  implicitHeight: column.implicitHeight + padding * 2
  radius: Commons.Style.cornerRadius
  color: Commons.Util.alpha(foreground, 0.035)
  border.width: 1
  border.color: Commons.Util.alpha(foreground, 0.09)

  Column {
    id: column
    anchors.fill: parent
    anchors.margins: root.padding
    spacing: root.spacing
  }
}
