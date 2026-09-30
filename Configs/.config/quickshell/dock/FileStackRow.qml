import QtQuick
import qs.Commons
import ".." as Shell
import "DockModel.js" as DockModel

Item {
  id: frow
  required property var dock

  property string name: ""
  property string path: ""
  property string icon: "folder"
  property string subtext: ""
  property real menuWidth: 0
  signal triggered()

  readonly property bool isMenuContent: true
  readonly property real rowWidth: frow.menuWidth > 0 ? frow.menuWidth : frow.implicitWidth

  implicitWidth: Math.max(240, Style.space(8) + Style.space(16) + Style.space(8)
    + label.implicitWidth + (sublabel.text !== "" ? (sublabel.implicitWidth + Style.space(8)) : 0) + Style.space(8))
  width: frow.rowWidth
  height: Math.max(28, Style.space(28))

  readonly property string resolvedIcon: DockModel.resolveFileItemIcon(frow.icon)
  readonly property bool isIconSymbolic: frow.dock.symbolicFolders && DockModel.isPlaceIcon(frow.resolvedIcon)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: area.containsMouse ? Color.menu.selectedBackground : "transparent"
  }

  Item {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(16, label.implicitHeight)

    Item {
      id: iconHolder
      width: Style.space(16)
      height: Style.space(16)
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter

      Image {
        anchors.fill: parent
        source: {
          var _tv = frow.dock.themeVersion
          return frow.isIconSymbolic ? "" : frow.dock.appLibrary.iconSource(frow.resolvedIcon)
        }
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: !frow.isIconSymbolic
      }

      Shell.SymbolicIcon {
        anchors.fill: parent
        visible: frow.isIconSymbolic
        name: frow.isIconSymbolic ? frow.resolvedIcon : ""
        context: "places"
        color: frow.dock.symbolicFolderColor
        size: iconHolder.width
      }
    }

    Text {
      id: sublabel
      visible: frow.subtext !== ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: frow.subtext
      textFormat: Text.PlainText
      color: Util.alpha(Color.menu.text, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Text {
      id: label
      anchors.left: iconHolder.right
      anchors.leftMargin: Style.space(8)
      anchors.right: sublabel.visible ? sublabel.left : parent.right
      anchors.rightMargin: sublabel.visible ? Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: frow.name
      textFormat: Text.PlainText
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideMiddle
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: frow.triggered()
  }
}
