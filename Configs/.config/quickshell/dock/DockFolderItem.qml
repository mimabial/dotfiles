import QtQuick
import QtQuick.Effects
import qs.Commons
import "DockModel.js" as DockModel

Item {
  id: fitem
  required property var dock
  required property Item dockContent

  property string folderPath: ""
  property string name: ""
  property string icon: "folder"
  property real homeCenter: 0

  signal openStackRequested(string path, string name, real cx, real cy)
  signal menuRequested(string path, string name, real cx, real cy)

  readonly property real slotMain: fitem.dock.iconSlot * (fitem.dock.waveHover ? fitem.magnifyScale : 1)
  width: fitem.dock.vertical ? fitem.dock.iconSlot : fitem.slotMain
  height: fitem.dock.vertical ? fitem.slotMain : fitem.dock.iconSlot

  readonly property bool isOpen: fitem.dock.activeStackFolder === fitem.folderPath

  property real magnifyScale: {
    if (fitem.dock.waveHover) return fitem.dock.magnifyScaleAt(fitem.homeCenter)
    if (fitem.dock.hoverEffect === "off") return 1
    return area.containsMouse ? fitem.dock.zoomPeak : 1
  }

  readonly property string resolvedSource: {
    var _tv = fitem.dock.themeVersion
    return fitem.dock.appLibrary.iconSource(DockModel.resolveThemedFolderIcon(fitem.icon, fitem.dock.folderColor))
  }
  readonly property bool isSymbolic: resolvedSource.indexOf("-symbolic.svg") >= 0 || resolvedSource.indexOf("symbolic") >= 0
  readonly property color symbolicColor: {
    if (fitem.dock.folderColor === "white") return "#ffffff"
    if (fitem.dock.folderColor === "black") return "#111111"
    return (Color.bar.background.hslLightness < 0.5 || Color.background.hslLightness < 0.5) ? "#ffffff" : "#111111"
  }

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
        id: folderIconImg
        anchors.fill: parent
        source: fitem.resolvedSource
        sourceSize: Qt.size(fitem.dock.iconSize * 4, fitem.dock.iconSize * 4)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: !fitem.isSymbolic
      }

      Item {
        anchors.fill: parent
        visible: fitem.isSymbolic

        Image {
          id: symbolicImg
          anchors.fill: parent
          source: fitem.resolvedSource
          sourceSize: Qt.size(fitem.dock.iconSize * 4, fitem.dock.iconSize * 4)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
          visible: false
        }

        MultiEffect {
          anchors.fill: symbolicImg
          source: symbolicImg
          colorization: 1.0
          colorizationColor: fitem.symbolicColor
        }
      }
    }
  }

  Rectangle {
    visible: fitem.isOpen
    readonly property real floorGap: Style.space(1)
    x: fitem.dock.vertical
      ? (fitem.dock.edge === "left" ? floorGap : fitem.width - width - floorGap)
      : (fitem.width - width) / 2
    y: fitem.dock.vertical
      ? (fitem.height - height) / 2
      : (fitem.dock.edge === "top" ? floorGap : fitem.height - height - floorGap)
    width: Style.space(4)
    height: Style.space(4)
    radius: width / 2
    color: Color.bar.active
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    onEntered: fitem.dock.slotEntered("__folder_context__", fitem.folderPath)
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        var mappedPos = fitem.mapToItem(fitem.dockContent, mouse.x, mouse.y)
        if (!mappedPos) return
        fitem.menuRequested(fitem.folderPath, fitem.name, mappedPos.x, mappedPos.y)
      } else {
        var centerPos = fitem.mapToItem(fitem.dockContent, fitem.width / 2, 0)
        if (!centerPos) return
        fitem.openStackRequested(fitem.folderPath, fitem.name, centerPos.x, centerPos.y)
      }
    }
  }

  // Hover tooltip — uses our own HoverTooltip so textFormat: Text.PlainText is enforced.
  // (PanelToolTip is an opaque shell component; folder names come from user config.)
  HoverTooltip {
    dock: fitem.dock
    text: fitem.name + " (Folder)"
    hovered: area.containsMouse
    blocked: !fitem.dock.showTooltips || fitem.dock.activeStackFolder !== ""
    x: (fitem.width - width) / 2
    y: -height - Style.space(8)
  }
}
