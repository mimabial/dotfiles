pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons

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
  readonly property int thumbSize: Commons.Style.space(24)
  default property alias actions: tail.data
  signal activated()
  function activateKeyboard() { activated() }

  width: parent ? parent.width : 0
  implicitHeight: thumbSize + 2 * Commons.Style.spacing.sm
  radius: Commons.Style.cornerRadius
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
    anchors.leftMargin: Commons.Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Commons.Style.spacing.md

    Text {
      visible: row.number > 0
      anchors.verticalCenter: parent.verticalCenter
      text: String(row.number).padStart(2, "0")
      color: row.isCurrent ? Commons.Color.accent : row.controller.dim
      font.family: row.controller.fontFamily
      font.pixelSize: Commons.Style.font.caption
    }

    Rectangle {
      width: row.thumbSize
      height: width
      radius: Commons.Style.spacing.xs
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
        color: row.isCurrent ? Commons.Color.accent : row.controller.dim
        font.family: row.controller.fontFamily
        font.pixelSize: Commons.Style.font.caption
      }
    }
  }

  Column {
    anchors.left: lead.right
    anchors.right: tail.left
    anchors.leftMargin: Commons.Style.spacing.md
    anchors.rightMargin: Commons.Style.spacing.md
    anchors.verticalCenter: parent.verticalCenter

    Text {
      width: parent.width
      textFormat: Text.PlainText
      text: row.title
      elide: Text.ElideRight
      color: row.isCurrent ? Commons.Color.accent : row.controller.foreground
      font.family: row.controller.fontFamily
      font.pixelSize: Commons.Style.font.caption
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
      font.pixelSize: Commons.Style.font.caption * 0.82
    }
  }

  Row {
    id: tail
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.spacing.sm
    anchors.verticalCenter: parent.verticalCenter
    spacing: Commons.Style.spacing.md

    Text {
      visible: text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: row.meta
      color: row.controller.dim
      font.family: row.controller.fontFamily
      font.pixelSize: Commons.Style.font.caption
    }
  }
}
