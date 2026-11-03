pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.minimap

PopupCard {
    id: root
    popupName: "workspaces"
    contentWidth: Style.px(340)
    property bool minimap: false
    property string numerals: ""
    property var numeralSets: ({})
    readonly property var settings: MinimapState.settings
    readonly property var toggles: [
        { key: "attention", title: "Attention cues", detail: "Urgent windows and notifications glow" },
        { key: "stateMarkers", title: "State markers", detail: "Mark fullscreen, pinned and floating" },
        { key: "showFloating", title: "Floating windows", detail: "Include floating windows in the map" },
        { key: "boxActions", title: "Box actions", detail: "Right-click menu, middle-click closes" },
        { key: "dragReorder", title: "Drag to reorder", detail: "Right-drag a box to move its column" }
    ]

    readonly property var spaces: {
        const rows = []
        const values = Hyprland.workspaces.values
        for (let i = 0; i < values.length; ++i) {
            const space = values[i]
            if (!space || space.id < 0) continue
            rows.push(space)
        }
        rows.sort((a, b) => a.id - b.id)
        return rows
    }

    function windowsOn(space) {
        const clients = space && space.toplevels ? space.toplevels.values : []
        const names = []
        for (let i = 0; i < clients.length; ++i) {
            const client = clients[i]
            if (!client) continue
            names.push(String(client.title || client.lastIpcObject.class || ""))
        }
        return names
    }

    component Choice: Column {
        id: choice
        required property string title
        required property var choices
        required property string current
        signal picked(string id)
        width: spaceColumn.width; spacing: Style.sm
        PopupSection { shell: root.shell; text: choice.title }
        Row {
            width: parent.width; spacing: Style.sm
            Repeater {
                model: choice.choices
                PopupTab {
                    required property var modelData
                    width: (choice.width - Style.sm * (choice.choices.length - 1)) / choice.choices.length
                    shell: root.shell; text: modelData.label
                    selected: choice.current === modelData.id
                    onClicked: choice.picked(modelData.id)
                }
            }
        }
    }

    Column {
        id: spaceColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "WORKSPACES"; value: root.spaces.length }

            Repeater {
                model: root.spaces
                PopupRow {
                    required property var modelData
                    readonly property var names: root.windowsOn(modelData)
                    width: spaceColumn.width; shell: root.shell
                    icon: modelData.focused ? "\u{f0765}" : "\u{f0766}"
                    title: modelData.name && modelData.name !== String(modelData.id)
                        ? modelData.id + "  " + modelData.name : String(modelData.id)
                    detail: names.length === 0 ? "empty" : names.join("  ·  ")
                    value: names.length > 0 ? String(names.length) : ""
                    active: modelData.focused
                    onClicked: { modelData.activate(); root.shell.closePopup() }
                }
            }
        }

        Choice {
            visible: root.minimap
            title: "LABEL"
            choices: Object.keys(root.numeralSets).map(id => ({ id, label: root.numeralSets[id].slice(0, 2).join(" ") }))
            current: root.numerals
            onPicked: id => root.shell.setModuleProps("workspaces", { numerals: id })
        }
        Choice {
            visible: root.minimap
            title: "ANIMATION"
            choices: MinimapState.animStyles
            current: MinimapState.animStyle
            onPicked: id => MinimapState.setAnimStyle(id)
        }
        Column {
            visible: root.minimap
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "MINIMAP" }
            Repeater {
                model: root.toggles
                PopupToggleRow {
                    required property var modelData
                    width: spaceColumn.width; shell: root.shell
                    title: modelData.title
                    detail: modelData.detail
                    checked: root.settings[modelData.key]
                    onToggled: root.settings[modelData.key] = !checked
                }
            }
        }
    }
}
