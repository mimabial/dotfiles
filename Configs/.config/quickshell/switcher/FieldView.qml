pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons as Commons
import qs as Active
import "Layout.js" as Layout
import "Field.js" as Field
import "Focus.js" as Focus
import "Palette.js" as Palette

Item {
  id: fieldView

  required property var controller
  readonly property string wallpaperPath: controller ? controller.shell.wallpaper.selectedWallpaper : ""
  property url wallpaperUrl: wallpaperPath ? "file://" + wallpaperPath.split("/").map(encodeURIComponent).join("/") : ""
  readonly property alias wallpaperImage: wallpaperImage
  readonly property int planeCount: planes.count
  readonly property alias map: map
  readonly property alias gauge: gauge
  readonly property var theme: Palette.derive({
    foreground: Commons.Color.foreground, background: Commons.Color.background, accent: Commons.Color.accent, urgent: Commons.Color.urgent,
    surfaceOpacity: Commons.Style.popupSurfaceOpacity
  })
  readonly property Appearance appearance: Appearance {}

  readonly property real unit: Math.max(0.75, Math.min(1.6, height / 1000))
  readonly property real textUnit: unit * Math.max(0.85, Math.min(1.6, Active.Style.uiScale))
  readonly property real margin: Math.max(16, width * 0.022)
  readonly property var entry: controller ? controller.selectedEntry : null
  readonly property bool holding: controller !== null && controller.mode === "hold"
  readonly property bool filtering: controller !== null && controller.filterText.length > 0
  readonly property bool nothingShown: controller !== null && controller.opened && controller.order.length === 0

  function planeAt(index) {
    return planes.itemAt(index)
  }

  function focusKeys() {
    keyCatcher.forceActiveFocus()
  }

  property bool pointerPrimed: false
  property point pointerAt: Qt.point(0, 0)

  function pointerMoved(item, x, y) {
    const point = item.mapToItem(fieldView, x, y)
    if (!fieldView.pointerPrimed) {
      fieldView.pointerPrimed = true
      fieldView.pointerAt = point
      return false
    }
    if (Math.abs(point.x - fieldView.pointerAt.x) < 3 && Math.abs(point.y - fieldView.pointerAt.y) < 3) return false
    fieldView.pointerAt = point
    return true
  }

  Connections {
    target: fieldView.controller
    function onOpenedChanged() {
      fieldView.pointerPrimed = false
    }
  }

  Image {
    id: wallpaperImage
    anchors.fill: parent
    source: fieldView.wallpaperUrl
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: width
    sourceSize.height: height
    opacity: status === Image.Ready ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
      NumberAnimation { duration: fieldView.appearance.fadeDuration; easing.type: Easing.OutCubic }
    }
  }

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: fieldView.theme.veilTop }
      GradientStop { position: 0.55; color: fieldView.theme.veilMiddle }
      GradientStop { position: 1.0; color: fieldView.theme.veilBottom }
    }
  }

  Rectangle {
    anchors.left: parent.left
    anchors.right: parent.right
    height: parent.height * 0.45
    opacity: 1 - fieldView.sceneDepth / 8
    gradient: Gradient {
      GradientStop { position: 0.0; color: fieldView.theme.surfaceLight }
      GradientStop { position: 1.0; color: fieldView.theme.surfaceLightEnd }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: fieldView.theme.depthShade
    opacity: fieldView.sceneDepth * 0.035
    visible: opacity > 0.005
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: if (fieldView.controller) fieldView.controller.cancel()
    onPositionChanged: mouse => fieldView.pointerMoved(fieldView, mouse.x, mouse.y)
  }

  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: event => {
      if (fieldView.controller)
        fieldView.controller.wheel(event.angleDelta.y, event.pixelDelta.y, event.angleDelta.x, event.pixelDelta.x)
    }
  }

  readonly property real mapHeight: Math.max(96, Math.min(height * 0.2, 210 * unit))
  readonly property real captionHeight: 62 * unit
  readonly property real deepTop: margin + 44 * unit
  readonly property real gaugeWidth: width >= 1000 ? 112 * textUnit : 0
  readonly property var stage: Layout.deepStage(width, height, deepTop,
    mapHeight + captionHeight + margin + 30 * unit, width / Math.max(1, height), margin + gaugeWidth)

  readonly property real selectedDepth: entry ? Math.min(8, Math.max(0, entry.depth)) : 0
  property real sceneDepth: selectedDepth

  Behavior on sceneDepth {
    enabled: fieldView.controller !== null && fieldView.controller.cameraAnimated
    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
  }

  Item {
    id: deep

    anchors.fill: parent

    Repeater {
      id: planes

      model: fieldView.controller ? fieldView.controller.field : []

      delegate: WindowPlane {
        controller: fieldView.controller
        theme: fieldView.theme
        appearance: fieldView.appearance
        stage: fieldView.stage
        unit: fieldView.unit
        textUnit: fieldView.textUnit
      }
    }
  }

  SoundingLine {
    id: gauge

    x: fieldView.margin
    y: fieldView.deepTop
    width: fieldView.gaugeWidth
    height: fieldView.stage.frontY + fieldView.stage.frontHeight / 2 - fieldView.deepTop
    visible: fieldView.gaugeWidth > 0
    controller: fieldView.controller
    theme: fieldView.theme
    unit: fieldView.unit
    textUnit: fieldView.textUnit
    leadDepth: fieldView.sceneDepth
  }

  Item {
    id: caption

    x: fieldView.stage.frontX - fieldView.stage.frontWidth / 2
    y: fieldView.height - fieldView.margin - fieldView.mapHeight - fieldView.captionHeight - 14 * fieldView.unit
    width: fieldView.width - x - fieldView.margin
    height: fieldView.captionHeight
    visible: fieldView.entry !== null

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: if (fieldView.controller && fieldView.controller.selectedEntry) fieldView.controller.commit()
    }

    AppIcon {
      id: captionIcon

      anchors.verticalCenter: parent.verticalCenter
      size: 38 * fieldView.unit
      source: fieldView.entry ? fieldView.entry.icon : ""
      name: fieldView.entry ? fieldView.entry.appName : ""
    }

    Column {
      anchors.left: captionIcon.right
      anchors.leftMargin: 14 * fieldView.unit
      anchors.right: counter.left
      anchors.rightMargin: 20 * fieldView.unit
      anchors.verticalCenter: parent.verticalCenter
      spacing: 3 * fieldView.unit

      Text {
        width: parent.width
        elide: Text.ElideRight
        color: fieldView.theme.text
        font.family: Commons.Style.font.family
        font.pixelSize: 20 * fieldView.textUnit
        font.bold: true
        textFormat: Text.PlainText
        text: {
          const toplevel = fieldView.entry ? fieldView.entry.toplevel : null
          return toplevel && toplevel.title ? String(toplevel.title) : (fieldView.entry ? (fieldView.entry.title || fieldView.entry.appName) : "")
        }
      }

      Text {
        width: parent.width
        elide: Text.ElideRight
        color: fieldView.theme.textSoft
        font.family: Commons.Style.font.family
        font.pixelSize: 13 * fieldView.textUnit
        textFormat: Text.PlainText
        text: {
          const entry = fieldView.entry
          if (!entry) return ""
          const parts = []
          if (entry.appName) parts.push(entry.appName)
          const workspace = Field.workspaceLabel(entry.workspaceName, entry.workspaceId)
          parts.push(Field.isSpecialName(entry.workspaceName) ? "scratchpad " + workspace : "workspace " + workspace)
          const tab = Focus.groupIndexFor(entry.address, entry.grouped)
          if (tab > 0 && entry.grouped.length > 1) parts.push("tab " + tab + " of " + entry.grouped.length)
          parts.push(Field.ageLabel(entry.seconds, entry.active, entry.estimated))
          const reading = Field.fathomLabel(entry.depth, entry.active, entry.estimated)
          if (reading) parts.push(reading)
          if (entry.toplevel && entry.toplevel.urgent) parts.push("wants attention")
          return parts.join("  ·  ")
        }
      }
    }

    Text {
      id: counter
      objectName: "counter"

      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      color: fieldView.theme.textSoft
      font.family: Commons.Style.font.family
      font.pixelSize: 13 * fieldView.textUnit
      textFormat: Text.PlainText
      text: fieldView.controller && fieldView.controller.selectedSlot >= 0
        ? (fieldView.controller.selectedSlot + 1) + " / " + fieldView.controller.order.length : ""
    }
  }

  Text {
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -fieldView.mapHeight / 2
    visible: fieldView.nothingShown
    color: fieldView.theme.text
    font.family: Commons.Style.font.family
    font.pixelSize: 20 * fieldView.textUnit
    textFormat: Text.PlainText
    text: "No window matches “" + (fieldView.controller ? fieldView.controller.filterText : "") + "”"
  }

  Text {
    objectName: "summary"

    x: fieldView.margin
    y: fieldView.margin + 8 * fieldView.unit
    visible: !filterBar.visible && fieldView.controller !== null
    color: fieldView.theme.textSoft
    font.family: Commons.Style.font.family
    font.pixelSize: 13 * fieldView.textUnit
    textFormat: Text.PlainText
    text: {
      const controller = fieldView.controller
      if (!controller) return ""
      const windows = controller.order.length
      const workspaces = controller.groups.filter(group => group.entries.some(index => controller.slots[index] >= 0)).length
      return windows + (windows === 1 ? " window" : " windows") + "  \u00b7  "
        + workspaces + (workspaces === 1 ? " workspace" : " workspaces")
    }
  }

  Rectangle {
    id: filterBar
    objectName: "filterBar"

    x: fieldView.margin
    y: fieldView.margin
    height: 34 * fieldView.unit
    width: filterRow.implicitWidth + 28 * fieldView.unit
    radius: Math.min(fieldView.appearance.cornerRadius, height / 2)
    color: fieldView.theme.panel
    border.width: fieldView.appearance.borderWidth
    border.color: fieldView.filtering ? fieldView.theme.accent : fieldView.theme.panelBorder
    visible: fieldView.filtering

    MouseArea {
      anchors.fill: parent
      onClicked: fieldView.focusKeys()
    }

    Row {
      id: filterRow

      anchors.verticalCenter: parent.verticalCenter
      x: 14 * fieldView.unit
      spacing: 8 * fieldView.unit

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: fieldView.filtering ? fieldView.theme.accentText : fieldView.theme.textFaint
        font.family: Commons.Style.font.family
        font.pixelSize: 14 * fieldView.textUnit
        textFormat: Text.PlainText
        text: "/"
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        color: fieldView.filtering ? fieldView.theme.text : fieldView.theme.textFaint
        font.family: Commons.Style.font.family
        font.pixelSize: 14 * fieldView.textUnit
        textFormat: Text.PlainText
        text: fieldView.controller ? fieldView.controller.filterText : ""
      }

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        visible: fieldView.filtering
        width: 2
        height: 16 * fieldView.unit
        color: fieldView.theme.accent
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: fieldView.filtering
        color: fieldView.theme.textSoft
        font.family: Commons.Style.font.family
        font.pixelSize: 12 * fieldView.textUnit
        textFormat: Text.PlainText
        text: fieldView.controller ? fieldView.controller.order.length + " of " + fieldView.controller.field.length : ""
      }
    }
  }

  Text {
    id: hints

    readonly property string hint: {
      if (fieldView.nothingShown) return "Backspace Edit  Esc Clear"
      const holding = fieldView.holding
      const filtering = fieldView.filtering
      return [
        holding ? "Tab Deeper" : "", "↑↓ Dive", "←→ Workspace",
        filtering ? "Backspace Edit" : "Type Filter",
        filtering ? "" : holding ? "Space Keep Open" : "1–9 Go To",
        holding ? "" : "Enter Focus",
        "Del Close Window",
        "Esc " + (filtering ? "Clear" : holding ? "Cancel" : "Close")
      ].filter(Boolean).join("  ")
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Math.max(0, (fieldView.margin - height) / 2)
    color: fieldView.theme.accentText
    font.family: Commons.Style.font.family
    font.pixelSize: Commons.Style.font.bodySmall
    textFormat: Text.StyledText
    text: Commons.Util.keyHintMarkup(hints.hint, fieldView.theme.textSoft)

    MouseArea {
      anchors.fill: parent
      onClicked: fieldView.focusKeys()
    }
  }

  WorkspaceMap {
    id: map

    x: fieldView.margin
    width: fieldView.width - fieldView.margin * 2
    height: fieldView.mapHeight
    y: fieldView.height - fieldView.margin - height
    controller: fieldView.controller
    view: fieldView
    theme: fieldView.theme
    appearance: fieldView.appearance
    unit: fieldView.unit
    textUnit: fieldView.textUnit
  }

  Item {
    id: keyCatcher

    anchors.fill: parent
    focus: true

    Keys.onPressed: event => {
      if (!fieldView.controller) return
      event.accepted = fieldView.controller.handleKey(event.key, event.modifiers, event.text, event.isAutoRepeat)
    }

    Keys.onReleased: event => {
      if (event.key === Qt.Key_Alt && !event.isAutoRepeat && fieldView.controller) {
        fieldView.controller.altReleased()
        event.accepted = true
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    z: 10000
    visible: fieldView.controller !== null && fieldView.controller.opened && !fieldView.controller.revealed
    acceptedButtons: Qt.AllButtons
    onWheel: wheel => wheel.accepted = true
  }

}
