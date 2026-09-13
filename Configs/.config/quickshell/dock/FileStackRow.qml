import QtQuick
import QtQuick.Effects
import qs.Commons
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

  readonly property string resolvedIconSource: {
    var _tv = frow.dock.themeVersion
    return frow.dock.appLibrary.iconSource(DockModel.resolveFileItemIcon(frow.icon, frow.dock.folderColor))
  }
  readonly property bool isIconSymbolic: resolvedIconSource.indexOf("-symbolic.svg") >= 0 || resolvedIconSource.indexOf("symbolic") >= 0
  readonly property color symbolicColor: {
    if (frow.dock.folderColor === "white") return "#ffffff"
    if (frow.dock.folderColor === "black") return "#111111"
    return (Color.bar.background.hslLightness < 0.5 || Color.background.hslLightness < 0.5) ? "#ffffff" : "#111111"
  }

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
        id: stackRowImg
        anchors.fill: parent
        source: frow.resolvedIconSource
        sourceSize: Qt.size(48, 48)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
        visible: !frow.isIconSymbolic
      }

      Item {
        anchors.fill: parent
        visible: frow.isIconSymbolic

        Image {
          id: symStackImg
          anchors.fill: parent
          source: frow.resolvedIconSource
          sourceSize: Qt.size(48, 48)
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          mipmap: true
          visible: false
        }

        MultiEffect {
          anchors.fill: symStackImg
          source: symStackImg
          colorization: 1.0
          colorizationColor: frow.symbolicColor
        }
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
