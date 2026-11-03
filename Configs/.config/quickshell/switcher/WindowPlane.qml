import QtQuick
import QtQuick.Effects
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons as Commons
import "Depth.js" as Depth
import "Layout.js" as Layout
import "Field.js" as Field

Item {
  id: card

  required property var modelData
  required property int index

  required property var controller
  required property var theme
  required property var appearance
  property var stage: null
  property real unit: 1
  property real textUnit: unit

  readonly property var entry: modelData
  readonly property var toplevel: entry ? entry.toplevel : null
  readonly property int slot: controller && index < controller.slots.length ? controller.slots[index] : -1
  readonly property bool inField: slot >= 0
  readonly property real r: inField && controller ? slot - controller.cameraSlot : 0
  readonly property bool selected: controller !== null && index === controller.selectedIndex
  readonly property bool hovered: mouse.containsMouse
  readonly property bool urgent: !!(toplevel && toplevel.urgent)
  readonly property bool hasContent: capture.hasContent
  readonly property size sourceSize: capture.sourceSize
  readonly property bool capturing: controller !== null && controller.opened && inField
    && r > -1.2 && r < Layout.VISIBLE_STEPS + 0.5 && !!toplevel && !!toplevel.wayland

  readonly property real aspect: {
    if (capture.hasContent && capture.sourceSize.height > 0)
      return capture.sourceSize.width / capture.sourceSize.height
    const geometry = entry ? entry.geometry : null
    if (geometry && geometry.width > 0 && geometry.height > 0)
      return geometry.width / geometry.height
    return 1.6
  }

  readonly property var geometry: stage ? Layout.deepPlane(stage, r) : ({ x: 0, y: 0, width: 1, height: 1, scale: 1, opacity: 0, z: 0 })
  readonly property real depthScale: Math.min(1, geometry.scale)
  readonly property real headerHeight: Math.max(18 * textUnit, Math.min(30 * textUnit, geometry.height * 0.1))
  readonly property real pad: Math.max(3, 8 * unit * depthScale)
  readonly property var fittedPreview: Layout.fit(geometry.width - pad * 2,
    geometry.height - headerHeight - pad, aspect)
  readonly property real radius: card.appearance.cornerRadius * depthScale
  readonly property real fog: entry
    ? theme.fogStrength * Math.min(0.7, Math.max(0, Math.min(1, r)) * (0.12 + Depth.fogForDepth(entry.depth) * 0.75) + 0.05 * Math.max(0, r - 1))
    : 0
  readonly property string titleText: toplevel && toplevel.title ? String(toplevel.title) : (entry ? entry.title : "")
  readonly property bool parked: controller !== null && entry !== null
    && Layout.outside(controller.geometryOf(entry), controller.monitorInfo[entry.monitorName])
  readonly property var snapshot: controller && entry ? (controller.snapshots[entry.address] || null) : null
  readonly property bool showsSnapshot: !capture.hasContent && snapshot !== null

  function takeSnapshot() {
    if (!capture.hasContent || !controller || !controller.opened || !entry || !capturing) return
    if (!controller.wantsSnapshot(entry.address)) return
    const width = Math.max(1, Math.min(controller.snapshotWidth, capture.sourceSize.width))
    const height = Math.max(1, Math.round(width * frame.height / Math.max(1, frame.width)))
    const address = entry.address
    const target = controller
    frame.grabToImage(result => target.keepSnapshot(address, result), Qt.size(width, height))
  }

  x: geometry.x - width / 2
  y: geometry.y - height / 2
  width: fittedPreview.width + pad * 2
  height: fittedPreview.height + headerHeight + pad
  z: geometry.z
  opacity: inField ? geometry.opacity : 0
  visible: opacity > 0.01

  Behavior on opacity {
    enabled: card.controller !== null && card.controller.cameraAnimated
    NumberAnimation { duration: 160 }
  }

  onHasContentChanged: {
    if (!hasContent || !controller) return
    card.takeSnapshot()
  }


  RectangularShadow {
    anchors.fill: parent
    radius: card.radius
    blur: (card.selected ? 40 : 26) * card.unit
    spread: card.selected ? 3 * card.unit : 0
    offset: card.selected ? Qt.vector2d(0, 0) : Qt.vector2d(0, 8 * card.unit * card.depthScale)
    color: card.selected ? card.theme.glow : card.theme.shadow
  }

  Rectangle {
    objectName: "cardSurface"
    anchors.fill: parent
    radius: card.radius
    border.width: card.appearance.borderWidth
    border.color: card.hovered ? card.theme.cardBorderHover : card.theme.cardBorder
    gradient: Gradient {
      GradientStop { position: 0; color: card.selected ? card.theme.cardSelectedTop : card.theme.cardTop }
      GradientStop { position: 1; color: card.selected ? card.theme.cardSelectedBottom : card.theme.cardBottom }
    }
  }

  Item {
    id: header

    x: card.pad + 2 * card.unit
    width: card.width - x * 2
    height: card.headerHeight
    opacity: 1 - card.fog * 0.45

    AppIcon {
      id: headerIcon

      anchors.verticalCenter: parent.verticalCenter
      size: card.headerHeight * 0.6
      source: card.entry ? card.entry.icon : ""
      name: card.entry ? card.entry.appName : ""
    }

    Text {
      anchors.left: headerIcon.right
      anchors.leftMargin: 7 * card.unit
      anchors.right: headerAge.left
      anchors.rightMargin: 8 * card.unit
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      color: card.theme.text
      font.family: Commons.Style.font.family
      font.pixelSize: Math.max(10, Math.min(13 * card.textUnit, card.headerHeight * 0.46))
      font.bold: card.selected
      textFormat: Text.PlainText
      text: card.titleText || (card.entry ? card.entry.appName : "")
    }

    Text {
      id: headerAge

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      color: card.theme.textSoft
      font.family: Commons.Style.font.family
      font.pixelSize: Math.max(9, Math.min(11 * card.textUnit, card.headerHeight * 0.4))
      textFormat: Text.PlainText
      text: card.entry ? Field.ageShort(card.entry.seconds, card.entry.active, card.entry.estimated) : ""
    }
  }

  Item {
    id: preview

    x: card.pad
    y: card.headerHeight
    width: card.width - card.pad * 2
    height: card.height - card.headerHeight - card.pad

    ClippingRectangle {
      id: frame
      objectName: "previewFrame"

      anchors.fill: parent
      radius: Math.max(0, card.radius * 0.55)
      color: "transparent"

      Image {
        anchors.fill: parent
        visible: card.showsSnapshot
        source: card.snapshot ? card.snapshot.url : ""
        fillMode: Image.PreserveAspectCrop
        cache: false
        smooth: true
        mipmap: true
      }

      Column {
        anchors.centerIn: parent
        width: parent.width - 20 * card.unit
        spacing: 8 * card.unit
        visible: !capture.hasContent && !card.showsSnapshot

        AppIcon {
          anchors.horizontalCenter: parent.horizontalCenter
          size: Math.max(16, Math.min(88 * card.unit, frame.height * 0.3))
          source: card.entry ? card.entry.icon : ""
          name: card.entry ? card.entry.appName : ""
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          visible: frame.height > 110 * card.unit
          color: card.theme.textSoft
          font.family: Commons.Style.font.family
          font.pixelSize: Math.max(10, Math.min(13 * card.textUnit, frame.height * 0.05))
          textFormat: Text.PlainText
          text: card.entry ? card.entry.appName : ""
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          visible: card.parked && frame.height > 130 * card.unit
          color: card.theme.textFaint
          font.family: Commons.Style.font.family
          font.pixelSize: Math.max(9, Math.min(11 * card.textUnit, frame.height * 0.042))
          textFormat: Text.PlainText
          text: "off screen \u00b7 no live preview"
        }
      }

      ScreencopyView {
        id: capture

        anchors.fill: parent
        captureSource: card.capturing ? card.toplevel.wayland : null
        live: card.capturing
        paintCursor: false
      }
    }

    Rectangle {
      anchors.fill: frame
      radius: frame.radius
      color: card.theme.fog
      opacity: card.fog
      visible: opacity > 0.005
    }

    Rectangle {
      anchors.fill: frame
      radius: frame.radius
      color: "transparent"
      border.width: card.appearance.borderWidth
      border.color: card.theme.frameEdge
    }

    Rectangle {
      anchors.left: frame.left
      anchors.bottom: frame.bottom
      anchors.margins: 8 * card.unit * card.depthScale + 2
      visible: card.showsSnapshot && frame.height > 70 * card.unit
      width: badgeText.implicitWidth + 14 * card.unit
      height: badgeText.implicitHeight + 6 * card.unit
      radius: Math.min(card.appearance.cornerRadius, height / 2)
      color: card.theme.panel
      border.width: card.appearance.borderWidth
      border.color: card.theme.panelBorder

      Text {
        id: badgeText

        anchors.centerIn: parent
        color: card.theme.textSoft
        font.family: Commons.Style.font.family
        font.pixelSize: Math.max(9, 11 * card.textUnit * Math.max(0.8, card.depthScale))
        textFormat: Text.PlainText
        text: {
          const snapshot = card.snapshot
          if (!snapshot || !card.controller) return ""
          const seconds = Math.max(0, (card.controller.openedAtMs - snapshot.takenAt) / 1000)
          return "last seen " + Field.ageLabel(seconds, false, false)
        }
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    objectName: "selectionOutline"
    anchors.margins: card.selected ? -3 * card.unit : 0
    radius: card.selected && card.radius > 0 ? card.radius + 3 * card.unit : card.radius
    color: "transparent"
    visible: card.selected || card.urgent
    border.width: card.selected ? Math.max(card.appearance.borderWidth + 1, 2.5 * card.unit)
      : Math.max(card.appearance.borderWidth, 1.5)
    border.color: card.selected ? card.theme.accent : card.theme.urgent
  }

  Rectangle {
    visible: card.urgent
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: -5 * card.unit
    width: 12 * card.unit
    height: width
    radius: width / 2
    color: card.theme.urgent
    border.width: 2
    border.color: card.theme.background
  }

  MouseArea {
    id: mouse

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: if (card.controller) card.controller.selectAndCommit(card.index)
  }
}
