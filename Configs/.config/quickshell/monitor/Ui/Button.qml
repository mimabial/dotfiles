import QtQuick
import QtQuick.Controls
import qs.Commons as Commons

BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""

  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false

  property color foreground: Commons.Color.foreground
  property color background: "transparent"
  property color accent: Commons.Color.accent

  property string fontFamily: Commons.Style.font.family
  property real fontSize: Commons.Style.font.body
  property real iconSize: Commons.Style.font.icon
  property real iconRotation: 0
  property bool iconSpinning: false
  property real horizontalPadding: Commons.Style.spacing.controlPaddingX
  property real verticalPadding: Commons.Style.spacing.controlPaddingY
  property bool leftAlign: false

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  property color tooltipBackground: Commons.Color.tooltip.background
  property color tooltipForeground: Commons.Color.tooltip.text
  property color tooltipBorder: Commons.Color.tooltip.border

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable
  Keys.onReturnPressed: if (focusable) root.clicked()
  Keys.onEnterPressed: if (focusable) root.clicked()
  Keys.onSpacePressed: if (focusable) root.clicked()

  implicitWidth: row.implicitWidth + horizontalPadding * 2 + Commons.Border.left(_borderSpec) + Commons.Border.right(_borderSpec)
  implicitHeight: row.implicitHeight + verticalPadding * 2 + Commons.Border.top(_borderSpec) + Commons.Border.bottom(_borderSpec)
  radius: Commons.Style.cornerRadius

  readonly property bool hot: mouseArea.containsMouse || hasCursor
  readonly property bool _keyboardFocused: focusable && activeFocus
  readonly property color _selectedColor: Commons.Style.selectedStateColor(root.foreground, root.accent)
  readonly property var _tooltipBorderSpec: Commons.Border.localOrSurfaceSpec("tooltip", "border", Commons.Style.popupBorder(root.tooltipBorder), Commons.Color.tooltip.border, Math.max(1, Commons.Style.normalBorderWidth))
  readonly property var _borderSpec: bordered ? Commons.Border.controlSpec("normal", root.foreground, root.accent) : Commons.Border.none()
  readonly property real _contentLeftInset: Commons.Border.left(_borderSpec) + leftPadding

  color: mouseArea.pressed ? Commons.Style.pressedFillFor(root.foreground, root.accent)
    : _keyboardFocused       ? Commons.Style.focusFillFor(root.foreground, root.accent)
    : hot                  ? Commons.Style.hoverFillFor(root.foreground, root.accent)
    : selected             ? Commons.Style.selectedFillFor(root.foreground, root.accent)
    : active               ? Commons.Style.selectedFillFor(root.foreground, root.accent)
    : background

  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: 120 } }

  ToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    delay: 400
    padding: 0
    background: BorderSurface {
      color: Commons.Style.popupTinted(root.tooltipBackground)
      borderSpec: root._tooltipBorderSpec
      radius: 0
    }
    contentItem: Text {
      text: root.tooltipText
      color: root.tooltipForeground
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.bodySmall
      leftPadding: Commons.Border.left(root._tooltipBorderSpec) + Commons.Style.spacing.controlPaddingX
      rightPadding: Commons.Border.right(root._tooltipBorderSpec) + Commons.Style.spacing.controlPaddingX
      topPadding: Commons.Border.top(root._tooltipBorderSpec) + Commons.Style.spacing.controlPaddingY
      bottomPadding: Commons.Border.bottom(root._tooltipBorderSpec) + Commons.Style.spacing.controlPaddingY
    }
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? root._contentLeftInset : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: Commons.Style.spacing.controlGap

    Text {
      visible: root.iconText !== ""
      text: root.iconText
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      rotation: root.iconSpinning ? 0 : root.iconRotation
      transformOrigin: Item.Center
      anchors.verticalCenter: parent.verticalCenter

      RotationAnimation on rotation {
        from: 0
        to: 360
        duration: 900
        loops: Animation.Infinite
        running: root.iconSpinning
      }
    }

    Text {
      visible: root.text !== ""
      text: root.text
      color: root.selected ? root._selectedColor : root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (root.focusable) root.forceActiveFocus()
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
