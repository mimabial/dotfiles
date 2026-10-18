pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons

Item {
  id: root

  property var items: []
  property color foreground: Commons.Color.popups.text
  property string fontFamily: Commons.Style.font.family

  width: parent ? parent.width : implicitWidth
  implicitHeight: Commons.Style.space(18)
  height: implicitHeight

  Row {
    anchors.fill: parent
    spacing: Commons.Style.space(12)

    Repeater {
      model: root.items.length

      delegate: Item {
        id: entry
        required property int index
        readonly property var modelData: root.items[index] || ({})
        readonly property int count: Math.max(1, root.items.length)
        width: (root.width - Commons.Style.space(12) * (count - 1)) / count
        height: root.height

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Commons.Style.space(6)
          width: Math.min(implicitWidth, parent.width - figure.width - Commons.Style.space(6))
          clip: true

          Rectangle {
            width: Commons.Style.space(8)
            height: width
            radius: width / 2
            color: entry.modelData.color || root.foreground
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            textFormat: Text.PlainText
            text: entry.modelData.label || ""
            color: root.foreground
            opacity: Commons.Style.secondaryTextAlpha
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
          }
        }

        Measure {
          id: figure
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          value: entry.modelData.value === undefined ? "" : String(entry.modelData.value)
          unit: entry.modelData.unit || ""
          foreground: root.foreground
          fontFamily: root.fontFamily
          valueSize: Commons.Style.font.bodySmall
          unitSize: Commons.Style.font.caption
        }
      }
    }
  }
}
