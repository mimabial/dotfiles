pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Rectangle {
  id: row
  required property var controller
  property int number: 0
  property string thumb: ""
  property string glyph: "\uf001"
  property string title: ""
  property string subtitle: ""
  property string meta: ""
  property bool isCurrent: false
  readonly property bool navigable: true
  property bool cursored: false
  readonly property int thumbSize: Style.space(24)
  default property alias actions: tail.data
  signal activated()
  function activateKeyboard() { activated() }

  width: parent ? parent.width : 0
  implicitHeight: thumbSize + 2 * Style.spacing.sm
  radius: Style.cornerRadius
  color: mouse.containsMouse || cursored ? controller.shell.hoverFill() : isCurrent ? controller.shell.selectedFill() : "transparent"
  border.color: cursored ? controller.shell.hoverEdge(.85) : isCurrent ? controller.shell.selectedEdge() : "transparent"

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.activated()
  }

  Row {
    id: lead
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.md

    Text {
      visible: row.number > 0
      anchors.verticalCenter: parent.verticalCenter
      text: String(row.number).padStart(2, "0")
      color: row.isCurrent ? Color.accent : row.controller.dim
      font.family: row.controller.fontFamily
      font.pixelSize: Style.font.caption
    }

    Rectangle {
      width: row.thumbSize
      height: width
      radius: Style.spacing.xs
      color: row.controller.surface

      Image {
        visible: row.thumb !== ""
        anchors.fill: parent
        source: row.controller.artSource(row.thumb)
        sourceSize: Qt.size(width, height)
        fillMode: Image.PreserveAspectCrop
      }
      Text {
        visible: row.thumb === ""
        anchors.centerIn: parent
        text: row.glyph
        color: row.isCurrent ? Color.accent : row.controller.dim
        font.family: row.controller.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Column {
    anchors.left: lead.right
    anchors.right: tail.left
    anchors.leftMargin: Style.spacing.md
    anchors.rightMargin: Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.title
      elide: Text.ElideRight
      color: row.isCurrent ? Color.accent : row.controller.foreground
      font.family: row.controller.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      visible: text !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: row.subtitle
      elide: Text.ElideRight
      color: row.controller.dim
      font.family: row.controller.fontFamily
      font.pixelSize: Style.font.caption * 0.82
    }
  }

  Row {
    id: tail
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.md

    Text {
      visible: text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: row.meta
      color: row.controller.dim
      font.family: row.controller.fontFamily
      font.pixelSize: Style.font.caption
    }
  }
}
