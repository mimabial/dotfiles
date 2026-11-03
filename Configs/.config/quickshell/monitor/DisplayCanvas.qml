pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import "Model.js" as Model

Item {
  id: root

  property var profile: ({ outputs: [] })
  property var editorDisplays: []
  property var workspacePlan: []
  property string selectedKey: ""
  property bool selectable: false
  property bool movable: false
  property string emphasis: "layout"
  property bool markDisconnected: false
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.5)
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family

  signal outputSelected(string key)
  signal outputMoved(string key, int x, int y, int snapDistance)

  readonly property var displays: Model.profileLayoutDisplays(profile, editorDisplays)
  readonly property var bounds: Model.layoutBounds(displays)
  readonly property var metrics: Model.layoutMetrics(bounds, canvas.width, canvas.height, Commons.Style.space(8))
  readonly property string hiddenDisplays: Model.hiddenProfileDisplays(profile)
  readonly property bool strongWorkspaces: emphasis !== "layout"
  readonly property int cardPadding: Commons.Style.space(6)
  readonly property int lineSpacing: Commons.Style.space(2)
  readonly property int chipPadding: Commons.Style.space(4)
  readonly property int chipSpacing: Commons.Style.space(3)

  implicitHeight: Commons.Style.space(205)

  FontMetrics {
    id: chipMetrics
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    font.bold: true
  }

  Text {
    textFormat: Text.PlainText
    id: hiddenLabel
    visible: root.hiddenDisplays !== ""
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.leftMargin: Commons.Style.space(10)
    anchors.rightMargin: Commons.Style.space(10)
    anchors.topMargin: Commons.Style.space(7)
    text: root.hiddenDisplays
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
    elide: Text.ElideRight
  }

  Item {
    id: canvas
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: hiddenLabel.visible ? hiddenLabel.bottom : parent.top
    anchors.bottom: parent.bottom
    anchors.margins: Commons.Style.space(8)
    anchors.topMargin: hiddenLabel.visible ? Commons.Style.space(5) : Commons.Style.space(8)

    Item {
      id: grid
      readonly property int columns: 7
      readonly property int rows: 5
      anchors.fill: parent

      Repeater {
        model: grid.columns + 1
        Rectangle {
          required property int index
          x: Math.round(index * grid.width / grid.columns)
          width: 1
          height: grid.height
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        }
      }

      Repeater {
        model: grid.rows + 1
        Rectangle {
          required property int index
          y: Math.round(index * grid.height / grid.rows)
          width: grid.width
          height: 1
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)
        }
      }
    }

    Repeater {
      model: root.displays

      Rectangle {
        id: card
        required property var modelData
        readonly property var previewRect: Model.layoutRect(modelData, root.bounds, canvas.width, canvas.height, Commons.Style.space(8))
        property real dragOffsetX: 0
        property real dragOffsetY: 0
        readonly property bool selected: String(modelData.key || "") === root.selectedKey
        readonly property bool disconnected: root.markDisconnected && modelData.connected === false
        readonly property var workspaceIds: Model.workspaceIds(root.workspacePlan, modelData.key)
        readonly property real chipWidth: Math.max(0, ...workspaceIds.map(id => chipMetrics.advanceWidth(id))) + root.chipPadding * 2
        readonly property real chipStep: chipWidth + root.chipSpacing
        readonly property int shownChips: workspaceIds.length * chipStep - root.chipSpacing <= content.width
          ? workspaceIds.length
          : Math.max(0, Math.floor((content.width - chipMetrics.advanceWidth("+" + workspaceIds.length)) / chipStep))
        readonly property bool chipsOnNameRow: workspaceIds.length > 0
          && nameText.implicitWidth + root.chipSpacing + chipRow.width <= content.width
        readonly property int lineBudget: Math.max(1, Math.floor((content.height + root.lineSpacing) / (nameText.implicitHeight + root.lineSpacing)))
        readonly property var rows: [
          "name",
          disconnected ? "disconnected" : "",
          workspaceIds.length > 0 && !chipsOnNameRow ? "workspaces" : "",
          "model",
          "mode",
          "placement"
        ].filter(Boolean).slice(0, lineBudget)

        function shows(row) { return rows.indexOf(row) !== -1 }

        x: previewRect.x + dragOffsetX
        y: previewRect.y + dragOffsetY
        width: previewRect.width
        height: previewRect.height
        radius: Math.min(Commons.Style.cornerRadius, Commons.Style.space(5))
        color: selected
          ? Commons.Style.selectedFillFor(root.foreground, root.accent)
          : Commons.Style.normalFillFor(root.foreground, root.accent)
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.55)

        Behavior on color { ColorAnimation { duration: 100 } }

        Item {
          id: content
          anchors.fill: parent
          anchors.margins: root.cardPadding

          Column {
            width: parent.width
            spacing: root.lineSpacing

            Text {
              id: nameText
              textFormat: Text.PlainText
              width: card.chipsOnNameRow ? parent.width - chipRow.width - root.chipSpacing : parent.width
              text: String(card.modelData.name || "Display")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              visible: card.shows("disconnected")
              width: parent.width
              text: "not connected"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
              font.italic: true
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              visible: card.shows("model")
              width: parent.width
              text: Model.displayModelLabel(card.modelData, false)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
              elide: Text.ElideRight
            }

            Item {
              id: chipSlot
              visible: card.shows("workspaces")
              width: parent.width
              height: nameText.implicitHeight
            }
          }

          Row {
            id: chipRow
            visible: card.chipsOnNameRow || card.shows("workspaces")
            x: card.chipsOnNameRow ? content.width - width : 0
            y: card.chipsOnNameRow ? 0 : chipSlot.y
            spacing: root.chipSpacing

            Repeater {
              model: card.workspaceIds.slice(0, card.shownChips)

              Rectangle {
                id: chip
                required property string modelData
                width: card.chipWidth
                height: nameText.implicitHeight
                radius: Math.min(Commons.Style.cornerRadius, Commons.Style.space(3))
                color: root.strongWorkspaces
                  ? Commons.Style.selectionFillFor(root.foreground, root.accent)
                  : Commons.Style.focusFillFor(root.foreground, root.accent)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: chip.modelData
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Commons.Style.font.caption
                  font.bold: root.strongWorkspaces
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: card.shownChips < card.workspaceIds.length
              text: "+" + (card.workspaceIds.length - card.shownChips)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
              font.bold: true
            }
          }

          Column {
            anchors.bottom: parent.bottom
            width: parent.width
            spacing: root.lineSpacing

            Text {
              textFormat: Text.PlainText
              visible: card.shows("mode")
              width: parent.width
              text: Model.modeLabel(card.modelData.mode)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              visible: card.shows("placement")
              width: parent.width
              text: Model.placementLabel(card.modelData)
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        MouseArea {
          id: dragArea
          anchors.fill: parent
          enabled: root.selectable
          hoverEnabled: true
          cursorShape: root.movable
            ? (dragStarted ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
            : Qt.PointingHandCursor
          // Pointer coordinates must come from the stationary canvas. Using
          // mouse.x/y directly makes the origin move with the card and feeds
          // the card's own movement back into the next drag delta.
          property real pointerStartX: 0
          property real pointerStartY: 0
          property bool dragStarted: false

          onPressed: function(mouse) {
            root.outputSelected(String(card.modelData.key || ""))
            var point = dragArea.mapToItem(canvas, mouse.x, mouse.y)
            pointerStartX = point.x
            pointerStartY = point.y
            dragStarted = false
            card.dragOffsetX = 0
            card.dragOffsetY = 0
          }
          onPositionChanged: function(mouse) {
            if (!pressed || !root.movable) return
            var point = dragArea.mapToItem(canvas, mouse.x, mouse.y)
            var deltaX = point.x - pointerStartX
            var deltaY = point.y - pointerStartY
            if (!dragStarted) {
              var threshold = Commons.Style.space(6)
              if (deltaX * deltaX + deltaY * deltaY < threshold * threshold) return
              dragStarted = true
            }
            card.dragOffsetX = deltaX
            card.dragOffsetY = deltaY
          }
          onReleased: function(mouse) {
            if (!root.movable || !dragStarted) {
              card.dragOffsetX = 0
              card.dragOffsetY = 0
              return
            }
            var scale = Math.max(0.0001, Number(root.metrics.scale || 1))
            var nextX = Math.round(Number(card.modelData.x || 0) + card.dragOffsetX / scale)
            var nextY = Math.round(Number(card.modelData.y || 0) + card.dragOffsetY / scale)
            var snap = Math.max(1, Math.round(Commons.Style.space(12) / scale))
            card.dragOffsetX = 0
            card.dragOffsetY = 0
            dragStarted = false
            root.outputMoved(String(card.modelData.key || ""), nextX, nextY, snap)
          }
          onCanceled: {
            dragStarted = false
            card.dragOffsetX = 0
            card.dragOffsetY = 0
          }
        }
      }
    }

    Text {
      textFormat: Text.PlainText
      visible: root.displays.length === 0
      anchors.centerIn: parent
      text: "No enabled displays"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.body
    }
  }
}
