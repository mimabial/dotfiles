import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "DockModel.js" as DockModel

BorderSurface {
  id: contextMenu
  required property var dock
  readonly property bool hovered: menuHover.hovered
  property alias selectedWindowIdx: appContextMenuColumn.selectedWindowIdx

  component ContextRow: DockMenuRow { menuWidth: contextMenu.rowWidth }
  component MenuDivider: DockMenuDivider { menuWidth: contextMenu.rowWidth }
  visible: contextMenu.dock.contextAppId !== ""
  z: 100
  color: Util.alpha(Color.menu.background, contextMenu.dock.dockSurfaceOpacity)
  borderSpec: Border.surfaceSpec("menu", "border",
    Util.alpha(Color.menu.border, Style.popupBorderOpacity), 1)
  radius: Style.cornerRadius
  padding: Style.space(4)

  HoverHandler { id: menuHover }

  readonly property real rowWidth: contextMenu.dock.contextAppId !== ""
    ? contextMenu.dock.menuContentWidth(menuColumn)
    : 0

  width: contextMenu.dock.contextAppId !== ""
    ? rowWidth + contentLeftInset + contentRightInset
    : 0
  height: contextMenu.dock.contextAppId !== ""
    ? menuColumn.implicitHeight + contentTopInset + contentBottomInset
    : 0

  x: contextMenu.dock.vertical ? contextMenu.dock.panelCross(width) : contextMenu.dock.panelMain(width, contextMenu.dock.contextAnchor)
  y: contextMenu.dock.vertical ? contextMenu.dock.panelMain(height, contextMenu.dock.contextAnchor) : contextMenu.dock.panelCross(height)

  Column {
    id: menuColumn
    spacing: Style.space(2)

    anchors.left: parent.left
    anchors.leftMargin: contextMenu.contentLeftInset
    anchors.right: parent.right
    anchors.rightMargin: contextMenu.contentRightInset
    anchors.top: parent.top
    anchors.topMargin: contextMenu.contentTopInset
    anchors.bottom: parent.bottom
    anchors.bottomMargin: contextMenu.contentBottomInset

    Column {
      spacing: Style.space(1)
      visible: contextMenu.dock.contextAppId === "__dock_settings__"

      Column {
        spacing: Style.space(2)
        visible: contextMenu.dock.settingsSubmenu === ""

        ContextRow {
          text: "Dock Settings"
          isHeader: true
        }

        ContextRow {
          text: "Appearance ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "appearance"
        }

        ContextRow {
          text: "Behavior & Windows ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "behavior"
        }

        ContextRow {
          text: "Effects & Animations ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "effects"
        }

        ContextRow {
          text: "Size & Spacing ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "size_spacing"
        }

        ContextRow {
          text: "Folders & Stacks ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "folders"
        }

        ContextRow {
          text: "App Groups ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "app_groups"
        }

        ContextRow {
          text: "Position: " + contextMenu.dock.edgeLabel(contextMenu.dock.edge) + (contextMenu.dock.linkToBar ? " (linked)" : "") + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "position"
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "app_groups"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = ""
        }
        ContextRow { text: "App Groups"; isHeader: true }
        ContextRow {
          text: "+ Group Running Apps"
          textColor: Color.bar.active
          onTriggered: {
            contextMenu.dock.createAppGroupFromRunning()
            contextMenu.dock.closeContext()
          }
        }
        MenuDivider { visible: contextMenu.dock.appGroups.length > 0 }
        Repeater {
          model: contextMenu.dock.appGroups.map(function(group) {
            return { group: group, dock: contextMenu.dock }
          })
          delegate: ContextRow {
            required property var modelData
            text: "Ungroup " + String(modelData.group.name || "Applications")
            danger: true
            onTriggered: modelData.dock.ungroupAppGroup(modelData.group.id)
          }
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "folders"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = ""
        }

        ContextRow {
          text: "Folder Color: " + contextMenu.dock.folderColorLabel(contextMenu.dock.folderColor) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "folder_color"
        }

        MenuDivider {}

        ContextRow {
          text: "Pinned Folder Stacks"
          isHeader: true
        }

        ContextRow {
          text: "+ Add Custom Folder..."
          textColor: Color.bar.active
          onTriggered: {
            customFolderPickerProc.running = true
            contextMenu.dock.closeContext()
          }
        }

        MenuDivider {}

        ContextRow {
          text: "Downloads (~/Downloads)"
          checked: contextMenu.dock.isFolderPinned("~/Downloads")
          onTriggered: contextMenu.dock.toggleFolderPin("~/Downloads", "Downloads", "folder-download")
        }

        ContextRow {
          text: "Documents (~/Documents)"
          checked: contextMenu.dock.isFolderPinned("~/Documents")
          onTriggered: contextMenu.dock.toggleFolderPin("~/Documents", "Documents", "folder-documents")
        }

        ContextRow {
          text: "Pictures (~/Pictures)"
          checked: contextMenu.dock.isFolderPinned("~/Pictures")
          onTriggered: contextMenu.dock.toggleFolderPin("~/Pictures", "Pictures", "folder-pictures")
        }

        ContextRow {
          text: "Projects (~/Projects)"
          checked: contextMenu.dock.isFolderPinned("~/Projects")
          onTriggered: contextMenu.dock.toggleFolderPin("~/Projects", "Projects", "folder-development")
        }

        ContextRow {
          text: "Music (~/Music)"
          checked: contextMenu.dock.isFolderPinned("~/Music")
          onTriggered: contextMenu.dock.toggleFolderPin("~/Music", "Music", "folder-music")
        }

        ContextRow {
          text: "Videos (~/Videos)"
          checked: contextMenu.dock.isFolderPinned("~/Videos")
          onTriggered: contextMenu.dock.toggleFolderPin("~/Videos", "Videos", "folder-videos")
        }

        ContextRow {
          text: "Home (~/)"
          checked: contextMenu.dock.isFolderPinned("~")
          onTriggered: contextMenu.dock.toggleFolderPin("~", "Home", "user-home")
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "folder_color"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "folders"
        }

        ContextRow {
          text: "Folder Color & Style"
          isHeader: true
        }

        ContextRow {
          text: "Auto (Match Theme)"
          checked: contextMenu.dock.folderColor === "theme" || !contextMenu.dock.folderColor
          onTriggered: contextMenu.dock.setFolderColor("theme")
        }

        MenuDivider {}

        ContextRow {
          text: "Symbolic (Theme Foreground)"
          checked: contextMenu.dock.folderColor === "symbolic"
          onTriggered: contextMenu.dock.setFolderColor("symbolic")
        }

        MenuDivider {}

        ContextRow {
          text: "Color Presets"
          isHeader: true
        }

        Item {
          readonly property bool isMenuContent: true
          implicitWidth: Math.max(220, 2 * Style.space(24) + Style.space(4) + Style.space(16))
          implicitHeight: Style.space(24) + Style.space(8)
          width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth
          height: implicitHeight

          Grid {
            anchors.centerIn: parent
            columns: 2
            spacing: Style.space(4)

            readonly property var colorPresets: [
              { id: "white", name: "White", color: "#ffffff" },
              { id: "black", name: "Black", color: "#111111" }
            ]

            Repeater {
              model: parent.colorPresets
              delegate: Rectangle {
                id: fColorSwatch
                required property var modelData
                width: Style.space(24)
                height: Style.space(24)
                radius: Style.space(4)
                color: modelData.color
                border.color: contextMenu.dock.folderColor === modelData.id
                  ? Color.bar.active
                  : Util.alpha(Color.menu.border, 0.8)
                border.width: contextMenu.dock.folderColor === modelData.id ? 2 : 1

                Rectangle {
                  visible: contextMenu.dock.folderColor === fColorSwatch.modelData.id
                  anchors.centerIn: parent
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: Style.space(4)
                  color: fColorSwatch.modelData.id === "white" ? "#111111" : "#ffffff"
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: contextMenu.dock.setFolderColor(fColorSwatch.modelData.id)
                }
              }
            }
          }
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "position"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = ""
        }

        ContextRow {
          text: "Dock Position"
          isHeader: true
        }

        ContextRow {
          text: "Opposite the Bar"
          checked: contextMenu.dock.linkToBar
          onTriggered: contextMenu.dock.setLinkToBar(!contextMenu.dock.linkToBar)
        }

        MenuDivider {}

        ContextRow {
          text: "Bottom"
          checked: !contextMenu.dock.linkToBar && contextMenu.dock.dockEdge === "bottom"
          onTriggered: contextMenu.dock.setDockEdge("bottom")
        }

        ContextRow {
          text: "Top"
          checked: !contextMenu.dock.linkToBar && contextMenu.dock.dockEdge === "top"
          onTriggered: contextMenu.dock.setDockEdge("top")
        }

        ContextRow {
          text: "Left"
          checked: !contextMenu.dock.linkToBar && contextMenu.dock.dockEdge === "left"
          onTriggered: contextMenu.dock.setDockEdge("left")
        }

        ContextRow {
          text: "Right"
          checked: !contextMenu.dock.linkToBar && contextMenu.dock.dockEdge === "right"
          onTriggered: contextMenu.dock.setDockEdge("right")
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "appearance"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = ""
        }

        ContextRow {
          text: "Appearance"
          isHeader: true
        }

        ContextRow {
          text: "Shape: " + (contextMenu.dock.dockShape === "theme" || contextMenu.dock.dockShape === "auto" ? "Auto (Theme)" : (contextMenu.dock.dockShape === "round" || contextMenu.dock.dockShape === "pill" ? "Round" : (contextMenu.dock.dockShape === "square" ? "Square" : "Rounded"))) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "shape"
        }

        ContextRow {
          text: "Opacity: " + (contextMenu.dock.dockOpacity < 0 ? "Auto (Theme)" : (contextMenu.dock.dockOpacity >= 0.95 ? "Opaque" : (contextMenu.dock.dockOpacity >= 0.75 ? "Glass" : (contextMenu.dock.dockOpacity >= 0.55 ? "Frosted Glass" : (contextMenu.dock.dockOpacity >= 0.20 ? "Translucent" : "Transparent"))))) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "opacity"
        }

        ContextRow {
          text: "Color: " + (contextMenu.dock.dockBgColor === "theme" || !contextMenu.dock.dockBgColor ? "Theme" : (contextMenu.dock.dockBgColor === "none" ? "No Color" : "Custom")) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "color"
        }

        MenuDivider {}

        ContextRow {
          text: contextMenu.dock.linked ? "Transparent (with bar)" : "Transparent"
          checked: contextMenu.dock.transparent
          onTriggered: contextMenu.dock.setTransparent(!contextMenu.dock.transparent)
        }

        ContextRow {
          text: contextMenu.dock.linked ? "Blur (with bar)" : "Blur"
          checked: contextMenu.dock.blurred
          onTriggered: contextMenu.dock.setBlur(!contextMenu.dock.blurred)
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "behavior"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = ""
        }

        ContextRow {
          text: "Behavior & Windows"
          isHeader: true
        }

        ContextRow {
          text: "Autohide: " + (contextMenu.dock.autohide ? (contextMenu.dock.intelligentAutohide ? "Intelligent" : "Auto Hide") : "Always Show") + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "autohide"
        }

        ContextRow {
          text: "Minimize On Click: " + (contextMenu.dock.minimizeMode === "all" ? "All Windows" : (contextMenu.dock.minimizeMode === "active" ? "Active Window" : "Disabled")) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "minimize"
        }

        ContextRow {
          text: "Urgent Highlights"
          checked: contextMenu.dock.showUrgentHint
          onTriggered: {
            contextMenu.dock.showUrgentHint = !contextMenu.dock.showUrgentHint
            contextMenu.dock.saveConfig()
          }
        }

        ContextRow {
          text: "Urgent Sound: " + (contextMenu.dock.urgentSoundName === "message-new-instant" ? "Message" : (contextMenu.dock.urgentSoundName === "complete" ? "Complete" : (contextMenu.dock.urgentSoundName === "dialog-information" ? "Information" : (contextMenu.dock.urgentSoundName === "dialog-warning" ? "Warning" : (contextMenu.dock.urgentSoundName === "phone-incoming-call" ? "Phone" : (contextMenu.dock.urgentSoundName === "alarm-clock-elapsed" ? "Alarm" : (contextMenu.dock.urgentSoundName === "none" ? "Mute" : "Bell"))))))) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "urgent_sound"
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "effects"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = ""
        }

        ContextRow {
          text: "Effects & Animations"
          isHeader: true
        }

        ContextRow {
          text: "Hover: " + (contextMenu.dock.hoverEffect === "wave" ? "Wave" : (contextMenu.dock.hoverEffect === "off" ? "None" : "Zoom")) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "hover"
        }

        ContextRow {
          text: "Launch Bounce"
          checked: contextMenu.dock.launchBounce
          onTriggered: {
            contextMenu.dock.launchBounce = !contextMenu.dock.launchBounce
            contextMenu.dock.saveConfig()
          }
        }

        ContextRow {
          text: "Window Previews"
          checked: contextMenu.dock.advancedTooltips
          onTriggered: {
            contextMenu.dock.advancedTooltips = !contextMenu.dock.advancedTooltips
            contextMenu.dock.saveConfig()
          }
        }

        ContextRow {
          text: "Show Tooltips"
          checked: contextMenu.dock.showTooltips
          onTriggered: {
            contextMenu.dock.showTooltips = !contextMenu.dock.showTooltips
            contextMenu.dock.saveConfig()
          }
        }

        ContextRow {
          text: "Minimized Window Previews"
          checked: contextMenu.dock.showMinimizedTiles
          onTriggered: {
            contextMenu.dock.showMinimizedTiles = !contextMenu.dock.showMinimizedTiles
            contextMenu.dock.saveConfig()
          }
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "hover"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "effects"
        }

        ContextRow {
          text: "Hover Effect"
          isHeader: true
        }

        ContextRow {
          text: "Zoom"
          checked: contextMenu.dock.hoverEffect !== "wave" && contextMenu.dock.hoverEffect !== "off"
          onTriggered: contextMenu.dock.setHoverEffect("zoom")
        }

        ContextRow {
          text: "Wave"
          checked: contextMenu.dock.hoverEffect === "wave"
          onTriggered: contextMenu.dock.setHoverEffect("wave")
        }

        ContextRow {
          text: "None"
          checked: contextMenu.dock.hoverEffect === "off"
          onTriggered: contextMenu.dock.setHoverEffect("off")
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "size_spacing"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = ""
        }

        ContextRow {
          text: "Size & Spacing"
          isHeader: true
        }

        ContextRow {
          text: "Icon Size: " + contextMenu.dock.iconSize + "px ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "size"
        }

        ContextRow {
          text: "Spacing: " + (contextMenu.dock.itemSpacing <= 2 ? "Compact" : (contextMenu.dock.itemSpacing <= 5 ? "Normal" : "Relaxed")) + " ›"
          onTriggered: contextMenu.dock.settingsSubmenu = "spacing"
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "autohide"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "behavior"
        }

        ContextRow {
          text: "Autohide Mode"
          isHeader: true
        }

        ContextRow {
          text: "Always Show"
          checked: !contextMenu.dock.autohide
          onTriggered: contextMenu.dock.setAutohideMode("always")
        }

        ContextRow {
          text: "Intelligent Autohide"
          checked: contextMenu.dock.autohide && contextMenu.dock.intelligentAutohide
          onTriggered: contextMenu.dock.setAutohideMode("intelligent")
        }

        ContextRow {
          text: "Auto Hide"
          checked: contextMenu.dock.autohide && !contextMenu.dock.intelligentAutohide
          onTriggered: contextMenu.dock.setAutohideMode("autohide")
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "minimize"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "behavior"
        }

        ContextRow {
          text: "Minimize On Click"
          isHeader: true
        }

        ContextRow {
          text: "Disabled"
          checked: contextMenu.dock.minimizeMode === "off"
          onTriggered: {
            contextMenu.dock.minimizeMode = "off"
            contextMenu.dock.saveConfig()
          }
        }

        ContextRow {
          text: "Active Window (Most Recent)"
          checked: contextMenu.dock.minimizeMode === "active"
          onTriggered: {
            contextMenu.dock.minimizeMode = "active"
            contextMenu.dock.saveConfig()
          }
        }

        ContextRow {
          text: "All Windows of App"
          checked: contextMenu.dock.minimizeMode === "all"
          onTriggered: {
            contextMenu.dock.minimizeMode = "all"
            contextMenu.dock.saveConfig()
          }
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "urgent_sound"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "behavior"
        }

        ContextRow {
          text: "Urgent Sound Alert"
          isHeader: true
        }

        ContextRow {
          text: "Bell (Default)"
          checked: contextMenu.dock.urgentSoundName === "bell"
          onTriggered: contextMenu.dock.setUrgentSoundName("bell")
        }

        ContextRow {
          text: "Message Chime"
          checked: contextMenu.dock.urgentSoundName === "message-new-instant"
          onTriggered: contextMenu.dock.setUrgentSoundName("message-new-instant")
        }

        ContextRow {
          text: "Complete Ding"
          checked: contextMenu.dock.urgentSoundName === "complete"
          onTriggered: contextMenu.dock.setUrgentSoundName("complete")
        }

        ContextRow {
          text: "Information Pop"
          checked: contextMenu.dock.urgentSoundName === "dialog-information"
          onTriggered: contextMenu.dock.setUrgentSoundName("dialog-information")
        }

        ContextRow {
          text: "Warning Alert"
          checked: contextMenu.dock.urgentSoundName === "dialog-warning"
          onTriggered: contextMenu.dock.setUrgentSoundName("dialog-warning")
        }

        ContextRow {
          text: "Phone Ring"
          checked: contextMenu.dock.urgentSoundName === "phone-incoming-call"
          onTriggered: contextMenu.dock.setUrgentSoundName("phone-incoming-call")
        }

        ContextRow {
          text: "Alarm Beeps"
          checked: contextMenu.dock.urgentSoundName === "alarm-clock-elapsed"
          onTriggered: contextMenu.dock.setUrgentSoundName("alarm-clock-elapsed")
        }

        ContextRow {
          text: "Mute / Silent"
          checked: contextMenu.dock.urgentSoundName === "none"
          onTriggered: contextMenu.dock.setUrgentSoundName("none")
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "shape"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "appearance"
        }

        ContextRow {
          text: "Dock Shape"
          isHeader: true
        }

        ContextRow {
          text: "Auto (Theme)"
          checked: contextMenu.dock.dockShape === "theme" || contextMenu.dock.dockShape === "auto"
          onTriggered: contextMenu.dock.setDockShape("theme")
        }

        ContextRow {
          text: "Rounded"
          checked: contextMenu.dock.dockShape === "rounded"
          onTriggered: contextMenu.dock.setDockShape("rounded")
        }

        ContextRow {
          text: "Round (Pill)"
          checked: contextMenu.dock.dockShape === "round" || contextMenu.dock.dockShape === "pill"
          onTriggered: contextMenu.dock.setDockShape("round")
        }

        ContextRow {
          text: "Square"
          checked: contextMenu.dock.dockShape === "square"
          onTriggered: contextMenu.dock.setDockShape("square")
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "color"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "appearance"
        }

        ContextRow {
          text: "Background Color"
          isHeader: true
        }

        ContextRow {
          text: "Theme (Default)"
          checked: contextMenu.dock.dockBgColor === "theme" || !contextMenu.dock.dockBgColor
          onTriggered: contextMenu.dock.setDockBgColor("theme")
        }

        ContextRow {
          text: "No Color"
          checked: contextMenu.dock.dockBgColor === "none"
          onTriggered: contextMenu.dock.setDockBgColor("none")
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Util.alpha(Color.menu.border, 0.4)
        }

        ContextRow {
          text: "Presets"
          isHeader: true
        }

        Item {
          readonly property bool isMenuContent: true
          implicitWidth: Math.max(220, 5 * Style.space(24) + 4 * Style.space(4) + Style.space(16))
          implicitHeight: 2 * Style.space(24) + Style.space(4) + Style.space(8)
          width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth
          height: implicitHeight

          Grid {
            id: swatchGrid
            anchors.centerIn: parent
            columns: 5
            spacing: Style.space(4)

            readonly property var presetColors: [
              "#000000", "#181825", "#1e1e2e", "#0f172a", "#111827",
              "#062e24", "#1c1917", "#2c0b16", "#1e102d", "#334155"
            ]

            Repeater {
              model: parent.presetColors
              delegate: Rectangle {
                id: swatchRect
                required property string modelData
                width: Style.space(24)
                height: Style.space(24)
                radius: Style.space(4)
                color: modelData
                border.color: contextMenu.dock.dockBgColor === modelData
                  ? Color.bar.active
                  : Util.alpha(Color.menu.border, 0.8)
                border.width: contextMenu.dock.dockBgColor === modelData ? 2 : 1

                Rectangle {
                  visible: contextMenu.dock.dockBgColor === swatchRect.modelData
                  anchors.centerIn: parent
                  width: Style.space(8)
                  height: Style.space(8)
                  radius: Style.space(4)
                  color: Color.bar.active
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: contextMenu.dock.setDockBgColor(swatchRect.modelData)
                }
              }
            }
          }
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "opacity"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "appearance"
        }

        ContextRow {
          text: "Background Opacity"
          isHeader: true
        }

        ContextRow {
          text: "Auto (Theme)"
          checked: contextMenu.dock.dockOpacity < 0
          onTriggered: contextMenu.dock.setDockOpacity(-1.0)
        }

        ContextRow {
          text: "Opaque (100%)"
          checked: contextMenu.dock.dockOpacity >= 0.95
          onTriggered: contextMenu.dock.setDockOpacity(1.0)
        }

        ContextRow {
          text: "Glass (80%)"
          checked: contextMenu.dock.dockOpacity >= 0.75 && contextMenu.dock.dockOpacity < 0.95
          onTriggered: contextMenu.dock.setDockOpacity(0.80)
        }

        ContextRow {
          text: "Frosted Glass (65%)"
          checked: contextMenu.dock.dockOpacity >= 0.55 && contextMenu.dock.dockOpacity < 0.75
          onTriggered: contextMenu.dock.setDockOpacity(0.65)
        }

        ContextRow {
          text: "Translucent (35%)"
          checked: contextMenu.dock.dockOpacity >= 0.20 && contextMenu.dock.dockOpacity < 0.55
          onTriggered: contextMenu.dock.setDockOpacity(0.35)
        }

        ContextRow {
          text: "Transparent (0%)"
          checked: contextMenu.dock.dockOpacity >= 0.0 && contextMenu.dock.dockOpacity < 0.20
          onTriggered: contextMenu.dock.setDockOpacity(0.0)
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "size"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "size_spacing"
        }

        ContextRow {
          text: "Icon Size"
          isHeader: true
        }

        ContextRow {
          text: "Small (28px)"
          checked: contextMenu.dock.configuredIconSize === 28
          onTriggered: contextMenu.dock.setIconSize(28)
        }

        ContextRow {
          text: "Medium (36px)"
          checked: contextMenu.dock.configuredIconSize === 36 || (contextMenu.dock.configuredIconSize === 0 && contextMenu.dock.iconSize === 36)
          onTriggered: contextMenu.dock.setIconSize(36)
        }

        ContextRow {
          text: "Large (44px)"
          checked: contextMenu.dock.configuredIconSize === 44
          onTriggered: contextMenu.dock.setIconSize(44)
        }

        ContextRow {
          text: "Extra Large (52px)"
          checked: contextMenu.dock.configuredIconSize === 52
          onTriggered: contextMenu.dock.setIconSize(52)
        }
      }

      Column {
        spacing: Style.space(1)
        visible: contextMenu.dock.settingsSubmenu === "spacing"

        ContextRow {
          text: "‹ Back"
          textColor: Color.bar.active
          onTriggered: contextMenu.dock.settingsSubmenu = "size_spacing"
        }

        ContextRow {
          text: "Icon Spacing"
          isHeader: true
        }

        ContextRow {
          text: "Compact (2px)"
          checked: contextMenu.dock.itemSpacing === 2
          onTriggered: contextMenu.dock.setItemSpacing(2)
        }

        ContextRow {
          text: "Normal (4px)"
          checked: contextMenu.dock.itemSpacing === 4
          onTriggered: contextMenu.dock.setItemSpacing(4)
        }

        ContextRow {
          text: "Relaxed (8px)"
          checked: contextMenu.dock.itemSpacing === 8
          onTriggered: contextMenu.dock.setItemSpacing(8)
        }
      }
    }

    Column {
      spacing: Style.space(2)
      visible: contextMenu.dock.contextAppId === "__folder_context__"

      ContextRow {
        text: contextMenu.dock.contextFolderName || "Folder"
        isHeader: true
      }

      ContextRow {
        text: "Open in File Manager"
        onTriggered: {
          Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote(contextMenu.dock.contextFolderPath.replace(/^~/, Quickshell.env("HOME"))))
          contextMenu.dock.closeContext()
        }
      }

      ContextRow {
        text: "Open in Terminal"
        onTriggered: {
          Util.execDetached("uwsm-app -- xdg-terminal-exec --dir=" + Util.shellQuote(contextMenu.dock.contextFolderPath.replace(/^~/, Quickshell.env("HOME"))))
          contextMenu.dock.closeContext()
        }
      }

      MenuDivider {}

      ContextRow {
        text: "Unpin from Dock"
        danger: true
        onTriggered: {
          contextMenu.dock.toggleFolderPin(contextMenu.dock.contextFolderPath, contextMenu.dock.contextFolderName, "")
          contextMenu.dock.closeContext()
        }
      }
    }

    Column {
      spacing: Style.space(2)
      visible: contextMenu.dock.contextAppId === "__tile_context__"

      ContextRow {
        text: contextMenu.dock.contextTileName !== "" ? contextMenu.dock.contextTileName : (contextMenu.dock.contextTileAppId !== "" ? contextMenu.dock.contextTileAppId : "Window")
        isHeader: true
      }

      ContextRow {
        text: contextMenu.dock.contextTileWins.length > 1 ? "Restore All Here" : "Restore Here"
        onTriggered: {
          contextMenu.dock.restoreContextTile()
          contextMenu.dock.closeContext()
        }
      }

      ContextRow {
        text: contextMenu.dock.contextTileWins.length > 1 ? "Restore All to Original" : "Restore to Original"
        onTriggered: {
          contextMenu.dock.restoreContextTileOriginal()
          contextMenu.dock.closeContext()
        }
      }

      MenuDivider {}

      ContextRow {
        text: contextMenu.dock.contextTilePinned ? "Unpin from Dock" : "Pin to Dock"
        onTriggered: {
          contextMenu.dock.togglePin(contextMenu.dock.contextTileAppId)
          contextMenu.dock.closeContext()
        }
      }

      MenuDivider {}

      ContextRow {
        text: contextMenu.dock.contextTileWins.length > 1 ? "Close All" : "Close"
        danger: true
        onTriggered: {
          contextMenu.dock.closeContextTile()
          contextMenu.dock.closeContext()
        }
      }
    }

    Column {
      spacing: Style.space(2)
      visible: contextMenu.dock.contextAppId === "__app_group_context__"

      ContextRow {
        text: contextMenu.dock.contextAppGroupData
          ? String(contextMenu.dock.contextAppGroupData.name || "Applications") : "Applications"
        isHeader: true
      }
      ContextRow {
        text: "Open Group"
        onTriggered: {
          var group = contextMenu.dock.contextAppGroupData
          var anchor = contextMenu.dock.contextAnchor
          contextMenu.dock.closeContext()
          contextMenu.dock.openAppGroup(group, anchor)
        }
      }
      MenuDivider {}
      ContextRow {
        text: "Ungroup"
        danger: true
        onTriggered: {
          contextMenu.dock.ungroupAppGroup(contextMenu.dock.contextAppGroupData.id)
          contextMenu.dock.closeContext()
        }
      }
    }

    Item {
      id: appContextMenuWrapper
      visible: contextMenu.dock.contextAppId !== "" && contextMenu.dock.contextAppId.indexOf("__") !== 0
      implicitWidth: appContextMenuColumn.implicitWidth
      implicitHeight: appContextMenuColumn.implicitHeight
      width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth
      height: appContextMenuColumn.implicitHeight

      Column {
        id: appContextMenuColumn
        spacing: Style.space(2)
        width: contextMenu.rowWidth > 0 ? contextMenu.rowWidth : implicitWidth

        property int selectedWindowIdx: -1

        Column {
          id: windowListSection
          spacing: Style.space(1)
          visible: contextMenu.dock.contextWindowList.length > 0

          ContextRow {
            text: contextMenu.dock.contextWindowList.length > 1
              ? ("Windows (" + contextMenu.dock.contextWindowList.length + ")")
              : "Active Window"
            isHeader: true
          }

          Repeater {
            model: contextMenu.dock.contextWindowList
            delegate: ContextRow {
              text: contextMenu.dock.windowRowLabel(modelData)
              isWindowRow: true
              winFocused: contextMenu.dock.isWindowFocused(modelData)
              winParked: contextMenu.dock.isWindowParked(modelData)
              checked: appContextMenuColumn.selectedWindowIdx === index

              onTriggered: {
                if (modelData && modelData.address) {
                  contextMenu.dock.focusWindowByAddress(modelData.address, contextMenu.dock.contextAppId)
                }
                contextMenu.dock.closeContext()
              }
            }
          }

          MenuDivider {}
        }

        Column {
          spacing: Style.space(1)
          visible: contextMenu.dock.contextDesktopActions.length > 0

          Repeater {
            model: contextMenu.dock.contextDesktopActions
            delegate: ContextRow {
              text: modelData.name || modelData.id
              onTriggered: {
                contextMenu.dock.launchDesktopAction(modelData, contextMenu.dock.contextName)
                contextMenu.dock.closeContext()
              }
            }
          }

          MenuDivider {}
        }

        ContextRow {
          text: contextMenu.dock.contextWindows > 0 ? "New Window" : "Launch"
          visible: contextMenu.dock.contextDesktopActions.length === 0
          onTriggered: {
            contextMenu.dock.launchApp(contextMenu.dock.contextAppId, null)
            contextMenu.dock.closeContext()
          }
        }

        ContextRow {
          text: "Minimize Window"
          // Upstream showed this only for apps with more than one window,
          // on the assumption that a single-window app is minimized by
          // clicking its icon. That leaves no discoverable way to minimize
          // an app whose one window lives on a scratchpad workspace: the
          // icon click focuses it first (summoning the scratchpad) and only
          // minimizes on a second click.
          visible: contextMenu.dock.minimizeMode !== "off" && contextMenu.dock.contextWindows > 0
          // Nothing left on screen, or the row the selection sits on is
          // already parked — say so rather than offering a no-op.
          disabled: contextMenu.dock.selectedContextWindowParked
            || contextMenu.dock.visibleWindows(contextMenu.dock.contextWindowList).length === 0
          onTriggered: {
            contextMenu.dock.minimizeOneWindow(contextMenu.dock.entryForId(contextMenu.dock.contextAppId))
            contextMenu.dock.closeContext()
          }
        }

        ContextRow {
          text: contextMenu.dock.contextPinned ? "Unpin from Dock" : "Pin to Dock"
          onTriggered: {
            var deskEntry = DockModel.entryFor(contextMenu.dock.appRows, contextMenu.dock.contextAppId)
            if (!deskEntry && typeof DesktopEntries !== "undefined" && DesktopEntries) {
              deskEntry = DesktopEntries.heuristicLookup(contextMenu.dock.contextAppId) || DesktopEntries.byId(contextMenu.dock.contextAppId)
            }
            var canonicalId = (deskEntry && deskEntry.id) ? deskEntry.id : contextMenu.dock.contextAppId
            contextMenu.dock.togglePin(canonicalId)
            contextMenu.dock.closeContext()
          }
        }

        ContextRow {
          text: contextMenu.dock.contextWindows > 1 ? "Close All Windows" : "Close Window"
          visible: contextMenu.dock.contextWindows > 0
          danger: true
          onTriggered: {
            DockModel.closeApp((ToplevelManager.toplevels ? ToplevelManager.toplevels.values : []), contextMenu.dock.contextAppId)
            contextMenu.dock.closeContext()
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        z: 10
        acceptedButtons: Qt.NoButton
        onWheel: function(wheel) {
          if (wheel.angleDelta.y === 0 || contextMenu.dock.contextWindowList.length <= 1) return
          var dir = wheel.angleDelta.y > 0 ? -1 : 1
          var len = contextMenu.dock.contextWindowList.length
          if (appContextMenuColumn.selectedWindowIdx < 0) {
            var cur = 0
            for (var c = 0; c < len; c++) {
              if (contextMenu.dock.isWindowFocused(contextMenu.dock.contextWindowList[c])) { cur = c; break }
            }
            appContextMenuColumn.selectedWindowIdx = (cur + dir + len) % len
          } else {
            appContextMenuColumn.selectedWindowIdx = (appContextMenuColumn.selectedWindowIdx + dir + len) % len
          }
        }
      }
    }
  }
}
