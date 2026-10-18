import QtQuick
import qs.Commons as Commons

BorderSurface {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false

  property bool hasCursor: false

  property bool rounded: Commons.Style.cornerRadius > 0

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family
  property real titleSize: Commons.Style.font.subtitle
  property real descriptionSize: Commons.Style.font.caption

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: true
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  implicitHeight: Math.max(54, content.implicitHeight + Commons.Style.spacing.huge)
  implicitWidth: Commons.Style.space(240)
  radius: Commons.Style.cornerRadius

  readonly property bool inputHighlighted: hasCursor || mouse.containsMouse
  readonly property var stateBorderSpec: Commons.Border.controlSpec(activeFocus ? "focus" : (inputHighlighted ? "hover-cursor" : "normal"), foreground, accent)

  color: Commons.Style.controlFill(activeFocus, inputHighlighted, foreground, accent)
  borderSpec: stateBorderSpec

  Behavior on color { ColorAnimation { duration: 100 } }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.borderLeft + Commons.Style.spacing.rowPaddingX
    anchors.rightMargin: root.borderRight + Commons.Style.spacing.rowPaddingX
    spacing: Commons.Style.spacing.rowPaddingX

    Column {
      width: parent.width - track.width - parent.spacing
      spacing: Commons.Style.spacing.xs
      anchors.verticalCenter: parent.verticalCenter

      Text {
        text: root.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.titleSize
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        visible: root.description !== ""
        text: root.description
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: root.descriptionSize
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }

    ToggleSwitch {
      id: track
      checked: root.checked
      rounded: root.rounded
      foreground: root.foreground
      accent: root.accent
      interactive: false
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
