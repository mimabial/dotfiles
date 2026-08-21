import QtQuick
import Quickshell.Hyprland

// The whole set, since the bar itself only shows the active one.
PopupCard {
    id: root
    popupName: "workspaces"
    contentWidth: 340

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

    Column {
        id: spaceColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: "WORKSPACES · " + root.spaces.length }

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
}
