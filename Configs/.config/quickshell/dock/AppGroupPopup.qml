pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

BorderSurface {
  id: popup
  required property var dock

  readonly property bool hovered: hover.hovered
  readonly property var group: dock.activeAppGroupData
  readonly property var appIds: group ? DockModel.toArray(group.apps) : []
  readonly property int columns: Math.min(4, Math.max(2, appIds.length <= 4 ? 2 : appIds.length <= 9 ? 3 : 4))
  readonly property real cellWidth: Style.space(64)
  readonly property real cellHeight: Style.space(70)

  visible: dock.activeAppGroupId !== "" && dock.dockVisible
  z: 100
  color: Util.alpha(Color.menu.background, dock.dockSurfaceOpacity)
  borderSpec: Border.surfaceSpec("menu", "border", Util.alpha(Color.menu.border, Style.popupBorderOpacity), 1)
  radius: Style.cornerRadius
  padding: Style.space(6)
  width: Math.max(Style.space(180), columns * cellWidth + (columns - 1) * Style.space(6))
    + contentLeftInset + contentRightInset
  height: content.implicitHeight + contentTopInset + contentBottomInset
  x: dock.vertical ? dock.panelCross(width) : dock.panelMain(width, dock.activeAppGroupAnchor)
  y: dock.vertical ? dock.panelMain(height, dock.activeAppGroupAnchor) : dock.panelCross(height)

  HoverHandler { id: hover }

  function finishRename() {
    if (popup.group) popup.dock.renameAppGroup(popup.group.id, nameInput.text)
    popup.dock.appGroupEditing = false
  }

  Column {
    id: content
    spacing: Style.space(6)
    anchors {
      left: parent.left; right: parent.right; top: parent.top
      leftMargin: popup.contentLeftInset; rightMargin: popup.contentRightInset; topMargin: popup.contentTopInset
    }

    Item {
      width: parent.width
      height: Style.space(26)

      Text {
        id: title
        visible: !popup.dock.appGroupEditing
        anchors.verticalCenter: parent.verticalCenter
        text: popup.group ? String(popup.group.name || "Applications") : "Applications"
        textFormat: Text.PlainText
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }

      Text {
        visible: title.visible
        anchors.left: title.right
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: "(" + popup.appIds.length + ")"
        textFormat: Text.PlainText
        color: Util.alpha(Color.menu.text, 0.5)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: title
        visible: title.visible
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          nameInput.text = title.text
          popup.dock.appGroupEditing = true
          Qt.callLater(function() { nameInput.forceActiveFocus(); nameInput.selectAll() })
        }
      }

      Rectangle {
        visible: popup.dock.appGroupEditing
        anchors.fill: parent
        radius: Style.cornerRadius
        color: Util.alpha(Color.menu.text, 0.06)
        border.color: Color.accent
        border.width: 1

        TextInput {
          id: nameInput
          anchors.fill: parent
          anchors.margins: Style.space(4)
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          verticalAlignment: TextInput.AlignVCenter
          selectByMouse: true
          onAccepted: popup.finishRename()
          Keys.onEscapePressed: popup.dock.appGroupEditing = false
        }
      }
    }

    Grid {
      columns: popup.columns
      spacing: Style.space(6)
      anchors.horizontalCenter: parent.horizontalCenter

      Repeater {
        model: popup.appIds
        delegate: Item {
          id: cell
          required property var modelData
          width: popup.cellWidth
          height: popup.cellHeight
          readonly property string appId: String(modelData || "")
          readonly property var entry: popup.dock.appLibrary.lookup(appId)
            || DockModel.entryFor(popup.dock.appRows, appId)
          property point dragStart: Qt.point(0, 0)
          property bool dragging: false
          property bool dragEnded: false

          Rectangle {
            anchors.fill: parent
            radius: Style.cornerRadius
            color: area.containsMouse ? Util.alpha(Color.menu.text, 0.08) : "transparent"
          }

          Column {
            anchors.centerIn: parent
            width: parent.width - Style.space(8)
            spacing: Style.space(4)
            Image {
              anchors.horizontalCenter: parent.horizontalCenter
              width: Style.space(36)
              height: width
              source: popup.dock.appLibrary.iconSource(cell.entry ? cell.entry.icon : cell.appId)
              sourceSize: Qt.size(width * 2, height * 2)
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              mipmap: true
            }
            Text {
              width: parent.width
              text: cell.entry ? popup.dock.appLibrary.entryName(cell.entry) : cell.appId
              textFormat: Text.PlainText
              color: Color.menu.text
              font.family: Style.font.family
              font.pixelSize: Math.max(9, Style.font.caption - 1)
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: cell.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            onPressed: function(mouse) {
              cell.dragStart = Qt.point(mouse.x, mouse.y)
              cell.dragging = false
              cell.dragEnded = false
            }
            onPositionChanged: function(mouse) {
              if (!(mouse.buttons & Qt.LeftButton)) return
              var dx = mouse.x - cell.dragStart.x
              var dy = mouse.y - cell.dragStart.y
              if (!cell.dragging && Math.sqrt(dx * dx + dy * dy) > 10) {
                cell.dragging = true
                popup.dock.dragAppId = cell.appId
                popup.dock.dragSourceGroupId = popup.group.id
              }
              if (cell.dragging) {
                var point = cell.mapToItem(popup.dock.dockCardItem, mouse.x, mouse.y)
                popup.dock.updateDragTarget(cell.appId, popup.dock.vertical ? point.y : point.x)
              }
            }
            onReleased: function(mouse) {
              if (!cell.dragging) return
              cell.dragging = false
              cell.dragEnded = true
              popup.dock.finishDrag()
              popup.dock.closeAppGroup()
            }
            onCanceled: if (cell.dragging) {
              cell.dragging = false
              popup.dock.finishDrag()
              popup.dock.closeAppGroup()
            }
            onClicked: function(mouse) {
              if (cell.dragEnded) { cell.dragEnded = false; return }
              if (mouse.button === Qt.RightButton)
                popup.dock.removeAppFromGroup(popup.group.id, cell.appId, true)
              else {
                popup.dock.activate(cell.appId)
                popup.dock.closeAppGroup()
              }
            }
          }
        }
      }
    }
  }
}
