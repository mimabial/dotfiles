pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import ".." as Shell
import qs.Commons
import "Ui"
import "Model.js" as Model

KeyboardPanel {
  id: panel
  required property var controller
  property alias keyTarget: keyCatcher
  property alias modeMenu: modeDropdown
  property alias scaleMenu: scaleDropdown
  property alias vrrMenu: vrrDropdown
  property alias rotationMenu: rotationDropdown
  property alias positionX: positionXField
  property alias positionY: positionYField
  property alias mirrorMenu: mirrorDropdown
  property alias bitdepthMenu: bitdepthDropdown
  property alias colorManagementMenu: colorManagementDropdown
  property alias sdrBrightness: sdrBrightnessField
  property alias sdrSaturation: sdrSaturationField
  property alias sdrMinLuminance: sdrMinLuminanceField
  property alias sdrMaxLuminance: sdrMaxLuminanceField
  property alias sdrCurveMenu: sdrCurveDropdown
  property alias minLuminance: minLuminanceField
  property alias maxLuminance: maxLuminanceField
  property alias maxAverageLuminance: maxAvgLuminanceField
  property alias forceWideMenu: forceWideDropdown
  property alias forceHdrMenu: forceHdrDropdown
  property alias iccProfile: iccProfileInput
  property alias workspaceAssignments: manualAssignmentList
  property alias profileNameField: profileNameInput
  property alias profileExecField: profileExecInput
  anchorItem: panel.controller.anchorItem
  owner: panel.controller
  shell: panel.controller.shell
  open: panel.controller.opened
  centerOnBar: false
  focusTarget: keyCatcher
  contentWidth: panel.fittedContentWidth(Style.space(panel.controller.expanded ? 1120 : 430))
  contentHeight: panel.controller.expanded
    ? panel.fittedContentHeight(Style.space(780))
    : panel.fittedContentHeight(compactColumn.implicitHeight)

  Item {
    width: 0
    height: 0

    Shortcut {
      sequence: "Shift+Left"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(-10, 0)
    }
    Shortcut {
      sequence: "Shift+Right"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(10, 0)
    }
    Shortcut {
      sequence: "Shift+Up"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(0, -10)
    }
    Shortcut {
      sequence: "Shift+Down"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(0, 10)
    }
    Shortcut {
      sequence: "Ctrl+Left"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(-1, 0)
    }
    Shortcut {
      sequence: "Ctrl+Right"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(1, 0)
    }
    Shortcut {
      sequence: "Ctrl+Up"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(0, -1)
    }
    Shortcut {
      sequence: "Ctrl+Down"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.nudgeSelectedOutput(0, 1)
    }
    Shortcut {
      sequence: "Alt+Left"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.snapSelectedOutput("left")
    }
    Shortcut {
      sequence: "Alt+Right"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.snapSelectedOutput("right")
    }
    Shortcut {
      sequence: "Alt+Up"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.snapSelectedOutput("up")
    }
    Shortcut {
      sequence: "Alt+Down"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "layout"
        && panel.controller.keyboardLayoutPane === "canvas" && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.snapSelectedOutput("down")
    }
    Shortcut {
      sequence: "L"
      enabled: panel.controller.opened && panel.controller.expanded && panel.controller.activePage === "profiles"
        && !panel.controller.keyboardHelpOpen && !panel.controller.execEditing && !keyCatcher.blocked
      onActivated: panel.controller.loadSelectedSavedProfile()
    }
  }

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    property bool returnPressed: false
    blocked: panel.controller.execEditing
      || profileNameInput.activeFocus
      || positionXField.field.activeFocus || positionYField.field.activeFocus
      || workspaceCountField.field.activeFocus || workspaceGroupSizeField.field.activeFocus
      || sdrBrightnessField.input.activeFocus || sdrSaturationField.input.activeFocus
      || sdrMinLuminanceField.input.activeFocus || sdrMaxLuminanceField.input.activeFocus
      || minLuminanceField.input.activeFocus || maxLuminanceField.input.activeFocus
      || maxAvgLuminanceField.input.activeFocus || iccProfileInput.activeFocus
      || modeDropdown.popupOpen || scaleDropdown.popupOpen || vrrDropdown.popupOpen
      || rotationDropdown.popupOpen || mirrorDropdown.popupOpen
      || bitdepthDropdown.popupOpen || colorManagementDropdown.popupOpen
      || sdrCurveDropdown.popupOpen || forceWideDropdown.popupOpen || forceHdrDropdown.popupOpen
      || workspaceStrategyDropdown.popupOpen
    onMoveRequested: function(dx, dy) {
      if (!panel.controller.expanded && dy !== 0) panel.controller.moveCursor(dy)
      else if (panel.controller.expanded) panel.controller.handleExpandedMove(dx, dy)
    }
    onReturnRequested: returnPressed = true
    onActivateRequested: {
      if (!panel.controller.expanded) panel.controller.activateCursor()
      else panel.controller.handleExpandedActivate(returnPressed)
      returnPressed = false
    }
    onCloseRequested: {
      if (panel.controller.keyboardHelpOpen) panel.controller.keyboardHelpOpen = false
      else if (panel.controller.previewTransaction !== "") panel.controller.revertPreview()
      else panel.controller.close()
    }
    onTabRequested: function(direction) {
      if (panel.controller.expanded) panel.controller.handleExpandedTab(direction)
    }
    onTextKey: function(text) { if (panel.controller.expanded) panel.controller.handleExpandedText(text) }

    Column {
      id: compactColumn
      visible: !panel.controller.expanded
      width: parent.width
      spacing: Style.space(14)

      Item {
        width: parent.width
        implicitHeight: Math.max(compactHero.implicitHeight, compactExpandButton.implicitHeight)

        Shell.PopupHero {
          id: compactHero
          shell: panel.controller.shell
          title: "Display"
          status: panel.controller.brightnessAvailable
            ? panel.controller.brightnessName(panel.controller.brightnessPercent) : "fixed brightness"
          anchors.left: parent.left
          anchors.right: compactExpandButton.left
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
        }

        Button {
          id: compactExpandButton
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "Expand"
          iconText: "󰊓"
          bordered: true
          foreground: panel.controller.foreground
          fontFamily: panel.controller.fontFamily
          fontSize: Style.font.caption
          onClicked: panel.controller.expanded = true
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: panel.controller.lastError !== ""
        width: parent.width
        text: panel.controller.lastError
        color: panel.controller.urgent
        font.family: panel.controller.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Column {
        width: parent.width
        spacing: Style.space(14)

        PanelSeparator { foreground: panel.controller.foreground }

        BrightnessControl {
          visible: panel.controller.brightnessConnector !== ""
          width: parent.width
          shell: panel.controller.shell
          connector: panel.controller.brightnessConnector
          displayLabel: panel.controller.brightnessDisplayLabel
          value: panel.controller.brightnessPercent
          available: panel.controller.brightnessAvailable
          loading: panel.controller.brightnessLoading
          foreground: panel.controller.foreground
          dim: panel.controller.dim
          accent: Color.accent
          fontFamily: panel.controller.fontFamily
          onPreviewed: function(value) { panel.controller.previewBrightness(value) }
          onCommitted: function(value) { panel.controller.setBrightness(value) }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(textSizeTitle.implicitHeight, textSizeValue.implicitHeight)

            PanelSectionHeader {
              id: textSizeTitle
              anchors.left: parent.left
              text: "TEXT SIZE"
              foreground: panel.controller.foreground
              fontFamily: panel.controller.fontFamily
            }

            Text {
              id: textSizeValue
              textFormat: Text.PlainText
              anchors.right: parent.right
              text: panel.controller.effectiveTextSize + " px"
              color: panel.controller.foreground
              font.family: panel.controller.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
          }

          PanelSlider {
            width: parent.width
            shell: panel.controller.shell
            minimum: 0
            maximum: panel.controller.textSizes.length - 1
            value: panel.controller.textSizeIndex
            step: 1
            integer: true
            tickCount: panel.controller.textSizes.length
            onReleased: function(value) { panel.controller.setTextSize(value) }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "MONITOR MANAGEMENT"
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
          }

          Toggle {
            width: parent.width
            label: "Automatic display profiles"
            description: {
              if (panel.controller.serviceActionPending)
                return panel.controller.serviceTargetManaged ? "Taking control of display configuration…" : "Handing display control back…"
              if (panel.controller.serviceBroken) return "The background service could not start"
              if (panel.controller.managedChecked && panel.controller.profileAutomatic)
                return "Switch layouts on monitor, lid, and resume events"
              if (panel.controller.managedChecked) return "Owns and applies monitor configuration"
              return "Read-only — display configuration is controlled elsewhere"
            }
            checked: panel.controller.managedChecked
            enabled: !panel.controller.serviceActionPending
            hasCursor: panel.controller.cursorActive && panel.controller.cursorIndex === 0
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.setManaged(!panel.controller.managedChecked)
          }
        }

        Repeater {
          model: panel.controller.actionRows

          ActionRow {
            controller: panel.controller
            required property var modelData
            required property int index
            width: parent.width
            rowIndex: 1 + index
            icon: String(modelData.icon)
            title: String(modelData.title)
            subtitle: String(modelData.subtitle)
            enabled: true
            onActivated: panel.controller.activateRow(String(modelData.id))
          }
        }

        EditorPane {
          width: parent.width
          height: Style.space(250)
          title: "Monitor Layout"
          meta: panel.controller.monitorCount + (panel.controller.monitorCount === 1 ? " display" : " displays")
          active: true
          foreground: panel.controller.foreground
          dim: panel.controller.dim
          accent: Color.accent
          fontFamily: panel.controller.fontFamily
          opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

          DisplayCanvas {
            anchors.fill: parent
            profile: panel.controller.draftProfile
            editorDisplays: panel.controller.editorDocument.displays
            workspacePlan: panel.controller.workspacePlan
            emphasis: "layout"
            selectedKey: panel.controller.selectedOutputKey
            interactive: false
            selectable: panel.controller.editorReady
            movable: panel.controller.managedChecked && panel.controller.editorReady && !panel.controller.editPending && panel.controller.previewTransaction === ""
            detailed: true
            framed: false
            foreground: panel.controller.foreground
            dim: panel.controller.dim
            accent: Color.accent
            fontFamily: panel.controller.fontFamily
            onOutputSelected: function(key) { panel.controller.selectedOutputKey = key }
            onOutputMoved: function(key, x, y, snapDistance) {
              panel.controller.editOutput({ x: x, y: y, snap_distance: snapDistance }, key)
            }
          }
        }

        BorderSurface {
          visible: panel.controller.draftDirty || panel.controller.previewTransaction !== ""
          width: parent.width
          implicitHeight: compactDraftActions.implicitHeight + Style.space(16)
          color: Style.selectedFillFor(panel.controller.foreground, Color.accent)
          borderSpec: Border.controlSpec("selected", panel.controller.foreground, Color.accent)
          radius: Style.cornerRadius
          opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

          Row {
            id: compactDraftActions
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            spacing: Style.space(7)

            Column {
              width: parent.width - compactDiscardDraft.width - compactApplyDraft.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: panel.controller.previewTransaction !== ""
                  ? (panel.controller.previewKind === "profile" ? "Keep this profile?" : "Keep this layout?")
                  : (panel.controller.editPending ? "Checking layout…" : "Layout changed")
                color: panel.controller.foreground
                font.family: panel.controller.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                visible: panel.controller.previewTransaction !== ""
                width: parent.width
                text: panel.controller.previewSeconds + " seconds to decide"
                color: panel.controller.dim
                font.family: panel.controller.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            Button {
              id: compactDiscardDraft
              text: panel.controller.previewTransaction !== "" ? "Revert" : "Discard"
              bordered: true
              enabled: panel.controller.previewTransaction !== ""
                ? !panel.controller.previewPending
                : (!panel.controller.editorLoading && !panel.controller.editPending)
              foreground: panel.controller.foreground
              fontFamily: panel.controller.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: {
                if (panel.controller.previewTransaction !== "") panel.controller.revertPreview()
                else panel.controller.requestEditorState()
              }
            }

            Button {
              id: compactApplyDraft
              text: panel.controller.previewTransaction !== ""
                ? "Keep"
                : (panel.controller.sourceProfile !== "" ? "Preview" : "Finish in editor")
              selected: true
              bordered: true
              enabled: !panel.controller.editPending && !panel.controller.previewPending
                && panel.controller.managedChecked
              foreground: panel.controller.foreground
              fontFamily: panel.controller.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(4)
              onClicked: {
                if (panel.controller.previewTransaction !== "") panel.controller.keepPreview()
                else if (panel.controller.sourceProfile !== "") panel.controller.previewDraft()
                else panel.controller.expanded = true
              }
            }
          }
        }

        PanelSeparator { foreground: panel.controller.foreground }

        Column {
          width: parent.width
          spacing: Style.space(6)
          opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

          PanelSectionHeader {
            text: "PROFILE"
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
          }

          Row {
            id: compactProfileStatus
            width: parent.width
            height: compactProfileText.implicitHeight + Style.space(8)
            spacing: Style.space(12)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: panel.controller.monitorCount > 1 ? "󰍺" : "󰍹"
              color: panel.controller.foreground
              font.family: panel.controller.fontFamily
              font.pixelSize: Style.font.icon
            }

            Column {
              id: compactProfileText
              width: parent.width - parent.children[0].width - parent.spacing
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: panel.controller.profileStatusTitle
                color: panel.controller.foreground
                font.family: panel.controller.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: panel.controller.profileStatusSubtitle
                color: panel.controller.dim
                font.family: panel.controller.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          Button {
            width: parent.width
            visible: !panel.controller.profileAutomatic
            text: panel.controller.profileModePending ? "Resuming automatic matching…" : "Resume automatic matching"
            selected: true
            bordered: true
            enabled: panel.controller.managedChecked && !panel.controller.profileModePending
              && panel.controller.previewTransaction === "" && !panel.controller.previewPending
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.setProfileAutomatic(true)
          }

          Button {
            width: parent.width
            visible: panel.controller.profileAutomatic && panel.controller.documentReady
              && panel.controller.connectedDisplayCount > 0 && !panel.controller.exactDisplayProfile
              && panel.controller.previewTransaction === "" && !panel.controller.previewPending
            text: "Create profile"
            selected: true
            bordered: true
            enabled: panel.controller.managedChecked && panel.controller.editorReady
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.beginCreateProfile()
          }
        }
      }
    }

    Item {
      id: expandedEditor
      visible: panel.controller.expanded
      anchors.fill: parent

      Item {
        id: editorNav
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.space(38)

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Repeater {
            model: panel.controller.pageOptions

            Button {
              required property var modelData
              text: String(modelData.label || "")
              selected: String(modelData.value || "") === panel.controller.activePage
              foreground: panel.controller.foreground
              fontFamily: panel.controller.fontFamily
              fontSize: Style.font.caption
              horizontalPadding: Style.space(7)
              verticalPadding: Style.space(3)
              onClicked: panel.controller.activePage = String(modelData.value || "layout")
            }
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: "Current setup  ·  " + panel.controller.profileStatusTitle
              + (!panel.controller.managedChecked ? " · read-only"
                : (panel.controller.profileAutomatic ? " · automatic" : " · pinned"))
            color: panel.controller.dim
            font.family: panel.controller.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }

          Button {
            id: keyboardHelpButton
            text: ""
            bordered: true
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            fontSize: Style.font.caption
            implicitWidth: keyboardHelpButtonContent.implicitWidth
              + horizontalPadding * 2 + Style.normalBorderWidth * 2
            implicitHeight: compactButton.implicitHeight

            Row {
              id: keyboardHelpButtonContent
              anchors.centerIn: parent
              spacing: Style.space(4)

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: 1
                text: "?"
                color: panel.controller.foreground
                font.family: panel.controller.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "Keys"
                color: panel.controller.foreground
                font.family: panel.controller.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            onClicked: panel.controller.keyboardHelpOpen = true
          }

          Button {
            id: compactButton
            text: "Compact"
            iconText: "󰊔"
            bordered: true
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            fontSize: Style.font.caption
            onClicked: panel.controller.expanded = false
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Qt.rgba(panel.controller.foreground.r, panel.controller.foreground.g, panel.controller.foreground.b, 0.22)
        }
      }

      BorderSurface {
        id: previewBanner
        visible: panel.controller.previewTransaction !== ""
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: editorNav.bottom
        anchors.topMargin: Style.space(8)
        height: Style.space(58)
        color: Style.selectedFillFor(panel.controller.foreground, Color.accent)
        borderSpec: Border.controlSpec("selected", panel.controller.foreground, Color.accent)
        radius: Style.cornerRadius

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(10)

          Column {
            width: parent.width - keepExpandedPreview.width - revertExpandedPreview.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Keep this layout?"
              color: panel.controller.foreground
              font.family: panel.controller.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: panel.controller.previewSeconds + " seconds before the previous layout returns"
              color: panel.controller.dim
              font.family: panel.controller.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Button {
            id: revertExpandedPreview
            anchors.verticalCenter: parent.verticalCenter
            text: "Revert"
            bordered: true
            enabled: !panel.controller.previewPending
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.revertPreview()
          }

          Button {
            id: keepExpandedPreview
            anchors.verticalCenter: parent.verticalCenter
            text: panel.controller.previewKind === "draft" ? "Keep & save" : "Keep"
            selected: true
            bordered: true
            enabled: !panel.controller.previewPending
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.keepPreview()
          }
        }
      }

      Item {
        id: editorBody
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: previewBanner.visible ? previewBanner.bottom : editorNav.bottom
        anchors.bottom: editorFooter.top
        anchors.topMargin: Style.space(10)
        anchors.bottomMargin: Style.space(10)

        Item {
          visible: panel.controller.activePage === "layout"
          anchors.fill: parent

          EditorPane {
            id: layoutPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.round(parent.width * 0.65)
            title: "Monitor Layout"
            meta: panel.controller.hiddenDisplays
            active: panel.controller.keyboardLayoutPane === "canvas"
            foreground: panel.controller.foreground
            dim: panel.controller.dim
            accent: Color.accent
            fontFamily: panel.controller.fontFamily
            opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

            DisplayCanvas {
              anchors.fill: parent
              profile: panel.controller.draftProfile
              editorDisplays: panel.controller.editorDocument.displays
              workspacePlan: panel.controller.workspacePlan
              emphasis: "layout"
              selectedKey: panel.controller.selectedOutputKey
              interactive: false
              selectable: panel.controller.editorReady
              movable: panel.controller.managedChecked && panel.controller.editorReady && !panel.controller.editPending && panel.controller.previewTransaction === ""
              detailed: true
              framed: false
              foreground: panel.controller.foreground
              dim: panel.controller.dim
              accent: Color.accent
              fontFamily: panel.controller.fontFamily
              onOutputSelected: function(key) { panel.controller.selectedOutputKey = key }
              onOutputMoved: function(key, x, y, snapDistance) {
                panel.controller.editOutput({ x: x, y: y, snap_distance: snapDistance }, key)
              }
            }
          }

          Column {
            anchors.left: layoutPane.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: Style.space(10)

            EditorPane {
              id: inspectorPane
              width: parent.width
              height: Style.space(185)
              title: "Info"
              meta: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.name || "") : ""
              foreground: panel.controller.foreground
              dim: panel.controller.dim
              accent: Color.accent
              fontFamily: panel.controller.fontFamily
              opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

              Column {
                anchors.fill: parent
                spacing: Style.space(3)

                InfoRow {
                  controller: panel.controller
                  label: "Connector"
                  value: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.name || "—") : "—"
                }
                InfoRow {
                  controller: panel.controller
                  label: "Type"
                  value: Model.displayType(panel.controller.selectedOutputMetadata, panel.controller.selectedOutput)
                }
                InfoRow {
                  controller: panel.controller
                  label: "Model"
                  value: panel.controller.selectedOutput ? Model.displayModelLabel(panel.controller.selectedOutput, false) : "—"
                }
                InfoRow {
                  controller: panel.controller
                  label: "Serial"
                  value: panel.controller.selectedOutput && String(panel.controller.selectedOutput.serial || "").trim() !== ""
                    ? String(panel.controller.selectedOutput.serial) : "(none)"
                }
                InfoRow {
                  controller: panel.controller
                  label: "Layout px"
                  value: panel.controller.selectedOutput
                    ? Model.outputLogicalSize(panel.controller.selectedOutput).width + " × " + Model.outputLogicalSize(panel.controller.selectedOutput).height
                    : "—"
                }
                InfoRow {
                  controller: panel.controller
                  label: "Workspace"
                  value: String(panel.controller.selectedOutputMetadata.workspace || "(none)")
                }
                InfoRow {
                  controller: panel.controller
                  label: "DPMS"
                  value: Model.onOff(panel.controller.selectedOutputMetadata.dpms === true)
                }
                InfoRow {
                  controller: panel.controller
                  visible: Number(panel.controller.selectedOutputMetadata.physical_width || 0) > 0
                  label: "Panel mm"
                  value: Number(panel.controller.selectedOutputMetadata.physical_width || 0)
                    + " × " + Number(panel.controller.selectedOutputMetadata.physical_height || 0) + " mm"
                }
              }
            }

            EditorPane {
              width: parent.width
              height: parent.height - Style.space(195)
              title: "Display  -  Color"
              active: panel.controller.keyboardLayoutPane !== "canvas"
              foreground: panel.controller.foreground
              dim: panel.controller.dim
              accent: Color.accent
              fontFamily: panel.controller.fontFamily

              ButtonGroup {
                id: inspectorTabs
                anchors.left: parent.left
                anchors.top: parent.top
                options: panel.controller.inspectorOptions
                value: panel.controller.inspectorPage
                foreground: panel.controller.foreground
                background: panel.controller.shell.background
                accent: Color.accent
                fontFamily: panel.controller.fontFamily
                fontSize: Style.font.caption
                onChanged: function(value) {
                  panel.controller.inspectorPage = value
                  panel.controller.keyboardLayoutPane = value
                }
              }

              Column {
                visible: panel.controller.inspectorPage === "display"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: inspectorTabs.bottom
                anchors.topMargin: Style.space(9)
                spacing: Style.space(9)

                BrightnessControl {
                  visible: panel.controller.brightnessConnector !== ""
                  width: parent.width
                  shell: panel.controller.shell
                  connector: panel.controller.brightnessConnector
                  displayLabel: panel.controller.brightnessDisplayLabel
                  value: panel.controller.brightnessPercent
                  available: panel.controller.brightnessAvailable
                  loading: panel.controller.brightnessLoading
                  foreground: panel.controller.foreground
                  dim: panel.controller.dim
                  accent: Color.accent
                  fontFamily: panel.controller.fontFamily
                  onPreviewed: function(value) { panel.controller.previewBrightness(value) }
                  onCommitted: function(value) { panel.controller.setBrightness(value) }
                }

                PanelSeparator {
                  visible: panel.controller.brightnessConnector !== ""
                  width: parent.width
                  foreground: panel.controller.foreground
                }

                Toggle {
                  id: displayEnabledToggle
                  width: parent.width
                  label: "Enabled"
                  description: checked ? "This display participates in the layout" : "Saved as off"
                  checked: panel.controller.selectedOutput ? panel.controller.selectedOutput.enabled !== false : false
                  enabled: panel.controller.managedChecked && !!panel.controller.selectedOutput && !panel.controller.editPending
                    && (checked ? Model.enabledOutputCount(panel.controller.draftProfile) > 1 : true)
                  opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity
                  hasCursor: panel.controller.inspectorHasCursor("enabled")
                  foreground: panel.controller.foreground
                  fontFamily: panel.controller.fontFamily
                  onClicked: panel.controller.editOutput({ enabled: !checked })
                }

                Grid {
                  width: parent.width
                  columns: 2
                  spacing: Style.space(8)
                  enabled: panel.controller.managedChecked
                  opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity
                  readonly property real cellWidth: (width - spacing) / 2

                  PanelDropdown {
                    id: modeDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "MODE"
                    options: Model.modeOptions(panel.controller.editorDocument.displays, panel.controller.selectedOutputKey)
                    value: panel.controller.selectedOutput ? Model.outputMode(panel.controller.selectedOutput) : ""
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("mode")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ mode: value }) }
                  }

                  PanelDropdown {
                    id: scaleDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "SCALE"
                    options: Model.scaleOptions(panel.controller.editorDocument.displays, panel.controller.selectedOutputKey,
                      panel.controller.selectedOutput ? panel.controller.selectedOutput.scale : 1)
                    value: panel.controller.selectedOutput ? Model.formatScale(panel.controller.selectedOutput.scale) : "1"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("scale")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ scale: Number(value) }) }
                  }

                  PanelDropdown {
                    id: vrrDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "VRR"
                    options: panel.controller.vrrOptions
                    value: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.vrr || 0) : "0"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("vrr")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ vrr: Number(value) }) }
                  }

                  PanelDropdown {
                    id: rotationDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "ROTATION"
                    options: panel.controller.transformOptions
                    value: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.transform || 0) : "0"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("rotation")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ transform: Number(value) }) }
                  }

                  NumberField {
                    id: positionXField
                    width: parent.cellWidth
                    fieldWidth: width
                    label: "POSITION X"
                    from: -20000
                    to: 20000
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.x || 0) : 0
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("positionX")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onModified: function(value) {
                      panel.controller.editOutput({ x: value })
                      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                    }
                  }

                  NumberField {
                    id: positionYField
                    width: parent.cellWidth
                    fieldWidth: width
                    label: "POSITION Y"
                    from: -20000
                    to: 20000
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.y || 0) : 0
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("positionY")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onModified: function(value) {
                      panel.controller.editOutput({ y: value })
                      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                    }
                  }
                }

                PanelDropdown {
                  id: mirrorDropdown
                  popupParent: keyCatcher
                  ownerOpen: panel.controller.opened && panel.controller.expanded
                  width: parent.width
                  label: "MIRROR"
                  options: Model.mirrorOptions(panel.controller.draftProfile, panel.controller.selectedOutputKey)
                  value: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.mirror_of || "") : ""
                  enabled: panel.controller.managedChecked && !!panel.controller.selectedOutput && !panel.controller.editPending
                  hasCursor: panel.controller.inspectorHasCursor("mirror")
                  opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity
                  foreground: panel.controller.foreground
                  fontFamily: panel.controller.fontFamily
                  onChanged: function(value) { panel.controller.editOutput({ mirror_of: value }) }
                }
              }

              Column {
                visible: panel.controller.inspectorPage === "color"
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: inspectorTabs.bottom
                anchors.topMargin: Style.space(9)
                spacing: Style.space(8)
                enabled: panel.controller.managedChecked
                opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

                Grid {
                  width: parent.width
                  columns: 2
                  spacing: Style.space(7)
                  readonly property real cellWidth: (width - spacing) / 2

                  PanelDropdown {
                    id: bitdepthDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "BIT DEPTH"
                    options: panel.controller.bitdepthOptions
                    value: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.bitdepth || 8) : "8"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("bitdepth")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ bitdepth: Number(value) }) }
                  }

                  PanelDropdown {
                    id: colorManagementDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "COLOR MANAGEMENT"
                    options: panel.controller.colorManagementOptions
                    value: panel.controller.selectedOutput && String(panel.controller.selectedOutput.cm || "") !== ""
                      ? String(panel.controller.selectedOutput.cm) : "srgb"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("colorManagement")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ cm: value }) }
                  }

                  DecimalField {
                    controller: panel.controller
                    keyTarget: keyCatcher
                    id: sdrBrightnessField
                    width: parent.cellWidth
                    label: "SDR BRIGHTNESS"
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.sdr_brightness || 0) : 0
                    decimals: 2
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("sdrBrightness")
                    onModified: function(value) { panel.controller.editOutput({ sdr_brightness: value }) }
                  }

                  DecimalField {
                    controller: panel.controller
                    keyTarget: keyCatcher
                    id: sdrSaturationField
                    width: parent.cellWidth
                    label: "SDR SATURATION"
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.sdr_saturation || 0) : 0
                    decimals: 2
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("sdrSaturation")
                    onModified: function(value) { panel.controller.editOutput({ sdr_saturation: value }) }
                  }

                  DecimalField {
                    controller: panel.controller
                    keyTarget: keyCatcher
                    id: sdrMinLuminanceField
                    width: parent.cellWidth
                    label: "SDR MIN LUMINANCE"
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.sdr_min_luminance || 0) : 0
                    decimals: 3
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("sdrMinLuminance")
                    onModified: function(value) { panel.controller.editOutput({ sdr_min_luminance: value }) }
                  }

                  DecimalField {
                    controller: panel.controller
                    keyTarget: keyCatcher
                    id: sdrMaxLuminanceField
                    width: parent.cellWidth
                    label: "SDR MAX LUMINANCE"
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.sdr_max_luminance || 0) : 0
                    decimals: 0
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("sdrMaxLuminance")
                    onModified: function(value) { panel.controller.editOutput({ sdr_max_luminance: Math.round(value) }) }
                  }

                  PanelDropdown {
                    id: sdrCurveDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "SDR CURVE"
                    options: [
                      { value: "default", label: "Default" },
                      { value: "gamma22", label: "Gamma 2.2" },
                      { value: "srgb", label: "sRGB" }
                    ]
                    value: panel.controller.selectedOutput && String(panel.controller.selectedOutput.sdr_eotf || "") !== ""
                      ? String(panel.controller.selectedOutput.sdr_eotf) : "default"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("sdrCurve")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ sdr_eotf: value }) }
                  }

                  DecimalField {
                    controller: panel.controller
                    keyTarget: keyCatcher
                    id: minLuminanceField
                    width: parent.cellWidth
                    label: "MIN LUMINANCE"
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.min_luminance || 0) : 0
                    decimals: 3
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("minLuminance")
                    onModified: function(value) { panel.controller.editOutput({ min_luminance: value }) }
                  }

                  DecimalField {
                    controller: panel.controller
                    keyTarget: keyCatcher
                    id: maxLuminanceField
                    width: parent.cellWidth
                    label: "MAX LUMINANCE"
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.max_luminance || 0) : 0
                    decimals: 0
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("maxLuminance")
                    onModified: function(value) { panel.controller.editOutput({ max_luminance: Math.round(value) }) }
                  }

                  DecimalField {
                    controller: panel.controller
                    keyTarget: keyCatcher
                    id: maxAvgLuminanceField
                    width: parent.cellWidth
                    label: "MAX AVG LUMINANCE"
                    value: panel.controller.selectedOutput ? Number(panel.controller.selectedOutput.max_avg_luminance || 0) : 0
                    decimals: 0
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("maxAverageLuminance")
                    onModified: function(value) { panel.controller.editOutput({ max_avg_luminance: Math.round(value) }) }
                  }

                  PanelDropdown {
                    id: forceWideDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "FORCE WIDE GAMUT"
                    options: panel.controller.triStateOptions
                    value: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.supports_wide_color || 0) : "0"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("forceWideColor")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ supports_wide_color: Number(value) }) }
                  }

                  PanelDropdown {
                    id: forceHdrDropdown
                    popupParent: keyCatcher
                    ownerOpen: panel.controller.opened && panel.controller.expanded
                    width: parent.cellWidth
                    label: "FORCE HDR"
                    options: panel.controller.triStateOptions
                    value: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.supports_hdr || 0) : "0"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("forceHdr")
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                    onChanged: function(value) { panel.controller.editOutput({ supports_hdr: Number(value) }) }
                  }
                }

                Column {
                  width: parent.width
                  spacing: Style.space(4)

                  PanelSectionHeader {
                    text: "ICC PROFILE"
                    foreground: panel.controller.foreground
                    fontFamily: panel.controller.fontFamily
                  }

                  TextField {
                    id: iccProfileInput
                    width: parent.width
                    text: panel.controller.selectedOutput ? String(panel.controller.selectedOutput.icc || "") : ""
                    placeholderText: "None — enter an absolute profile path"
                    enabled: !!panel.controller.selectedOutput && !panel.controller.editPending
                    hasCursor: panel.controller.inspectorHasCursor("iccProfile")
                    foreground: panel.controller.foreground
                    onEditingFinished: {
                      var returnToKeyboard = activeFocus
                      panel.controller.editOutput({ icc: text })
                      if (returnToKeyboard)
                        Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                    }
                  }
                }
              }
            }
          }
        }

        Item {
          visible: panel.controller.activePage === "profiles"
          anchors.fill: parent
          opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

          EditorPane {
            id: profileListPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.round(parent.width * 0.34)
            title: "Saved Profiles"
            meta: panel.controller.savedProfiles.length + " saved"
            active: true
            foreground: panel.controller.foreground
            dim: panel.controller.dim
            accent: Color.accent
            fontFamily: panel.controller.fontFamily

            Column {
              anchors.fill: parent
              spacing: Style.space(6)

              Toggle {
                width: parent.width
                label: "Automatically use the best profile"
                description: {
                  if (panel.controller.profileModePending) return "Updating profile selection mode…"
                  return "Matches your connected displays to your saved profiles"
                }
                checked: panel.controller.profileAutomatic
                enabled: panel.controller.managedChecked && !panel.controller.profileModePending
                  && panel.controller.previewTransaction === "" && !panel.controller.previewPending
                  && (!panel.controller.profileAutomatic || panel.controller.activeProfile !== "")
                foreground: panel.controller.foreground
                fontFamily: panel.controller.fontFamily
                onClicked: panel.controller.setProfileAutomatic(!checked)
              }

              PanelSeparator { foreground: panel.controller.foreground }

              Row {
                width: parent.width
                height: Style.space(22)

                Text {
                  textFormat: Text.PlainText
                  width: parent.width - Style.space(58)
                  text: "PROFILE"
                  color: panel.controller.dim
                  font.family: panel.controller.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  width: Style.space(58)
                  text: "MATCH"
                  color: panel.controller.dim
                  font.family: panel.controller.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  horizontalAlignment: Text.AlignRight
                }
              }

              Repeater {
                model: panel.controller.document && panel.controller.document.profiles instanceof Array ? panel.controller.document.profiles : []

                BorderSurface {
                  id: profileRow
                  required property var modelData
                  width: parent.width
                  height: Style.space(32)
                  readonly property bool selected: String(modelData.name || "") === panel.controller.selectedSavedProfileName
                  color: selected
                    ? Style.selectedFillFor(panel.controller.foreground, Color.accent)
                    : "transparent"
                  borderSpec: selected ? Border.controlSpec("selected", panel.controller.foreground, Color.accent) : Border.none()
                  radius: Style.cornerRadius

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(7)
                    anchors.rightMargin: Style.space(7)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - profileMatchText.width - Style.space(8)
                      text: (profileRow.modelData.active ? "›  " : "   ") + String(profileRow.modelData.name || "Profile")
                      color: profileRow.modelData.active || profileRow.selected ? panel.controller.foreground : panel.controller.dim
                      font.family: panel.controller.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: profileRow.modelData.active
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      id: profileMatchText
                      anchors.verticalCenter: parent.verticalCenter
                      text: Number(profileRow.modelData.match_score || 0) > 0 ? String(profileRow.modelData.match_score) : "—"
                      color: profileRow.modelData.recommended ? Color.accent : panel.controller.dim
                      font.family: panel.controller.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: profileRow.modelData.recommended
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: String(parent.modelData.name || "") !== ""
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      var selected = String(parent.modelData.name || "")
                      panel.controller.selectedSavedProfileName = selected
                    }
                  }
                }
              }
            }
          }

          Column {
            anchors.left: profileListPane.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: Style.space(10)

            EditorPane {
              id: profileDetailsPane
              width: parent.width
              height: Math.min(parent.height - Style.space(180),
                Math.max(Style.space(190), Style.space(38 + panel.controller.selectedSavedDetailRowCount * 18)))
              title: "Profile Details"
              meta: panel.controller.selectedSavedSummary && panel.controller.selectedSavedSummary.active ? "Active" : ""
              foreground: panel.controller.foreground
              dim: panel.controller.dim
              accent: Color.accent
              fontFamily: panel.controller.fontFamily

              Column {
                anchors.fill: parent
                spacing: Style.space(4)

                InfoRow {
                  controller: panel.controller
                  label: "Name"
                  value: panel.controller.selectedSavedProfile ? String(panel.controller.selectedSavedProfile.name || "—") : "—"
                  valueBold: true
                }
                InfoRow {
                  controller: panel.controller
                  label: "Updated"
                  value: panel.controller.selectedSavedProfile ? Model.profileUpdatedLabel(panel.controller.selectedSavedProfile.updated_at) : "—"
                }
                InfoRow {
                  controller: panel.controller
                  label: "Match"
                  value: panel.controller.selectedSavedSummary ? Model.profileMatchLabel(panel.controller.selectedSavedSummary) : "—"
                  valueAccent: !!panel.controller.selectedSavedSummary
                    && (panel.controller.selectedSavedSummary.active || panel.controller.selectedSavedSummary.recommended)
                }

                Repeater {
                  model: panel.controller.selectedSavedMatchReasons

                  InfoRow {
                    controller: panel.controller
                    required property var modelData
                    label: ""
                    value: String(modelData.value || "")
                  }
                }

                InfoRow {
                  controller: panel.controller
                  label: "Displays"
                  value: panel.controller.selectedSavedSummary
                    ? Number(panel.controller.selectedSavedSummary.output_count || 0) + " saved · "
                      + Number(panel.controller.selectedSavedSummary.connected_outputs || 0) + " connected"
                    : "—"
                }

                Repeater {
                  model: panel.controller.selectedSavedHiddenRows

                  InfoRow {
                    controller: panel.controller
                    required property var modelData
                    label: String(modelData.label || "")
                    value: String(modelData.value || "")
                  }
                }

                InfoRow {
                  controller: panel.controller
                  label: "Exec"
                  value: panel.controller.selectedSavedProfile && String(panel.controller.selectedSavedProfile.exec || "").trim() !== ""
                    ? String(panel.controller.selectedSavedProfile.exec) : "(not set)"
                }

                Repeater {
                  model: panel.controller.selectedSavedWorkspaceRows

                  ProfileWorkspaceInfoRow {
                    controller: panel.controller
                    required property var modelData
                    required property int index
                    label: index === 0 ? "Workspaces" : ""
                    displayName: String(modelData.name || "Display")
                    workspaces: String(modelData.workspaces || "—")
                  }
                }

                InfoRow {
                  controller: panel.controller
                  visible: panel.controller.selectedSavedWorkspaceRows.length === 0
                  label: "Workspaces"
                  value: "(not managed)"
                }
              }
            }

            EditorPane {
              width: parent.width
              height: parent.height - profileDetailsPane.height - parent.spacing
              title: "Monitor Layout"
              meta: panel.controller.selectedSavedProfileName
              foreground: panel.controller.foreground
              dim: panel.controller.dim
              accent: Color.accent
              fontFamily: panel.controller.fontFamily

              DisplayCanvas {
                anchors.fill: parent
                profile: panel.controller.selectedSavedProfile || ({ outputs: [] })
                editorDisplays: panel.controller.editorDocument.displays
                workspacePlan: panel.controller.selectedSavedWorkspacePlan
                emphasis: "profile"
                selectedKey: ""
                interactive: false
                detailed: true
                framed: false
                markDisconnected: true
                foreground: panel.controller.foreground
                dim: panel.controller.dim
                accent: Color.accent
                fontFamily: panel.controller.fontFamily
              }
            }
          }
        }

        Item {
          visible: panel.controller.activePage === "workspaces"
          anchors.fill: parent
          enabled: panel.controller.managedChecked
          opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

          EditorPane {
            id: workspaceSettingsPane
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.round(parent.width * 0.34)
            title: "Workspace Planner"
            active: true
            foreground: panel.controller.foreground
            dim: panel.controller.dim
            accent: Color.accent
            fontFamily: panel.controller.fontFamily

            Column {
              anchors.fill: parent
              spacing: Style.space(12)

              Toggle {
                id: workspaceEnabledToggle
                width: parent.width
                label: "Enabled"
                description: checked ? "Place workspaces with this profile" : "Leave placement unchanged"
                checked: !!((panel.controller.draftProfile || {}).workspaces || {}).enabled
                enabled: panel.controller.editorReady && !panel.controller.editPending
                hasCursor: panel.controller.expanded && panel.controller.activePage === "workspaces"
                  && panel.controller.workspaceKeyboardIndex === 0
                foreground: panel.controller.foreground
                fontFamily: panel.controller.fontFamily
                onClicked: panel.controller.editWorkspaces({ enabled: !checked })
              }

              PanelDropdown {
                id: workspaceStrategyDropdown
                popupParent: keyCatcher
                ownerOpen: panel.controller.opened && panel.controller.expanded
                width: parent.width
                label: "STRATEGY"
                scrollable: false
                options: [
                  { value: "manual", label: "Manual" },
                  { value: "sequential", label: "Sequential" },
                  { value: "interleave", label: "Interleaved" }
                ]
                value: String(((panel.controller.draftProfile || {}).workspaces || {}).strategy || "manual")
                enabled: panel.controller.editorReady && !panel.controller.editPending
                hasCursor: panel.controller.expanded && panel.controller.activePage === "workspaces"
                  && panel.controller.workspaceKeyboardIndex === 1
                foreground: panel.controller.foreground
                fontFamily: panel.controller.fontFamily
                onChanged: function(value) { panel.controller.changeWorkspaceStrategy(value) }
              }

              Row {
                width: parent.width
                spacing: Style.space(10)

                NumberField {
                  id: workspaceCountField
                  width: panel.controller.workspaceGroupSizeApplicable
                    ? (parent.width - parent.spacing) / 2 : parent.width
                  fieldWidth: width
                  label: "WORKSPACES"
                  from: 1
                  to: panel.controller.workspaceValueMaximum
                  value: String(((panel.controller.draftProfile || {}).workspaces || {}).strategy || "") === "manual"
                    ? Model.manualWorkspaceCount((panel.controller.draftProfile || {}).workspaces || {})
                    : Number(((panel.controller.draftProfile || {}).workspaces || {}).max_workspaces || 9)
                  enabled: !panel.controller.editPending
                  hasCursor: panel.controller.expanded && panel.controller.activePage === "workspaces"
                    && panel.controller.workspaceKeyboardIndex === 2
                  foreground: panel.controller.foreground
                  fontFamily: panel.controller.fontFamily
                  onModified: function(value) {
                    var returnToKeyboard = workspaceCountField.field.activeFocus
                    if (!panel.controller.editPending) panel.controller.setWorkspaceCount(value)
                    if (returnToKeyboard)
                      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                  }
                }

                NumberField {
                  id: workspaceGroupSizeField
                  visible: panel.controller.workspaceGroupSizeApplicable
                  width: (parent.width - parent.spacing) / 2
                  fieldWidth: width
                  label: "GROUP SIZE"
                  from: 1
                  to: panel.controller.workspaceValueMaximum
                  value: Number(((panel.controller.draftProfile || {}).workspaces || {}).group_size || 3)
                  enabled: !panel.controller.editPending
                    && String(((panel.controller.draftProfile || {}).workspaces || {}).strategy || "") === "sequential"
                  hasCursor: panel.controller.expanded && panel.controller.activePage === "workspaces"
                    && panel.controller.workspaceKeyboardIndex === 3
                  foreground: panel.controller.foreground
                  fontFamily: panel.controller.fontFamily
                  onModified: function(value) {
                    panel.controller.editWorkspaces({ group_size: value })
                    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
                  }
                }

              }

              PanelSeparator { foreground: panel.controller.foreground }

              PanelSectionHeader {
                text: String(((panel.controller.draftProfile || {}).workspaces || {}).strategy || "") === "manual"
                  ? "WORKSPACE → DISPLAY" : "MONITOR ORDER"
                foreground: panel.controller.foreground
                fontFamily: panel.controller.fontFamily
              }

              Repeater {
                model: String(((panel.controller.draftProfile || {}).workspaces || {}).strategy || "") === "manual"
                  ? [] : (((panel.controller.draftProfile || {}).workspaces || {}).monitor_order || [])

                BorderSurface {
                  id: orderRow
                  required property var modelData
                  required property int index
                  width: parent.width
                  height: Style.space(42)
                  readonly property bool hasKeyboardCursor: panel.controller.expanded
                    && panel.controller.activePage === "workspaces"
                    && panel.controller.workspaceKeyboardIndex === panel.controller.workspaceListKeyboardStart + index
                  color: hasKeyboardCursor
                    ? Style.selectedFillFor(panel.controller.foreground, Color.accent)
                    : Qt.rgba(panel.controller.foreground.r, panel.controller.foreground.g, panel.controller.foreground.b, 0.025)
                  borderSpec: Border.controlSpec(hasKeyboardCursor ? "focus" : "normal",
                    panel.controller.foreground, Color.accent)
                  radius: Style.cornerRadius

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(6)
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - orderUp.width - orderDown.width - parent.spacing * 2
                      text: (orderRow.index + 1) + ".  " + Model.outputDisplayLabel(panel.controller.draftProfile, String(orderRow.modelData))
                      color: panel.controller.foreground
                      font.family: panel.controller.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Button {
                      id: orderUp
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↑"
                      bordered: true
                      enabled: orderRow.index > 0 && !panel.controller.editPending
                      foreground: panel.controller.foreground
                      fontFamily: panel.controller.fontFamily
                      onClicked: panel.controller.moveWorkspaceMonitor(String(orderRow.modelData), -1)
                    }

                    Button {
                      id: orderDown
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↓"
                      bordered: true
                      enabled: orderRow.index < (((panel.controller.draftProfile || {}).workspaces || {}).monitor_order || []).length - 1
                        && !panel.controller.editPending
                      foreground: panel.controller.foreground
                      fontFamily: panel.controller.fontFamily
                      onClicked: panel.controller.moveWorkspaceMonitor(String(orderRow.modelData), 1)
                    }
                  }
                }
              }

              ListView {
                id: manualAssignmentList
                visible: String(((panel.controller.draftProfile || {}).workspaces || {}).strategy || "") === "manual"
                width: parent.width
                height: visible ? Math.max(Style.space(90), parent.height - y) : 0
                clip: true
                spacing: Style.space(6)
                boundsBehavior: Flickable.StopAtBounds
                model: visible ? panel.controller.manualWorkspaceRows : []
                currentIndex: panel.controller.workspaceKeyboardIndex >= panel.controller.workspaceListKeyboardStart
                  ? panel.controller.workspaceKeyboardIndex - panel.controller.workspaceListKeyboardStart : -1
                ScrollBar.vertical: ScrollBar {
                  id: manualScrollBar
                  policy: ScrollBar.AsNeeded
                }

                delegate: BorderSurface {
                  id: manualRow
                  required property var modelData
                  required property int index
                  width: manualAssignmentList.width - (manualScrollBar.visible
                    ? manualScrollBar.width + Style.space(4) : 0)
                  height: Style.space(42)
                  readonly property bool hasKeyboardCursor: panel.controller.expanded
                    && panel.controller.activePage === "workspaces"
                    && panel.controller.workspaceKeyboardIndex === panel.controller.workspaceListKeyboardStart + index
                  color: hasKeyboardCursor
                    ? Style.selectedFillFor(panel.controller.foreground, Color.accent)
                    : Qt.rgba(panel.controller.foreground.r, panel.controller.foreground.g, panel.controller.foreground.b, 0.025)
                  borderSpec: Border.controlSpec(hasKeyboardCursor ? "focus" : "normal",
                    panel.controller.foreground, Color.accent)
                  radius: Style.cornerRadius

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(6)
                    spacing: Style.space(6)

                    Text {
                      id: manualWorkspaceLabel
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(82)
                      text: "Workspace " + String(manualRow.modelData.workspace || "?")
                      color: panel.controller.dim
                      font.family: panel.controller.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - manualWorkspaceLabel.width
                        - manualLeft.width - manualRight.width - parent.spacing * 3
                      text: String(manualRow.modelData.display_name || "Display")
                      color: panel.controller.foreground
                      font.family: panel.controller.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: panel.controller.expanded && panel.controller.activePage === "workspaces"
                        && panel.controller.workspaceKeyboardIndex === panel.controller.workspaceListKeyboardStart + manualRow.index
                      elide: Text.ElideRight
                    }

                    Button {
                      id: manualLeft
                      anchors.verticalCenter: parent.verticalCenter
                      text: "←"
                      bordered: true
                      enabled: panel.controller.manualWorkspaceTargetCount > 1 && !panel.controller.editPending
                      foreground: panel.controller.foreground
                      fontFamily: panel.controller.fontFamily
                      onClicked: panel.controller.moveManualWorkspace(manualRow.index, -1)
                    }

                    Button {
                      id: manualRight
                      anchors.verticalCenter: parent.verticalCenter
                      text: "→"
                      bordered: true
                      enabled: panel.controller.manualWorkspaceTargetCount > 1 && !panel.controller.editPending
                      foreground: panel.controller.foreground
                      fontFamily: panel.controller.fontFamily
                      onClicked: panel.controller.moveManualWorkspace(manualRow.index, 1)
                    }
                  }
                }
              }
            }
          }

          Column {
            anchors.left: workspaceSettingsPane.right
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            spacing: Style.space(10)

            EditorPane {
              width: parent.width
              height: Style.space(145)
              title: "Workspace Plan"
              meta: ((panel.controller.draftProfile || {}).workspaces || {}).enabled ? "" : "preview only"
              foreground: panel.controller.foreground
              dim: panel.controller.dim
              accent: Color.accent
              fontFamily: panel.controller.fontFamily

              Column {
                anchors.fill: parent
                spacing: Style.space(5)

                Repeater {
                  model: panel.controller.workspaceRows

                  InfoRow {
                    controller: panel.controller
                    required property var modelData
                    label: String(modelData.name || "Display")
                    value: String(modelData.workspaces || "—")
                    valueAccent: true
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  visible: panel.controller.workspaceRows.length === 0
                  text: "No workspace rules configured"
                  color: panel.controller.dim
                  font.family: panel.controller.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
            }

            EditorPane {
              width: parent.width
              height: parent.height - Style.space(155)
              title: "Monitor Layout"
              foreground: panel.controller.foreground
              dim: panel.controller.dim
              accent: Color.accent
              fontFamily: panel.controller.fontFamily

              DisplayCanvas {
                anchors.fill: parent
                profile: panel.controller.draftProfile
                editorDisplays: panel.controller.editorDocument.displays
                workspacePlan: panel.controller.workspacePlan
                emphasis: "workspaces"
                selectedKey: panel.controller.selectedWorkspaceDisplayKey
                interactive: false
                detailed: true
                framed: false
                foreground: panel.controller.foreground
                dim: panel.controller.dim
                accent: Color.accent
                fontFamily: panel.controller.fontFamily
              }
            }
          }
        }
      }

      BorderSurface {
        id: editorFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(58)
        color: Qt.rgba(panel.controller.foreground.r, panel.controller.foreground.g, panel.controller.foreground.b, 0.025)
        borderSpec: Border.controlSpec(panel.controller.draftDirty || panel.controller.creatingProfile ? "selected" : "normal", panel.controller.foreground, Color.accent)
        radius: Style.cornerRadius
        opacity: panel.controller.managedChecked ? 1.0 : panel.controller.unmanagedOpacity

        Row {
          anchors.fill: parent
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          spacing: Style.space(9)

          Column {
            width: Math.max(Style.space(180), parent.width
              - (activateFooterButton.visible ? activateFooterButton.width + parent.spacing : 0)
              - (discardDraftButton.visible ? discardDraftButton.width + parent.spacing : 0)
              - (saveDraftButton.visible ? saveDraftButton.width + parent.spacing : 0)
              - (profileNameInput.visible ? profileNameInput.width + parent.spacing : 0)
              - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: panel.controller.lastError !== ""
                ? panel.controller.lastError
                : (panel.controller.creatingProfile ? "Creating a profile for this setup"
                  : (panel.controller.draftDirty ? "Unsaved display changes"
                  : (panel.controller.activePage === "profiles"
                    ? (panel.controller.selectedSavedSummary && panel.controller.selectedSavedSummary.active
                      ? "This profile is active"
                      : "Browsing " + panel.controller.selectedSavedProfileName)
                    : "Editing " + panel.controller.profileStatusTitle)))
              color: panel.controller.lastError !== "" ? panel.controller.urgent : panel.controller.foreground
              font.family: panel.controller.fontFamily
              font.pixelSize: Style.font.body
              font.bold: panel.controller.draftDirty
              elide: Text.ElideRight
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: panel.controller.editPending ? "Checking layout…"
                : (panel.controller.creatingProfile ? "Name it, arrange the displays, then preview and save."
                : (panel.controller.activePage === "profiles"
                  ? (panel.controller.profileAutomatic
                    ? "Turn off automatic selection to activate a profile."
                    : "Activation uses a safe 10-second preview.")
                  : "Changes are previewed safely before they can be saved."))
              color: panel.controller.dim
              font.family: panel.controller.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          TextField {
            id: profileNameInput
            visible: panel.controller.creatingProfile || (panel.controller.draftDirty && panel.controller.sourceProfile === "")
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(190)
            text: panel.controller.saveName
            placeholderText: panel.controller.creatingProfile ? "Name this display setup" : "New profile name"
            foreground: panel.controller.foreground
            enabled: panel.controller.managedChecked
            onTextEdited: panel.controller.saveName = text
            onAccepted: panel.controller.previewDraft()
          }

          Button {
            id: activateFooterButton
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.controller.activePage === "profiles"
              && !(panel.controller.selectedSavedSummary && panel.controller.selectedSavedSummary.active)
            text: "Activate"
            selected: enabled
            bordered: true
            enabled: !panel.controller.draftDirty && !!panel.controller.selectedSavedProfile
              && !(panel.controller.selectedSavedSummary && panel.controller.selectedSavedSummary.active)
              && !panel.controller.profileAutomatic && panel.controller.managedChecked
              && panel.controller.previewTransaction === "" && !panel.controller.previewPending
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.activateSelectedSavedProfile()
          }

          Button {
            id: discardDraftButton
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.controller.draftDirty || panel.controller.creatingProfile
            text: "Discard"
            bordered: true
            enabled: !panel.controller.editorLoading && !panel.controller.editPending
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.requestEditorState()
          }

          Button {
            id: saveDraftButton
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.controller.draftDirty || panel.controller.creatingProfile
            text: "Preview & save"
            selected: true
            bordered: true
            enabled: panel.controller.managedChecked && !panel.controller.editPending && !panel.controller.previewPending
              && (panel.controller.sourceProfile !== "" || String(panel.controller.saveName || "").trim() !== "")
            foreground: panel.controller.foreground
            fontFamily: panel.controller.fontFamily
            onClicked: panel.controller.previewDraft()
          }
        }
      }
    }

    KeyboardHelp {
      anchors.fill: parent
      z: 100
      visible: panel.controller.keyboardHelpOpen
      page: panel.controller.activePage
      foreground: panel.controller.foreground
      background: panel.controller.shell.background
      accent: Color.accent
      fontFamily: panel.controller.fontFamily
      onCloseRequested: panel.controller.keyboardHelpOpen = false
    }

    Item {
      anchors.fill: parent
      z: 110
      visible: panel.controller.execEditing

      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.58)

        MouseArea {
          anchors.fill: parent
          onClicked: panel.controller.execEditing = false
        }
      }

      BorderSurface {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(48), Style.space(660))
        height: execContent.implicitHeight + Style.space(30)
        color: panel.controller.shell.background
        borderSpec: Border.controlSpec("focus", panel.controller.foreground, Color.accent)
        radius: Style.cornerRadius

        Column {
          id: execContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(18)
          anchors.rightMargin: Style.space(18)
          spacing: Style.space(10)

          Text {
            textFormat: Text.PlainText
            text: "Edit Exec for " + panel.controller.selectedSavedProfileName
            color: panel.controller.foreground
            font.family: panel.controller.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          TextField {
            id: profileExecInput
            width: parent.width
            text: panel.controller.execDraft
            placeholderText: "/path/to/script.sh"
            foreground: panel.controller.foreground
            onTextEdited: panel.controller.execDraft = text
            onAccepted: panel.controller.commitExecEdit()
            Keys.onEscapePressed: function(event) {
              panel.controller.execEditing = false
              Qt.callLater(function() { keyCatcher.forceActiveFocus() })
              event.accepted = true
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: "Enter saves. Leave empty to clear. Esc discards."
            color: panel.controller.dim
            font.family: panel.controller.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
