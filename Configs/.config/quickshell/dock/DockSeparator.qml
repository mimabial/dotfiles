import QtQuick
import qs.Commons

Item {
  id: separator
  required property var dock
  width: separator.dock.vertical ? separator.dock.iconSlot : separator.dock.separatorWidth
  height: separator.dock.vertical ? separator.dock.separatorWidth : separator.dock.iconSlot
  Rectangle {
    anchors.centerIn: parent
    width: separator.dock.vertical ? separator.dock.iconSize * 0.7 : separator.dock.separatorWidth
    height: separator.dock.vertical ? separator.dock.separatorWidth : separator.dock.iconSize * 0.7
    color: Util.alpha(separator.dock.dockForeground, 0.25)
  }
}
