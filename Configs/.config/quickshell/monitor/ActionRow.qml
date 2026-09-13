pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "Ui"

CursorSurface {
  id: actionRow
  required property var controller
  property int rowIndex: 0
  property string icon: ""
  property string title: ""
  property string subtitle: ""
  signal activated()

  hasCursor: actionRow.controller.cursorActive && actionRow.controller.cursorIndex === rowIndex
  foreground: actionRow.controller.foreground
  implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: actionRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: actionRow.enabled
    onEntered: {
      actionRow.controller.cursorActive = true
      actionRow.controller.cursorIndex = actionRow.rowIndex
    }
    onClicked: actionRow.activated()
  }

  Row {
    id: actionContent
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    spacing: Style.space(12)

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: actionRow.icon
      color: actionRow.enabled ? actionRow.controller.foreground : actionRow.controller.dim
      font.family: actionRow.controller.fontFamily
      font.pixelSize: Style.font.icon
    }

    Column {
      width: parent.width - parent.children[0].width - parent.spacing
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: actionRow.title
        color: actionRow.enabled ? actionRow.controller.foreground : actionRow.controller.dim
        font.family: actionRow.controller.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: actionRow.subtitle
        color: actionRow.controller.dim
        font.family: actionRow.controller.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }
}
