pragma ComponentBehavior: Bound

import QtQuick

PopupCard {
    id: root
    popupName: "updates"
    contentWidth: Style.px(380)
    contentHeight: updatesColumn.implicitHeight + padding * 2

    // system.update.sh emits the bar fields plus a structured breakdown.
    property var report: ({})
    property bool checking: false
    signal recheck()

    readonly property var packages: report && report.packages ? report.packages : ({})
    readonly property var errors: report && report.errors ? report.errors : []
    readonly property var groups: {
        const out = []
        for (const source of [["Pacman", "pacman"], ["AUR", "aur"], ["Flatpak", "flatpak"]]) {
            const items = packages[source[1]] || []
            if (items.length) out.push({ label: source[0], source: source[1], items: items })
        }
        return out
    }
    readonly property int total: {
        let sum = 0
        for (const group of groups) sum += group.items.length
        return sum
    }
    readonly property var system: report && report.system ? report.system : ({})
    function ago(epoch) {
        const minutes = Math.round((shell.clock.date.getTime() / 1000 - Number(epoch)) / 60)
        if (!(Number(epoch) > 0)) return ""
        if (minutes >= 1440) return Math.floor(minutes / 1440) + "d ago"
        if (minutes >= 60) return Math.floor(minutes / 60) + "h ago"
        return minutes < 1 ? "just now" : minutes + "m ago"
    }

    Column {
        id: updatesColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero {
            shell: root.shell
            title: root.total > 0 ? root.total + (root.total === 1 ? " package" : " packages") : "Up to date"
            status: root.total > 0
                ? root.groups.map(group => group.items.length + " " + group.label.toLowerCase()).join("  ·  ")
                : "checked " + root.ago(root.system.checked)
        }

        // nothing to list when there is nothing pending, so the panel says what
        // it knows about the system instead of showing an empty card
        Column {
            visible: root.total === 0 && root.errors.length === 0
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "SYSTEM" }
            PopupRow {
                width: parent.width; shell: root.shell
                interactive: false; icon: "󰏗"; title: "Installed packages"; value: String(root.system.installed || "—")
            }
            PopupRow {
                width: parent.width; shell: root.shell
                interactive: false; icon: "󰚰"; title: "Last upgrade"; value: root.ago(root.system.upgraded) || "—"
            }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰑐"; title: "Check now"
                detail: root.checking ? "Checking…" : "Query pacman, AUR and flatpak now"
                active: root.checking
                onClicked: if (!root.checking) root.recheck()
            }
        }

        Repeater {
            model: root.groups
            Column {
                id: groupColumn
                required property var modelData
                width: updatesColumn.width; spacing: Style.xs
                PopupSeparator { shell: root.shell }
                PopupSection { shell: root.shell; text: groupColumn.modelData.label.toUpperCase(); value: groupColumn.modelData.items.length }
                ListView {
                    width: parent.width
                    height: Math.min(contentHeight, Style.px(168))
                    clip: true; spacing: Style.xxs
                    model: groupColumn.modelData.items
                    delegate: Row {
                        id: packageRow
                        required property var modelData
                        width: ListView.view.width; spacing: Style.lg
                        Text {
                            id: name
                            width: parent.width - version.implicitWidth - Style.lg
                            text: packageRow.modelData.name; elide: Text.ElideRight
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                        Text {
                            id: version
                            text: packageRow.modelData.from + " → " + packageRow.modelData.to
                            color: root.shell.alpha(root.shell.foreground, .55)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                    }
                }
                PopupRow {
                    width: parent.width; shell: root.shell
                    icon: ""; title: "Update " + groupColumn.modelData.label; detail: "Opens a terminal"
                    onClicked: {
                        root.shell.closePopup()
                        root.shell.run(["hyprshell", "system/system.update.sh", "up", groupColumn.modelData.source])
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
                icon: ""; title: "Run all upgrades"; detail: "Opens a terminal"
                onClicked: {
                    root.shell.closePopup()
                    root.shell.run(["hyprshell", "system/system.update.sh", "up"])
                }
            }
        }
    }
}
