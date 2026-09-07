import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Visualizer style selector with instant categorized picking
BorderSurface {
  id: root
  property var p  // Panel root
  property string selectedCategory: "all"

  readonly property var allModes: [
    // Classic & VU
    { id: "bars", name: "Bars", category: "classic", icon: "\uf080" },
    { id: "classic_led", name: "Classic LED", category: "classic", icon: "\uf111" },
    { id: "peaks", name: "Peaks", category: "classic", icon: "\uf012" },
    { id: "bricks", name: "Bricks", category: "classic", icon: "\uf0c9" },
    { id: "stereo", name: "Stereo VU", category: "classic", icon: "\uf025" },
    { id: "correlation", name: "Correlation", category: "classic", icon: "\uf07e" },
    { id: "ascii", name: "ASCII", category: "classic", icon: "\uf121" },

    // Waves & Scopes
    { id: "siriwave", name: "Siri Wave", category: "wave", icon: "\uf179" },
    { id: "soundcloud_wave", name: "SoundCloud Wave", category: "wave", icon: "\uf1be" },
    { id: "telegram_wave", name: "Telegram Wave", category: "wave", icon: "\uf130" },
    { id: "daw_wave", name: "DAW Peak Wave", category: "wave", icon: "\uf080" },
    { id: "led_scrubber", name: "LED Scrubber", category: "wave", icon: "\uf009" },
    { id: "heatmap_wave", name: "Heatmap Wave", category: "wave", icon: "\uf06d" },
    { id: "grounded_wave", name: "Baseline Wave", category: "wave", icon: "\uf012" },
    { id: "wave", name: "Waveform", category: "wave", icon: "\uf21e" },
    { id: "sine", name: "Sine Wave", category: "wave", icon: "\uf1d8" },
    { id: "mirror", name: "Mirror", category: "wave", icon: "\uf042" },

    // Synth & Retro
    { id: "retro", name: "Retro Synth", category: "retro", icon: "\uf185" },
    { id: "matrix", name: "Matrix", category: "retro", icon: "\uf108" },
    { id: "terrain", name: "Terrain", category: "retro", icon: "\uf06e" },
    { id: "binary", name: "Binary", category: "retro", icon: "\uf120" },
    { id: "mosaic", name: "Mosaic", category: "retro", icon: "\uf009" },

    // Particles & Nature
    { id: "butterfly", name: "Butterfly", category: "particle", icon: "\uf1d8" },
    { id: "scatter", name: "Scatter", category: "particle", icon: "\uf005" },
    { id: "rain", name: "Rain", category: "particle", icon: "\uf0e9" },

    // 3D & Vector
    { id: "plasma", name: "Liquid Plasma (2D)", category: "3d", icon: "\uf043" },
    { id: "osc_warp", name: "Oscilloscope Warp", category: "3d", icon: "\uf1fe" },
    { id: "crt_scanline", name: "CRT Radar Scope", category: "3d", icon: "\uf26c" },
    { id: "cyber_tunnel", name: "3D Cyber Tunnel", category: "3d", icon: "\uf135" }
  ]

  readonly property var filteredModes: {
    if (selectedCategory === "all") return allModes
    var res = []
    for (var i = 0; i < allModes.length; i++) {
      if (allModes[i].category === selectedCategory) res.push(allModes[i])
    }
    return res
  }

  width: parent ? parent.width : 0
  implicitHeight: Style.space(200)
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.none()

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    // Header with title and close button
    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf0d0"
        color: Color.accent; font.family: root.p ? root.p.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width - Style.space(54) - bgToggle.width - pulseToggle.width - Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: "Visualizer Styles (" + root.allModes.length + ")"
        color: root.p ? root.p.foreground : Color.foreground
        font.family: root.p ? root.p.fontFamily : "sans-serif"
        font.pixelSize: Style.font.caption; font.bold: true
      }

      Rectangle {
        id: bgToggle
        readonly property bool active: root.p ? root.p.visBackground : false
        anchors.verticalCenter: parent.verticalCenter
        width: bgLabel.implicitWidth + Style.space(10); height: Style.space(17)
        radius: Style.space(4)
        color: active ? Color.menu.selectedBackground
          : (bgMouse.containsMouse ? (root.p ? root.p.shell.hoverFill(1) : Color.menu.selectedBackground) : "transparent")
        border.width: 1
        border.color: active ? Color.menu.selectedBorder
          : (root.p ? root.p.shell.alpha(root.p.shell.role("br", root.p.foreground), 0.25) : Color.popups.border)

        Text {
          id: bgLabel
          anchors.centerIn: parent
          text: "\uf043 BG"
          color: bgToggle.active ? Color.menu.selectedText
            : (bgMouse.containsMouse ? Color.accent : (root.p ? root.p.dim : Color.foreground))
          font.family: root.p ? root.p.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption * 0.8
          font.bold: bgToggle.active
        }

        MouseArea {
          id: bgMouse
          anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root.p) root.p.setVisBackground(!root.p.visBackground)
        }
      }

      Rectangle {
        id: pulseToggle
        readonly property bool active: root.p ? root.p.visBackgroundPulse : false
        anchors.verticalCenter: parent.verticalCenter
        width: pulseLabel.implicitWidth + Style.space(10); height: Style.space(17)
        radius: Style.space(4)
        color: active ? Color.menu.selectedBackground
          : (pulseMouse.containsMouse ? (root.p ? root.p.shell.hoverFill(1) : Color.menu.selectedBackground) : "transparent")
        border.width: 1
        border.color: active ? Color.menu.selectedBorder
          : (root.p ? root.p.shell.alpha(root.p.shell.role("br", root.p.foreground), 0.25) : Color.popups.border)

        Text {
          id: pulseLabel
          anchors.centerIn: parent
          text: "\uf0e7 PULSE"
          color: pulseToggle.active ? Color.menu.selectedText
            : (pulseMouse.containsMouse ? Color.accent : (root.p ? root.p.dim : Color.foreground))
          font.family: root.p ? root.p.fontFamily : "sans-serif"
          font.pixelSize: Style.font.caption * 0.8
          font.bold: pulseToggle.active
        }

        MouseArea {
          id: pulseMouse
          anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root.p) root.p.setVisBackgroundPulse(!root.p.visBackgroundPulse)
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf00d"
        color: closePickerMouse.containsMouse ? Color.accent : (root.p ? root.p.dim : Color.foreground)
        font.family: root.p ? root.p.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption
        MouseArea {
          id: closePickerMouse
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
          onClicked: if (root.p) root.p.visPickerOpen = false
        }
      }
    }

    // Category Tabs
    Row {
      width: parent.width
      spacing: Style.space(4)

      Repeater {
        model: [
          { id: "all", label: "All" },
          { id: "classic", label: "Classic" },
          { id: "wave", label: "Wave" },
          { id: "retro", label: "Retro" },
          { id: "particle", label: "Particle" },
          { id: "3d", label: "3D" }
        ]
        delegate: Rectangle {
          required property var modelData
          id: tabPill
          readonly property bool isSelected: root.selectedCategory === modelData.id
          width: tabLabel.implicitWidth + Style.space(10); height: Style.space(18)
          radius: Style.space(9)
          color: isSelected ? Color.menu.selectedBackground
            : (tabMouse.containsMouse ? (root.p ? root.p.shell.hoverFill(1) : Color.menu.selectedBackground) : "transparent")

          Text {
            id: tabLabel
            anchors.centerIn: parent
            text: modelData.label
            color: tabPill.isSelected ? Color.menu.selectedText : (root.p ? root.p.foreground : Color.foreground)
            font.family: root.p ? root.p.fontFamily : "sans-serif"
            font.pixelSize: Style.font.caption * 0.85
            font.bold: tabPill.isSelected
          }

          MouseArea {
            id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.selectedCategory = modelData.id
          }
        }
      }
    }

    // Modes Grid / Flow inside Flickable
    Flickable {
      width: parent.width
      height: parent.height - Style.space(46)
      contentWidth: width; contentHeight: flowGrid.implicitHeight
      clip: true; boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Flow {
        id: flowGrid
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.filteredModes
          delegate: Rectangle {
            required property var modelData
            id: chip
            readonly property bool isActive: root.p && root.p.visMode === modelData.id
            width: chipContent.implicitWidth + Style.space(12)
            height: Style.space(22)
            radius: Style.space(4)
            color: isActive ? Color.menu.selectedBackground
              : (chipMouse.containsMouse ? (root.p ? root.p.shell.hoverFill(1) : Color.menu.selectedBackground)
                : (root.p ? root.p.shell.alpha(root.p.surface, 0.8) : Color.popups.background))
            border.width: 1
            border.color: isActive ? Color.menu.selectedBorder
              : (chipMouse.containsMouse ? Color.menu.selectedBorder
                : (root.p ? root.p.shell.alpha(root.p.shell.role("br", root.p.foreground), 0.25) : Color.popups.border))

            Row {
              id: chipContent
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: modelData.icon
                color: chip.isActive ? Color.menu.selectedText
                  : (chipMouse.containsMouse ? Color.accent : (root.p ? root.p.dim : Color.foreground))
                font.family: root.p ? root.p.fontFamily : "sans-serif"
                font.pixelSize: Style.font.caption * 0.8
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: modelData.name
                color: chip.isActive ? Color.menu.selectedText
                  : (chipMouse.containsMouse ? Color.accent : (root.p ? root.p.foreground : Color.foreground))
                font.family: root.p ? root.p.fontFamily : "sans-serif"
                font.pixelSize: Style.font.caption * 0.85
                font.bold: chip.isActive
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: chipMouse
              anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.p) {
                  root.p.setVisMode(modelData.id)
                }
              }
            }
          }
        }
      }
    }
  }
}
