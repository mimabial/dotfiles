import QtQuick
import qs.Commons
import ".." as Shell
import "DockModel.js" as DockModel

Item {
  id: fitem
  required property var dock

  property string folderPath: ""
  property string name: ""
  property string icon: "folder"
  property string tooltip: fitem.name + " (Folder)"
  property string menuOwner: "__folder_context__"
  property real homeCenter: 0

  signal openStackRequested(string path, string name, real cx)
  signal menuRequested(string path, string name, real cx)

  function trigger(menu) {
    if (menu) fitem.menuRequested(fitem.folderPath, fitem.name, fitem.dock.slotCenterX(fitem))
    else fitem.openStackRequested(fitem.folderPath, fitem.name, fitem.dock.slotCenterX(fitem))
  }

  readonly property real slotMain: fitem.dock.iconSlot * (fitem.dock.waveHover ? fitem.magnifyScale : 1)
  width: fitem.slotMain
  height: fitem.dock.iconSlot

  readonly property bool isOpen: fitem.dock.activeStackFolder === fitem.folderPath

  property real magnifyScale: {
    if (fitem.dock.waveHover) return fitem.dock.magnifyScaleAt(fitem.homeCenter)
    if (fitem.dock.hoverEffect === "off") return 1
    return area.containsMouse ? fitem.dock.zoomPeak : 1
  }

  readonly property string placeIcon: DockModel.resolveThemedFolderIcon(fitem.icon)
  readonly property bool isSymbolic: fitem.dock.symbolicFolders && fitem.placeIcon.indexOf("/") < 0

  Behavior on magnifyScale {
    NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
  }

  Item {
    id: iconSlot
    width: fitem.dock.iconSlot
    height: fitem.dock.iconSlot
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter

    Item {
      id: iconContainer
      width: fitem.dock.iconSize
      height: fitem.dock.iconSize
      anchors.centerIn: parent
      transformOrigin: fitem.dock.floorTransformOrigin
      scale: fitem.magnifyScale

      Image {
        anchors.fill: parent
        source: {
          var _tv = fitem.dock.themeVersion
          return fitem.isSymbolic ? "" : fitem.dock.appLibrary.iconSource(fitem.placeIcon)
        }
        sourceSize: Qt.size(fitem.dock.iconSize * 4, fitem.dock.iconSize * 4)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: !fitem.isSymbolic
      }

      Shell.SymbolicIcon {
        anchors.fill: parent
        visible: fitem.isSymbolic
        name: fitem.isSymbolic ? fitem.placeIcon : ""
        context: "places"
        color: fitem.dock.symbolicFolderColor
        size: fitem.dock.iconSize
      }
    }
  }

  Rectangle {
    visible: fitem.dock.showIndicators && fitem.isOpen
    x: (fitem.width - width) / 2
    y: fitem.dock.indicatorY(fitem.height, height)
    width: Style.space(4)
    height: Style.space(4)
    radius: width / 2
    color: Color.bar.active
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onEntered: fitem.dock.slotEntered(fitem.menuOwner, fitem.folderPath)
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) { fitem.trigger(mouse.button === Qt.RightButton) }
  }

  // Hover tooltip — uses our own HoverTooltip so textFormat: Text.PlainText is enforced.
  // (PanelToolTip is an opaque shell component; folder names come from user config.)
  HoverTooltip {
    dock: fitem.dock
    text: fitem.tooltip
    hovered: area.containsMouse
    blocked: !fitem.dock.showTooltips || fitem.dock.activeStackFolder !== ""
    x: (fitem.width - width) / 2
    y: fitem.dock.tipY(fitem.height, height)
  }
}
