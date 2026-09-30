import QtQuick
import qs.Commons

Item {
  id: separator
  required property var dock
  width: separator.dock.separatorWidth
  height: separator.dock.iconSlot
  Rectangle {
    anchors.centerIn: parent
    width: separator.dock.separatorWidth
    height: separator.dock.iconSize * 0.7
    color: Util.alpha(Color.bar.text, 0.25)
  }
}
