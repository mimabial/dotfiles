pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import qs.Ui

Row {
  id: root
  required property var controller

  width: parent ? parent.width : 0
  spacing: Commons.Style.space(6)

  PanelActionButton {
    iconText: "\uf074"; tooltipText: "Shuffle: " + (root.controller.shuffleMode ? "ON" : "OFF")
    foreground: root.controller.shuffleMode ? Commons.Color.accent : root.controller.dim
    hoverColor: Commons.Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.toggleShuffle()
  }

  PanelActionButton {
    iconText: "\uf048"; tooltipText: "Previous Track"
    foreground: root.controller.foreground; hoverColor: Commons.Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.prevTrack()
  }

  PanelActionButton {
    iconText: root.controller.isPlaying ? "\uf04c" : "\uf04b"
    tooltipText: root.controller.isPlaying ? "Pause" : "Play"
    foreground: root.controller.isPlaying ? Commons.Color.accent : root.controller.foreground
    hoverColor: Commons.Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.togglePlayback()
  }

  PanelActionButton {
    iconText: "\uf051"; tooltipText: "Next Track"
    foreground: root.controller.foreground; hoverColor: Commons.Color.accent; fontFamily: root.controller.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.controller.nextTrack()
  }

  PanelActionButton {
    iconText: "\uf01e"; tooltipText: "Repeat: " + root.controller.repeatMode.toUpperCase()
    foreground: root.controller.repeatMode !== "off" ? Commons.Color.accent : root.controller.dim
    hoverColor: Commons.Color.accent; fontFamily: root.controller.fontFamily
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

  Item { width: Commons.Style.space(4) }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Commons.Style.space(5)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Commons.Style.space(22); horizontalAlignment: Text.AlignHCenter
      text: root.controller.volumePct === 0 ? "\uf026" : (root.controller.volumePct < 50 ? "\uf027" : "\uf028")
      color: root.controller.volumePct === 0 ? root.controller.urgent : (volIconMouse.containsMouse ? Commons.Color.accent : root.controller.dim)
      font.family: root.controller.fontFamily; font.pixelSize: Commons.Style.font.caption
      MouseArea {
        id: volIconMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.controller.toggleMute()
      }
    }

    Item {
      width: Commons.Style.space(64); height: Commons.Style.space(16)
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Commons.Style.space(4); radius: Commons.Style.space(2)
        color: root.controller.shell.alpha(root.controller.shell.role("br", root.controller.foreground), 0.25)

        Rectangle {
          width: Math.max(Commons.Style.space(2), parent.width * (root.controller.volumePct / 100.0))
          height: parent.height; radius: Commons.Style.space(2); color: Commons.Color.accent
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
