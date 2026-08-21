import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

PopupCard {
    id: root
    popupName: "start"
    contentWidth: 620
    contentHeight: startColumn.implicitHeight + padding * 2

    property string filter: ""
    property int cursorIndex: 0
    readonly property bool searching: filter.trim() !== ""
    readonly property int paneHeight: 420

    readonly property var allApps: {
        const out = []
        const all = DesktopEntries.applications.values
        for (let i = 0; i < all.length; ++i) {
            const app = all[i]
            if (!app || app.noDisplay) continue
            out.push(app)
        }
        out.sort((a, b) => a.name.localeCompare(b.name))
        return out
    }

    property var pinIds: []
    readonly property var pinnedApps: {
        const out = []
        for (const id of pinIds) {
            const app = DesktopEntries.byId(id)
            if (app) out.push(app)
        }
        return out
    }
    function togglePin(app) {
        const ids = pinIds.slice()
        const at = ids.indexOf(app.id)
        if (at >= 0) ids.splice(at, 1); else ids.push(app.id)
        pinIds = ids
        pinsFile.setText(JSON.stringify(ids, null, 2) + "\n")
    }

    property var places: []
    property var menus: ({})

    function labelIcon(label) { const m = label.match(/^(\S+)\s{2,}/); return m ? m[1] : "" }
    function labelText(label) { const m = label.match(/^\S+\s{2,}(.*)$/); return m ? m[1] : label }
    function flattenMenu(menuId, prefix, out, seen) {
        const menu = menus[menuId]
        if (!menu || seen.indexOf(menuId) >= 0) return out
        seen.push(menuId)
        for (const item of menu.items) {
            if (!item.searchable) continue
            const path = prefix === "" ? labelText(item.label) : prefix + " › " + labelText(item.label)
            if (item.kind === "submenu") flattenMenu(item.target, path, out, seen)
            else out.push({icon: labelIcon(item.label), path: path, target: item.target})
        }
        return out
    }

    readonly property var results: {
        if (!searching) return []
        const needle = filter.trim().toLowerCase()
        const out = []
        for (const app of allApps) {
            const hay = (app.name + " " + app.genericName + " " + app.comment + " " + app.keywords).toLowerCase()
            if (hay.indexOf(needle) >= 0) out.push({type: "app", app: app})
        }
        for (const entry of flattenMenu("main", "", [], [])) {
            if (entry.path.toLowerCase().indexOf(needle) >= 0) out.push({type: "action", entry: entry})
        }
        for (const place of places) {
            if (place.label.toLowerCase().indexOf(needle) >= 0) out.push({type: "place", place: place})
        }
        return out
    }
    readonly property var cursorModel: searching ? results : allApps

    readonly property var session: [
        {label: "Lock",     icon: "\u{f033e}", run: ["hyprshell", "lock-screen.sh"]},
        {label: "Suspend",  icon: "\u{f04b2}", run: ["systemctl", "suspend"]},
        {label: "Log out",  icon: "\u{f0343}", run: ["hyprshell", "logout-launch.sh", "1"]},
        {label: "Reboot",   icon: "\u{f0709}", run: ["systemctl", "reboot"]},
        {label: "Shutdown", icon: "\u{f0425}", run: ["systemctl", "poweroff"]}
    ]

    function runAction(target) {
        shell.run(["hyprshell", "rofi/menutree", "--action", target])
        shell.closePopup()
    }
    function activate(item) {
        if (!item) return
        if (item.type === "action") {
            runAction(item.entry.target)
            return
        }
        if (item.type === "place") {
            shell.run(["xdg-open", item.place.path])
            shell.closePopup()
            return
        }
        const app = item.type === "app" ? item.app : item
        app.execute()
        shell.closePopup()
    }
    function moveCursor(step) {
        if (cursorModel.length === 0) return
        cursorIndex = Math.max(0, Math.min(cursorModel.length - 1, cursorIndex + step))
        const list = searching ? resultList : appList
        list.positionViewAtIndex(cursorIndex, ListView.Contain)
    }
    onOpenChanged: {
        searchField.text = ""
        cursorIndex = 0
        menuPane.reset()
        if (open) {
            searchField.forceActiveFocus()
            menuProc.running = true
        }
    }
    onFilterChanged: cursorIndex = 0

    property FileView pinsFile: FileView {
        path: root.shell.home + "/.config/quickshell/pins.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.pinIds = JSON.parse(String(text())) } catch (error) { root.pinIds = [] }
        }
    }
    property FileView userDirsFile: FileView {
        path: root.shell.home + "/.config/user-dirs.dirs"
        printErrors: false
        onLoaded: {
            const icons = ({DOWNLOAD: "\u{f01da}", DOCUMENTS: "\u{f0219}", PICTURES: "\u{f024f}", MUSIC: "\u{f0388}", VIDEOS: "\u{f0567}", PROJECTS: "\u{f0b8b}"})
            const dirs = {}
            for (const line of String(text()).split("\n")) {
                const m = line.match(/^XDG_([A-Z]+)_DIR="(.*)"$/)
                if (m) dirs[m[1]] = m[2].replace("$HOME", root.shell.home)
            }
            const out = [{icon: "\u{f02dc}", label: "Home", path: root.shell.home}]
            for (const key of ["DOWNLOAD", "DOCUMENTS", "PICTURES", "MUSIC", "VIDEOS", "PROJECTS"]) {
                const dir = dirs[key]
                if (!dir || !icons[key] || dir === root.shell.home || dir === root.shell.home + "/") continue
                out.push({icon: icons[key], label: dir.split("/").pop(), path: dir})
            }
            root.places = out
        }
    }
    property Process menuProc: Process {
        command: ["hyprshell", "rofi/menutree", "--dump-json"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.menus = JSON.parse(text) } catch (error) {}
        } }
    }

    extraGrabWindows: [sessionTip, flyout, flyout2, flyout3, flyout4]

    property StartMenuFlyout flyout: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: menuPane.openSubId; anchorItem: menuPane.openRow
        onActionTriggered: target => root.runAction(target)
    }
    property StartMenuFlyout flyout2: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout.openSubId; anchorItem: root.flyout.openRow
        onActionTriggered: target => root.runAction(target)
    }
    property StartMenuFlyout flyout3: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout2.openSubId; anchorItem: root.flyout2.openRow
        onActionTriggered: target => root.runAction(target)
    }
    property StartMenuFlyout flyout4: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout3.openSubId; anchorItem: root.flyout3.openRow
        onActionTriggered: target => root.runAction(target)
    }

    property Item tipRow: null
    property string tipText: ""
    property BarTooltip sessionTip: BarTooltip {
        shell: root.shell
        anchorItem: root.tipRow
        text: root.tipText
        hovered: root.tipRow !== null
    }

    Column {
        id: startColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        Rectangle {
            width: parent.width; height: 30; radius: root.shell.rounding
            color: root.shell.alpha(root.shell.foreground, .06)
            border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
            Text {
                id: searchGlyph
                anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0349}"
                color: root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            TextField {
                id: searchField
                anchors.left: searchGlyph.right; anchors.leftMargin: Style.xs
                anchors.right: countText.left; anchors.rightMargin: Style.xs
                anchors.verticalCenter: parent.verticalCenter
                height: 22
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                placeholderText: "Search apps, actions, places — Enter launches, Esc closes"
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                background: null
                onTextChanged: root.filter = text
                Keys.onDownPressed: root.moveCursor(1)
                Keys.onUpPressed: root.moveCursor(-1)
                Keys.onReturnPressed: root.activate(root.cursorModel[root.cursorIndex])
                Keys.onEnterPressed: root.activate(root.cursorModel[root.cursorIndex])
            }
            Text {
                id: countText
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: root.cursorModel.length
                color: root.shell.alpha(root.shell.foreground, .4)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
        }

        ListView {
            id: resultList
            visible: root.searching
            width: parent.width; height: root.paneHeight
            clip: true; spacing: 2
            model: root.results
            delegate: PopupRow {
                required property var modelData
                required property int index
                width: resultList.width; shell: root.shell
                iconSource: modelData.type === "app" ? Quickshell.iconPath(modelData.app.icon, true) : ""
                icon: modelData.type === "action" ? modelData.entry.icon
                    : modelData.type === "place" ? modelData.place.icon : ""
                title: modelData.type === "app" ? modelData.app.name
                    : modelData.type === "action" ? modelData.entry.path : modelData.place.label
                detail: modelData.type === "app" ? (modelData.app.genericName || modelData.app.comment)
                    : modelData.type === "place" ? modelData.place.path : ""
                value: modelData.type === "app" && root.pinIds.indexOf(modelData.app.id) >= 0 ? "\u{f0403}" : ""
                cursored: index === root.cursorIndex
                onClicked: button => modelData.type === "app" && button === Qt.RightButton
                    ? root.togglePin(modelData.app) : root.activate(modelData)
            }
        }

        Row {
            visible: !root.searching
            width: parent.width
            spacing: Style.sectionGap

            Column {
                width: parent.width - rightPane.width - parent.spacing
                spacing: Style.sm
                StartPinnedGrid {
                    id: pinnedGrid
                    width: parent.width
                    shell: root.shell
                    apps: root.pinnedApps
                    onLaunched: app => root.activate(app)
                    onUnpinned: app => root.togglePin(app)
                }
                PopupSection { id: appsHeader; shell: root.shell; text: "ALL APPS" }
                ListView {
                    id: appList
                    width: parent.width
                    height: root.paneHeight - appsHeader.height - Style.sm
                        - (pinnedGrid.visible ? pinnedGrid.height + Style.sm : 0)
                    clip: true; spacing: 2
                    model: root.allApps
                    delegate: PopupRow {
                        required property var modelData
                        required property int index
                        width: appList.width; shell: root.shell
                        iconSource: Quickshell.iconPath(modelData.icon, true)
                        title: modelData.name
                        detail: modelData.genericName || modelData.comment
                        value: root.pinIds.indexOf(modelData.id) >= 0 ? "\u{f0403}" : ""
                        cursored: index === root.cursorIndex
                        onClicked: button => button === Qt.RightButton
                            ? root.togglePin(modelData) : root.activate(modelData)
                    }
                }
            }

            Column {
                id: rightPane
                width: 216
                spacing: Style.sm
                Column {
                    id: placesCol
                    width: parent.width
                    spacing: Style.xxs
                    PopupSection { shell: root.shell; text: "PLACES" }
                    Repeater {
                        model: root.places
                        PopupRow {
                            required property var modelData
                            width: placesCol.width; shell: root.shell
                            implicitHeight: 24
                            icon: modelData.icon
                            title: modelData.label
                            onClicked: root.activate({type: "place", place: modelData})
                        }
                    }
                }
                PopupSeparator { id: paneSep; shell: root.shell }
                StartMenuPane {
                    id: menuPane
                    width: parent.width
                    shell: root.shell
                    menus: root.menus
                    totalHeight: root.paneHeight - placesCol.height - paneSep.height - Style.sm * 2
                    onAction: target => root.runAction(target)
                }
            }
        }

        PopupSeparator { shell: root.shell }

        Item {
            width: parent.width
            height: sessionRow.implicitHeight
            Row {
                id: sessionRow
                anchors.left: parent.left
                spacing: Style.xs
                Repeater {
                    model: root.session
                    PopupRow {
                        id: sessionButton
                        required property var modelData
                        width: Style.controlHeight * 2
                        shell: root.shell
                        centerTitle: true
                        title: modelData.icon
                        onHoveredChanged: {
                            if (hovered) { root.tipRow = sessionButton; root.tipText = modelData.label }
                            else if (root.tipRow === sessionButton) root.tipRow = null
                        }
                        onClicked: { root.shell.run(modelData.run); root.shell.closePopup() }
                    }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.xs
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0004}"
                    color: root.shell.alpha(root.shell.foreground, .5)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.subtitle
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        const user = Quickshell.env("USER") || ""
                        return user.charAt(0).toUpperCase() + user.slice(1)
                    }
                    color: root.shell.alpha(root.shell.foreground, .75)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
            }
        }
    }
}
