import QtQuick
import qs.Commons

// The caller owns `checked`; `busy` only blocks input. A separate cursor ring
// avoids weakening the track's normal border under hover/focus.
Item {
  id: root

  property bool checked: false
  property bool busy: false

  property bool interactive: true

  property bool hasCursor: false

  property bool cursorRing: interactive
  property int cursorPad: Style.space(6)
  property bool rounded: Style.cornerRadius > 0
  property color foreground: Color.foreground
  property color accent: Color.accent

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  // `trackHeight` is settable so a compact placement — a switch riding a panel
  // section header, say — can ask for a genuinely smaller control instead of
  // scaling a big one down, which lands the track and knob on fractional pixels
  // and blurs their edges. The derived sizes only carry floors low enough to
  // stay out of an override's way; at the default track height each one is
  // already above its floor, so nothing about the normal switch changes.
  property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
  property int trackWidth: Math.round(trackHeight * 1.9)
  property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

  readonly property int _pad: cursorRing ? cursorPad : 0

  implicitWidth: trackWidth + _pad * 2
  implicitHeight: trackHeight + _pad * 2

  BorderSurface {
    anchors.fill: parent
    visible: root.cursorRing && root.hot
    color: "transparent"
    radius: Style.cornerRadius
    borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  BorderSurface {
    id: track
    width: root.trackWidth
    height: root.trackHeight
    anchors.centerIn: parent
    radius: root.rounded ? Math.min(Style.cornerRadius, height / 2) : 0
    color: root.checked
      ? Style.selectedFillFor(root.foreground, root.accent)
      : Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec(root.checked ? "selected" : "normal", root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      width: root.knobSize
      height: root.knobSize
      radius: root.rounded ? Math.min(track.radius, height / 2) : 0
      x: root.checked ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      color: root.checked ? Style.selectedStateColor(root.foreground, root.accent) : Qt.darker(root.foreground, 1.25)

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
