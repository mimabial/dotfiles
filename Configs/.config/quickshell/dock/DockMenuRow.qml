import QtQuick
import qs.Commons

Item {
  id: crow

  property string text: ""
  property string glyph: ""
  property bool checked: false
  property color textColor: Color.menu.text
  property bool danger: false
  property bool isHeader: false
  // Shown but not actionable: the row still says what it would do, instead of
  // vanishing and shifting every row below it.
  property bool disabled: false
  property bool isWindowRow: false
  property real menuWidth: 0
  property bool winFocused: false
  property bool winParked: false
  signal triggered()

  // Rows ask for what they need, then all get drawn at the menu's width, so
  // hover and checked fills line up down the menu instead of stepping in and
  // out with the length of each label.
  readonly property bool isMenuContent: true
  readonly property real markWidth: Style.space(14)
  // Reserved on every window row, selected or not, for the same reason the
  // mark column is: the selection chevron used to be prepended to the label
  // text, so cycling the window list under the scroll wheel re-measured each
  // row and the whole menu visibly changed width as the selection moved.
  readonly property real chevronWidth: crow.isWindowRow ? Style.space(8) : 0

  implicitWidth: Math.min(Style.space(260), Math.max(220, Style.space(8) + crow.markWidth + Style.space(6)
    + (crow.chevronWidth > 0 ? crow.chevronWidth + Style.space(6) : 0)
    + label.implicitWidth + Style.space(8)))
  width: crow.menuWidth > 0 ? crow.menuWidth : crow.implicitWidth
  height: crow.isHeader ? Math.max(22, Style.space(22)) : Math.max(28, Style.space(28))

  Rectangle {
    anchors.fill: parent
    visible: !crow.isHeader && !crow.disabled
    radius: Style.cornerRadius
    color: area.containsMouse
      ? (crow.danger ? Util.alpha(Color.urgent, 0.16) : Color.menu.selectedBackground)
      : (crow.checked ? Util.alpha(Color.bar.active, 0.12) : "transparent")
  }

  Row {
    id: content
    anchors.left: parent.left
    anchors.leftMargin: Style.space(8)
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(6)

    // The mark column is always reserved, so labels stay on one left edge and
    // a row keeps its width when it gets checked.
    Item {
      id: markContainer
      width: crow.markWidth
      height: crow.markWidth
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        visible: crow.isWindowRow
        width: Style.space(6)
        height: Style.space(6)
        radius: width / 2
        anchors.centerIn: parent
        color: crow.winFocused
          ? Color.bar.active
          : (crow.winParked ? "transparent" : (crow.checked ? Color.bar.active : Util.alpha(Color.menu.text, 0.45)))
        border.color: crow.winFocused
          ? Color.bar.active
          : (crow.winParked ? Util.alpha(Color.menu.text, 0.4) : (crow.checked ? Color.bar.active : "transparent"))
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
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: crow.checked ? Color.bar.active : (crow.isHeader ? Util.alpha(Color.menu.text, 0.5) : crow.textColor)
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
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: Color.bar.active
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
        ? Util.alpha(Color.menu.text, 0.5)
        : (crow.checked || crow.winFocused
            ? Color.bar.active
            : (area.containsMouse && crow.danger ? Color.urgent : crow.textColor))
      font.family: Style.font.family
      font.pixelSize: crow.isHeader ? Style.font.caption : Style.font.body
      // `checked` boldens an option row to mark the current value, which is
      // static. On a window row it tracks the wheel, so it would resize the
      // row mid-scroll the way the chevron used to.
      font.weight: (crow.isHeader || crow.winFocused || (crow.checked && !crow.isWindowRow))
        ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
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
