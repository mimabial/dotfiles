pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

BorderSurface {
  id: root
  property var controller: null

  readonly property var presets: [
    { id: "Flat", name: "Flat (Original)", icon: "\uf1de", desc: "Pure unprocessed audio with 0 dB flat response" },
    { id: "Bass Boost", name: "Bass Boost", icon: "\uf028", desc: "Enhanced low-end sub-bass & kick drum punch" },
    { id: "Rock", name: "Rock & Metal", icon: "\uf0e7", desc: "Punchy low-mids and crisp treble drive" },
    { id: "Electronic", name: "Electronic / EDM", icon: "\uf025", desc: "Deep club bass with sparkling highs" },
    { id: "Pop", name: "Pop / Modern", icon: "\uf005", desc: "Warm vocal focus with balanced soundstage" },
    { id: "Vocal Clarity", name: "Vocal Clarity", icon: "\uf130", desc: "Clear voice boost for speech, podcasts & lyrics" },
    { id: "Acoustic", name: "Acoustic / Live", icon: "\uf001", desc: "Natural warm balance for strings & instruments" },
    { id: "Treble Boost", name: "Treble Boost", icon: "\uf0f3", desc: "Airy, crisp, high-frequency brightness" },
    { id: "Late Night", name: "Late Night Mode", icon: "\uf186", desc: "Reduced bass rumble with clear quiet speech" }
  ]

  width: parent ? parent.width : 0
  implicitHeight: Style.space(200)
  radius: Style.cornerRadius
  color: "transparent"
  borderSpec: Border.none()

  Column {
    anchors.fill: parent
    anchors.margins: Style.space(8)
    spacing: Style.space(6)

    Row {
      width: parent.width
      spacing: Style.space(6)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf1de"
        color: Color.accent; font.family: root.controller ? root.controller.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width - Style.space(48)
        anchors.verticalCenter: parent.verticalCenter
        text: "Equalizer Profiles (" + (root.controller ? root.controller.eqText : "Flat") + ")"
        color: root.controller ? root.controller.foreground : Color.foreground
        font.family: root.controller ? root.controller.fontFamily : "sans-serif"
        font.pixelSize: Style.font.caption; font.bold: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf00d"
        color: closeEqMouse.containsMouse ? Color.accent : (root.controller ? root.controller.dim : Color.foreground)
        font.family: root.controller ? root.controller.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption
        MouseArea {
          id: closeEqMouse
          anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
          onClicked: if (root.controller) root.controller.eqPickerOpen = false
        }
      }
    }

    Row {
      width: parent.width
      spacing: Style.space(6)

      Rectangle {
        id: loudnormBtn
        readonly property bool active: root.controller && root.controller.audioFx && root.controller.audioFx.loudnorm
        width: (parent.width - Style.space(6)) / 2
        height: Style.space(24)
        radius: Style.space(4)
        color: active ? Color.menu.selectedBackground
          : (loudMouse.containsMouse ? (root.controller ? root.controller.shell.hoverFill(1) : Color.menu.selectedBackground)
            : (root.controller ? root.controller.shell.alpha(root.controller.surface, 0.8) : Color.popups.background))
        border.width: 1
        border.color: active || loudMouse.containsMouse ? Color.menu.selectedBorder : "transparent"

        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)
          Text {
            text: "\uf028"
            color: loudnormBtn.active ? Color.menu.selectedText : (root.controller ? root.controller.dim : Color.foreground)
            font.family: root.controller ? root.controller.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption * 0.8
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "Normalizer"
            color: loudnormBtn.active ? Color.menu.selectedText : (root.controller ? root.controller.foreground : Color.foreground)
            font.family: root.controller ? root.controller.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption * 0.8
            font.bold: loudnormBtn.active
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: loudMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root.controller) root.controller.toggleLoudnorm()
        }
      }

      Rectangle {
        id: spatialBtn
        readonly property bool active: root.controller && root.controller.audioFx && root.controller.audioFx.spatial
        width: (parent.width - Style.space(6)) / 2
        height: Style.space(24)
        radius: Style.space(4)
        color: active ? Color.menu.selectedBackground
          : (spatialMouse.containsMouse ? (root.controller ? root.controller.shell.hoverFill(1) : Color.menu.selectedBackground)
            : (root.controller ? root.controller.shell.alpha(root.controller.surface, 0.8) : Color.popups.background))
        border.width: 1
        border.color: active || spatialMouse.containsMouse ? Color.menu.selectedBorder : "transparent"

        Row {
          anchors.centerIn: parent
          spacing: Style.space(4)
          Text {
            text: "\uf025"
            color: spatialBtn.active ? Color.menu.selectedText : (root.controller ? root.controller.dim : Color.foreground)
            font.family: root.controller ? root.controller.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption * 0.8
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: "3D Spatial"
            color: spatialBtn.active ? Color.menu.selectedText : (root.controller ? root.controller.foreground : Color.foreground)
            font.family: root.controller ? root.controller.fontFamily : "sans-serif"; font.pixelSize: Style.font.caption * 0.8
            font.bold: spatialBtn.active
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        MouseArea {
          id: spatialMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
          onClicked: if (root.controller) root.controller.toggleSpatial()
        }
      }
    }

    Flickable {
      width: parent.width
      height: parent.height - Style.space(56)
      contentWidth: width; contentHeight: presetCol.implicitHeight
      clip: true; boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: presetCol
        width: parent.width
        spacing: Style.space(4)

        Repeater {
          model: root.presets
          delegate: Rectangle {
            required property var modelData
            id: presetRow
            readonly property bool isActive: root.controller && root.controller.eqText === modelData.id
            width: parent.width
            height: Style.space(32)
            radius: Style.space(4)
            color: isActive ? Color.menu.selectedBackground
              : (rowMouse.containsMouse ? (root.controller ? root.controller.shell.hoverFill(1) : Color.menu.selectedBackground) : "transparent")
            border.width: 1
            border.color: isActive || rowMouse.containsMouse ? Color.menu.selectedBorder : "transparent"

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(8)

              Text {
                text: presetRow.modelData.icon
                color: presetRow.isActive ? Color.menu.selectedText : (root.controller ? root.controller.foreground : Color.foreground)
                font.family: root.controller ? root.controller.fontFamily : "sans-serif"
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                width: parent.width - Style.space(50)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                  width: parent.width
                  text: presetRow.modelData.name
                  color: presetRow.isActive ? Color.menu.selectedText : (root.controller ? root.controller.foreground : Color.foreground)
                  font.family: root.controller ? root.controller.fontFamily : "sans-serif"
                  font.pixelSize: Style.font.caption
                  font.bold: presetRow.isActive
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: presetRow.modelData.desc
                  color: root.controller ? root.controller.dim : Color.foreground
                  font.family: root.controller ? root.controller.fontFamily : "sans-serif"
                  font.pixelSize: Style.font.caption * 0.8
                  elide: Text.ElideRight
                }
              }

              Text {
                visible: presetRow.isActive
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf00c"
                color: Color.menu.selectedText
                font.family: root.controller ? root.controller.fontFamily : "sans-serif"
                font.pixelSize: Style.font.caption * 0.8
              }
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.controller) root.controller.setEq(presetRow.modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
