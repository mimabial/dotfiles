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
    { id: "peaks", name: "Peaks", category: "classic", icon: "\uf012" },
    { id: "stereo", name: "Stereo VU", category: "classic", icon: "\uf025" },
    { id: "ascii", name: "ASCII", category: "classic", icon: "\uf121" },

    // Waves
    { id: "siriwave", name: "Siri Wave", category: "wave", icon: "\uf179" },
    { id: "soundcloud_wave", name: "SoundCloud Wave", category: "wave", icon: "\uf1be" },
    { id: "telegram_wave", name: "Telegram Wave", category: "wave", icon: "\uf130" },
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
        color: Color.accent; font.family: p ? p.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width - Style.space(48)
        anchors.verticalCenter: parent.verticalCenter
        text: "Visualizer Styles (" + root.allModes.length + ")"
        color: p ? p.foreground : Color.foreground
        font.family: p ? p.fontFamily : "sans-serif"
        font.pixelSize: Style.font.caption; font.bold: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf00d"
        color: closePickerMouse.containsMouse ? Color.accent : (p ? p.dim : Color.foreground)
        font.family: p ? p.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption
        MouseArea {
          id: closePickerMouse
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
          onClicked: if (p) p.visPickerOpen = false
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
          { id: "wave", label: "Wave" }
        ]
        delegate: Rectangle {
          id: tabPill
          readonly property bool isSelected: root.selectedCategory === modelData.id
          width: tabLabel.implicitWidth + Style.space(10); height: Style.space(18)
          radius: Style.space(9)
          color: isSelected ? Color.menu.selectedBackground
            : (tabMouse.containsMouse ? (p ? p.shell.hoverFill(1) : Color.menu.selectedBackground) : "transparent")

          Text {
            id: tabLabel
            anchors.centerIn: parent
            text: modelData.label
            color: tabPill.isSelected ? Color.menu.selectedText : (p ? p.foreground : Color.foreground)
            font.family: p ? p.fontFamily : "sans-serif"
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
            id: chip
            readonly property bool isActive: p && p.visMode === modelData.id
            width: chipContent.implicitWidth + Style.space(12)
            height: Style.space(22)
            radius: Style.space(4)
            color: isActive ? Color.menu.selectedBackground
              : (chipMouse.containsMouse ? (p ? p.shell.hoverFill(1) : Color.menu.selectedBackground)
                : (p ? p.shell.alpha(p.surface, 0.8) : Color.popups.background))
            border.width: 1
            border.color: isActive ? Color.menu.selectedBorder
              : (chipMouse.containsMouse ? Color.menu.selectedBorder
                : (p ? p.shell.alpha(p.shell.role("br", p.foreground), 0.25) : Color.popups.border))

            Row {
              id: chipContent
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                text: modelData.icon
                color: chip.isActive ? Color.menu.selectedText
                  : (chipMouse.containsMouse ? Color.accent : (p ? p.dim : Color.foreground))
                font.family: p ? p.fontFamily : "sans-serif"
                font.pixelSize: Style.font.caption * 0.8
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: modelData.name
                color: chip.isActive ? Color.menu.selectedText
                  : (chipMouse.containsMouse ? Color.accent : (p ? p.foreground : Color.foreground))
                font.family: p ? p.fontFamily : "sans-serif"
                font.pixelSize: Style.font.caption * 0.85
                font.bold: chip.isActive
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: chipMouse
              anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (p) {
                  p.setVisMode(modelData.id)
                }
              }
            }
          }
        }
      }
    }
  }
}
