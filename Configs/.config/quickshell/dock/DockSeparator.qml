import QtQuick
import qs.Commons as Commons

Item {
  id: separator
  required property var dock
  width: separator.dock.separatorWidth
  height: separator.dock.iconSlot
  Rectangle {
    anchors.centerIn: parent
    width: separator.dock.separatorWidth
    height: separator.dock.iconSize * 0.7
    color: Commons.Util.alpha(Commons.Color.bar.text, 0.25)
  }
}
