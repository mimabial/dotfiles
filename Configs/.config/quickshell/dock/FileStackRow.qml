import QtQuick
import qs.Commons as Commons
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

  implicitWidth: Math.max(240, Commons.Style.space(8) + Commons.Style.space(16) + Commons.Style.space(8)
    + label.implicitWidth + (sublabel.text !== "" ? (sublabel.implicitWidth + Commons.Style.space(8)) : 0) + Commons.Style.space(8))
  width: frow.rowWidth
  height: Math.max(28, Commons.Style.space(28))

  readonly property string resolvedIcon: DockModel.resolveFileItemIcon(frow.icon)
  readonly property bool isIconSymbolic: frow.dock.symbolicFolders && DockModel.isPlaceIcon(frow.resolvedIcon)

  Rectangle {
    anchors.fill: parent
    radius: Commons.Style.cornerRadius
    color: area.containsMouse ? Commons.Color.menu.selectedBackground : "transparent"
  }

  Item {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: Commons.Style.space(8)
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(16, label.implicitHeight)

    Item {
      id: iconHolder
      width: Commons.Style.space(16)
      height: Commons.Style.space(16)
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
      color: Commons.Util.alpha(Commons.Color.menu.text, 0.45)
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
    }

    Text {
      id: label
      anchors.left: iconHolder.right
      anchors.leftMargin: Commons.Style.space(8)
      anchors.right: sublabel.visible ? sublabel.left : parent.right
      anchors.rightMargin: sublabel.visible ? Commons.Style.space(8) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: frow.name
      textFormat: Text.PlainText
      color: Commons.Color.menu.text
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.body
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
