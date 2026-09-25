pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: root
  required property var controller

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  PanelActionButton {
    iconText: "\uf074"; tooltipText: "Shuffle: " + (root.controller.shuffleMode ? "ON" : "OFF")
    foreground: root.controller.shuffleMode ? Color.accent : root.controller.dim
    hoverColor: Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.toggleShuffle()
  }

  PanelActionButton {
    iconText: "\uf048"; tooltipText: "Previous Track"
    foreground: root.controller.foreground; hoverColor: Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.prevTrack()
  }

  PanelActionButton {
    iconText: root.controller.isPlaying ? "\uf04c" : "\uf04b"
    tooltipText: root.controller.isPlaying ? "Pause" : "Play"
    foreground: root.controller.isPlaying ? Color.accent : root.controller.foreground
    hoverColor: Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.togglePlayback()
  }

  PanelActionButton {
    iconText: "\uf051"; tooltipText: "Next Track"
    foreground: root.controller.foreground; hoverColor: Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.nextTrack()
  }

  PanelActionButton {
    iconText: "\uf01e"; tooltipText: "Repeat: " + root.controller.repeatMode.toUpperCase()
    foreground: root.controller.repeatMode !== "off" ? Color.accent : root.controller.dim
    hoverColor: Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.cycleRepeat()
  }

  PanelActionButton {
    iconText: "\uf04d"; tooltipText: "Stop Playback"
    foreground: root.controller.foreground; hoverColor: root.controller.urgent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.stop()
  }

  PanelActionButton {
    iconText: root.controller.currentLiked ? "\uf004" : "\uf08a"
    tooltipText: root.controller.currentLiked ? "Remove from Liked" : "Add to Liked"
    foreground: root.controller.currentLiked ? root.controller.urgent : root.controller.dim
    hoverColor: root.controller.urgent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.toggleLiked()
  }

  Item { width: Style.space(4) }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(5)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(22); horizontalAlignment: Text.AlignHCenter
      text: root.controller.volumePct === 0 ? "\uf026" : (root.controller.volumePct < 50 ? "\uf027" : "\uf028")
      color: root.controller.volumePct === 0 ? root.controller.urgent : (volIconMouse.containsMouse ? Color.accent : root.controller.dim)
      font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
      MouseArea {
        id: volIconMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.controller.toggleMute()
      }
    }

    Item {
      width: Style.space(64); height: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Style.space(4); radius: Style.space(2)
        color: root.controller.shell.alpha(root.controller.shell.role("br", root.controller.foreground), 0.25)

        Rectangle {
          width: Math.max(Style.space(2), parent.width * (root.controller.volumePct / 100.0))
          height: parent.height; radius: Style.space(2); color: Color.accent
        }
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
          if (pressed) root.controller.setVolume(Math.max(0, Math.min(100, Math.round((mouse.x / width) * 100))))
        }
        onClicked: function(mouse) {
          root.controller.setVolume(Math.max(0, Math.min(100, Math.round((mouse.x / width) * 100))))
        }
      }
    }
  }
}
