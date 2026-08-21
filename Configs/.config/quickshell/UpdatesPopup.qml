import QtQuick

PopupCard {
    id: root
    popupName: "updates"
    contentWidth: 380
    contentHeight: updatesColumn.implicitHeight + padding * 2

    // system.update.sh emits the waybar fields plus a structured breakdown.
    property var report: ({})

    readonly property var packages: report && report.packages ? report.packages : ({})
    readonly property var errors: report && report.errors ? report.errors : []
    readonly property var groups: {
        const out = []
        for (const source of [["PACMAN", "pacman"], ["AUR", "aur"], ["FLATPAK", "flatpak"]]) {
            const items = packages[source[1]] || []
            if (items.length) out.push({ label: source[0], items: items })
        }
        return out
    }
    readonly property int total: {
        let sum = 0
        for (const group of groups) sum += group.items.length
        return sum
    }

    Column {
        id: updatesColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupSection { shell: root.shell; text: "UPDATES" }
        Column {
            width: parent.width; spacing: Style.xxs
            Text {
                width: parent.width
                text: root.total > 0 ? root.total + (root.total === 1 ? " package" : " packages") : "Up to date"
                color: root.shell.foreground; font.family: root.shell.fontFamily
                font.pixelSize: Style.title; font.bold: true
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: root.groups.map(group => group.items.length + " " + group.label.toLowerCase()).join("  ·  ")
                color: root.shell.alpha(root.shell.foreground, .6)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
        }

        Repeater {
            model: root.groups
            Column {
                required property var modelData
                width: updatesColumn.width; spacing: Style.xs
                PopupSeparator { shell: root.shell }
                PopupSection { shell: root.shell; text: modelData.label + "  ·  " + modelData.items.length }
                ListView {
                    width: parent.width
                    height: Math.min(contentHeight, 168)
                    clip: true; spacing: Style.xxs
                    model: modelData.items
                    delegate: Row {
                        required property var modelData
                        width: ListView.view.width; spacing: Style.lg
                        Text {
                            id: name
                            width: parent.width - version.implicitWidth - Style.lg
                            text: modelData.name; elide: Text.ElideRight
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                        Text {
                            id: version
                            text: modelData.from + " → " + modelData.to
                            color: root.shell.alpha(root.shell.foreground, .55)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                    }
                }
            }
        }

        Column {
            visible: root.errors.length > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "CHECK ERRORS" }
            Repeater {
                model: root.errors
                Text {
                    required property var modelData
                    width: updatesColumn.width; text: modelData; wrapMode: Text.Wrap
                    color: root.shell.role("error", root.shell.foreground)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
        }

        Column {
            visible: root.total > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰮯"; title: "Run upgrade"; detail: "Opens a terminal"
                onClicked: {
                    root.shell.closePopup()
                    root.shell.run(["hyprshell", "system/system.update.sh", "up"])
                }
            }
        }
    }
}
