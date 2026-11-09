import QtQuick
import qs.Commons as Commons

Item {
  id: crow

  property string text: ""
  property string glyph: ""
  property string shortcut: ""
  property bool checked: false
  property color textColor: Commons.Color.menu.text
  property bool danger: false
  property bool isHeader: false
  property bool disabled: false
  readonly property bool navigable: enabled && !isHeader && !disabled
  property bool cursored: false
  property bool highlighted: false
  readonly property bool hovered: area.containsMouse
  property bool isWindowRow: false
  property real menuWidth: 0
  property bool winFocused: false
  property bool winParked: false
  signal triggered()
  function activateKeyboard() { triggered() }

  readonly property bool isMenuContent: true
  readonly property real markWidth: Commons.Style.space(14)
  readonly property real chevronWidth: crow.isWindowRow ? Commons.Style.space(8) : 0

  implicitWidth: Commons.Style.space(8) + crow.markWidth + Commons.Style.space(6)
    + (crow.chevronWidth > 0 ? crow.chevronWidth + Commons.Style.space(6) : 0)
    + label.implicitWidth + Commons.Style.space(8)
  width: crow.menuWidth > 0 ? crow.menuWidth : crow.implicitWidth
  height: crow.isHeader ? Math.max(22, Commons.Style.space(22)) : Math.max(28, Commons.Style.space(28))

  Rectangle {
    anchors.fill: parent
    visible: !crow.isHeader && !crow.disabled
    radius: Commons.Style.cornerRadius
    color: (area.containsMouse || crow.cursored || crow.highlighted)
      ? (crow.danger ? Commons.Util.scaleAlpha(Commons.Color.urgent, 0.16) : Commons.Color.menu.selectedBackground)
      : (crow.checked ? Commons.Util.scaleAlpha(Commons.Color.bar.active, 0.12) : "transparent")
  }

  Row {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: Commons.Style.space(8)
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.space(8) + (shortcutLabel.visible ? shortcutLabel.implicitWidth + Commons.Style.space(12) : 0)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Commons.Style.space(6)

    Item {
      id: markContainer
      width: crow.markWidth
      height: crow.markWidth
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        visible: crow.isWindowRow
        width: Commons.Style.space(6)
        height: Commons.Style.space(6)
        radius: width / 2
        anchors.centerIn: parent
        color: crow.winFocused
          ? Commons.Color.bar.active
          : (crow.winParked ? "transparent" : (crow.checked ? Commons.Color.bar.active : Commons.Util.scaleAlpha(Commons.Color.menu.text, 0.45)))
        border.color: crow.winFocused
          ? Commons.Color.bar.active
          : (crow.winParked ? Commons.Util.scaleAlpha(Commons.Color.menu.text, 0.4) : (crow.checked ? Commons.Color.bar.active : "transparent"))
        border.width: 1
      }

      Text {
        visible: !crow.isWindowRow
        anchors.fill: parent
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        opacity: (crow.glyph !== "" || crow.checked) ? 1 : 0
        text: crow.glyph !== "" ? crow.glyph : "\uf00c"
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.caption
        color: crow.checked ? Commons.Color.bar.active : (crow.isHeader ? Commons.Util.scaleAlpha(Commons.Color.menu.text, 0.5) : crow.textColor)
      }
    }

    Item {
      id: chevronContainer
      visible: crow.isWindowRow
      width: crow.chevronWidth
      height: crow.markWidth
      anchors.verticalCenter: parent.verticalCenter

      Text {
        anchors.centerIn: parent
        text: "›"
        textFormat: Text.PlainText
        opacity: crow.checked ? 1 : 0
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
        color: Commons.Color.bar.active
      }
    }

    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      width: content.width - markContainer.width - content.spacing
        - (chevronContainer.visible ? chevronContainer.width + content.spacing : 0)
      text: crow.text
      textFormat: Text.PlainText
      color: (crow.isHeader || crow.disabled)
        ? Commons.Util.scaleAlpha(Commons.Color.menu.text, 0.5)
        : (crow.checked || crow.winFocused
            ? Commons.Color.bar.active
        : ((area.containsMouse || crow.cursored) && crow.danger ? Commons.Color.urgent : crow.textColor))
      font.family: Commons.Style.font.family
      font.pixelSize: crow.isHeader ? Commons.Style.font.caption : Commons.Style.font.body
      font.weight: (crow.isHeader || crow.winFocused || (crow.checked && !crow.isWindowRow))
        ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
  }

  Text {
    id: shortcutLabel
    visible: crow.shortcut !== ""
    anchors.right: parent.right
    anchors.rightMargin: Commons.Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: crow.shortcut
    textFormat: Text.PlainText
    color: Commons.Util.scaleAlpha(Commons.Color.menu.text, 0.5)
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.body
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: !crow.isHeader && !crow.disabled
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: crow.triggered()
  }
}
