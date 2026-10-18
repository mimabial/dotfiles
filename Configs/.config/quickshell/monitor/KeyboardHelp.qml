pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons as Commons
import "Ui"

Item {
  id: root

  property string page: "layout"
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property color accent: Commons.Color.accent
  property string fontFamily: Commons.Style.font.family

  signal closeRequested()

  readonly property var groups: {
    var contextual = []
    if (root.page === "layout") {
      contextual = [
        {
          title: "Selected display",
          bindings: [
            { keys: "drag, arrows", action: "Move by 100px" },
            { keys: "Shift+arrows", action: "Move by 10px" },
            { keys: "Ctrl+arrows", action: "Move by 1px" },
            { keys: "Alt+arrows", action: "Snap beside the nearest display" },
            { keys: "0", action: "Move to 0,0" },
            { keys: "[  ]", action: "Select the previous or next display" }
          ]
        },
        {
          title: "Layout",
          bindings: [
            { keys: "Tab, Shift+Tab", action: "Move between canvas, Display, and Color" },
            { keys: "↑  ↓", action: "Select a field in Display or Color" },
            { keys: "←  →", action: "Adjust the selected field" },
            { keys: "Enter", action: "Edit the selected field" }
          ]
        }
      ]
    } else if (root.page === "profiles") {
      contextual = [{
        title: "Selected profile",
        bindings: [
          { keys: "↑  ↓", action: "Browse profiles and their saved setup" },
          { keys: "Enter, a", action: "Apply it in manual profile mode" },
          { keys: "l", action: "Load it into the layout editor" },
          { keys: "e", action: "Edit its exec command" },
          { keys: "d", action: "Delete it" },
          { keys: "Space", action: "Toggle automatic profile selection" }
        ]
      }]
    } else {
      contextual = [{
        title: "Workspaces",
        bindings: [
          { keys: "↑  ↓", action: "Select a setting, workspace, or display" },
          { keys: "←  →", action: "Adjust it, assign a workspace, or reorder displays" },
          { keys: "Enter, Space", action: "Advance the selected setting" }
        ]
      }]
    }
    contextual.push({
      title: "Anywhere",
      bindings: [
        { keys: "1  2  3", action: "Switch tabs" },
        { keys: "a", action: "Apply the current draft or selected profile" },
        { keys: "s", action: "Save the current draft as a profile" },
        { keys: "r", action: "Reset from live Hyprland state" },
        { keys: "?", action: "Show these keys" },
        { keys: "R", action: "Restart the daemon after an upgrade" },
        { keys: "q, Esc", action: "Close the panel" }
      ]
    })
    return contextual
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.58)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  BorderSurface {
    anchors.centerIn: parent
    width: Math.min(parent.width - Commons.Style.space(48), Commons.Style.space(650))
    implicitHeight: helpContent.implicitHeight + Commons.Style.space(30)
    color: root.background
    borderSpec: Commons.Border.controlSpec("focus", root.foreground, root.accent)
    radius: Commons.Style.cornerRadius

    Column {
      id: helpContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Commons.Style.space(18)
      anchors.rightMargin: Commons.Style.space(18)
      spacing: Commons.Style.space(13)

      Text {
        textFormat: Text.PlainText
        text: "Keys"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.subtitle
        font.bold: true
      }

      Repeater {
        model: root.groups

        Column {
          id: bindingGroup
          required property var modelData
          width: helpContent.width
          spacing: Commons.Style.space(4)

          Text {
            textFormat: Text.PlainText
            text: String(parent.modelData.title || "")
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.body
            font.bold: true
          }

          Repeater {
            model: bindingGroup.modelData.bindings || []

            Row {
              required property var modelData
              width: parent.width
              spacing: Commons.Style.space(14)

              Text {
                textFormat: Text.PlainText
                width: Commons.Style.space(150)
                text: String(parent.modelData.keys || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Commons.Style.font.bodySmall
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width - Commons.Style.space(164)
                text: String(parent.modelData.action || "")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Commons.Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        text: "Any key closes this."
        color: Qt.darker(root.foreground, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
      }
    }
  }
}
