import QtQuick
import qs.Commons as Commons

Item {
  id: root

  property bool checked: false
  property bool busy: false

  property bool interactive: true

  property bool hasCursor: false

  property bool cursorRing: interactive
  property int cursorPad: Commons.Style.space(6)
  property bool rounded: Commons.Style.cornerRadius > 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  property int trackHeight: Math.max(22, Math.round(Commons.Style.spacing.controlHeight * 0.55))
  property int trackWidth: Math.round(trackHeight * 1.9)
  property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

  readonly property int cursorRingInset: cursorRing ? cursorPad : 0

  implicitWidth: trackWidth + cursorRingInset * 2
  implicitHeight: trackHeight + cursorRingInset * 2

  BorderSurface {
    anchors.fill: parent
    visible: root.cursorRing && root.hot
    color: "transparent"
    radius: Commons.Style.cornerRadius
    borderSpec: Commons.Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  BorderSurface {
    id: track
    width: root.trackWidth
    height: root.trackHeight
    anchors.centerIn: parent
    radius: root.rounded ? Math.min(Commons.Style.cornerRadius, height / 2) : 0
    color: root.checked
      ? Commons.Style.selectedFillFor(root.foreground, root.accent)
      : Commons.Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Commons.Border.controlSpec(root.checked ? "selected" : "normal", root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: root.rounded ? Math.min(track.radius, height / 2) : 0
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      color: root.checked ? Commons.Style.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)

      Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: 120 } }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: if (!root.busy) root.toggled()
  }
}
