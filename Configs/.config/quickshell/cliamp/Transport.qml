pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

Row {
  id: root
  property var p  // Panel root

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  PanelActionButton {
    iconText: "\uf074"; tooltipText: "Shuffle: " + (root.p.shuffleMode ? "ON" : "OFF")
    foreground: root.p.shuffleMode ? Color.accent : root.p.dim
    hoverColor: Color.accent; fontFamily: root.p.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.p.toggleShuffle()
  }

  PanelActionButton {
    iconText: "\uf048"; tooltipText: "Previous Track"
    foreground: root.p.foreground; hoverColor: Color.accent; fontFamily: root.p.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.p.prevTrack()
  }

  PanelActionButton {
    iconText: root.p.isPlaying ? "\uf04c" : "\uf04b"
    tooltipText: root.p.isPlaying ? "Pause" : "Play"
    foreground: root.p.isPlaying ? Color.accent : root.p.foreground
    hoverColor: Color.accent; fontFamily: root.p.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.p.togglePlayback()
  }

  PanelActionButton {
    iconText: "\uf051"; tooltipText: "Next Track"
    foreground: root.p.foreground; hoverColor: Color.accent; fontFamily: root.p.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.p.nextTrack()
  }

  PanelActionButton {
    iconText: "\uf01e"; tooltipText: "Repeat: " + root.p.repeatMode.toUpperCase()
    foreground: root.p.repeatMode !== "off" ? Color.accent : root.p.dim
    hoverColor: Color.accent; fontFamily: root.p.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.p.cycleRepeat()
  }

  PanelActionButton {
    iconText: "\uf04d"; tooltipText: "Stop Playback"
    foreground: root.p.foreground; hoverColor: root.p.urgent; fontFamily: root.p.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.p.stop()
  }

  PanelActionButton {
    iconText: root.p.currentLiked ? "\uf004" : "\uf08a"
    tooltipText: root.p.currentLiked ? "Remove from Liked" : "Add to Liked"
    foreground: root.p.currentLiked ? root.p.urgent : root.p.dim
    hoverColor: root.p.urgent; fontFamily: root.p.fontFamily
    anchors.verticalCenter: parent.verticalCenter
    onClicked: root.p.toggleLiked()
  }

  Item { width: Style.space(4) }

  Row {
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(5)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.p.volumePct === 0 ? "\uf026" : (root.p.volumePct < 50 ? "\uf027" : "\uf028")
      color: root.p.volumePct === 0 ? root.p.urgent : (volIconMouse.containsMouse ? Color.accent : root.p.dim)
      font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
      MouseArea {
        id: volIconMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: root.p.toggleMute()
      }
    }

    Item {
      width: Style.space(64); height: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width; height: Style.space(4); radius: Style.space(2)
        color: root.p.shell.alpha(root.p.shell.role("br", root.p.foreground), 0.25)

        Rectangle {
          width: Math.max(Style.space(2), parent.width * (root.p.volumePct / 100.0))
          height: parent.height; radius: Style.space(2); color: Color.accent
        }
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onPositionChanged: function(mouse) {
          if (pressed) root.p.setVolume(Math.max(0, Math.min(100, Math.round((mouse.x / width) * 100))))
        }
        onClicked: function(mouse) {
          root.p.setVolume(Math.max(0, Math.min(100, Math.round((mouse.x / width) * 100))))
        }
      }
    }
  }
}
