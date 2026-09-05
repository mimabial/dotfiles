pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

PopupCard {
    id: root
    popupName: "start"
    contentWidth: Style.px(620)
    contentHeight: startColumn.implicitHeight + padding * 2

    property string filter: ""
    property int selectedIndex: 0
    readonly property bool searching: filter.trim() !== ""
    // everything in the column that is not the pane, so the pane can take what
    // is left of the screen instead of pushing the card off it
    readonly property int chromeHeight: Style.px(30) + Style.sm + padding * 2
    readonly property int usableHeight: root.maxHeight - root.chromeHeight
    readonly property int menuColumnHeight: placesCol.implicitHeight + paneSep.height
        + Style.sm * 2 + menuPane.contentHeight

    // What Hyprland leaves a tiled window on this monitor, so the card lines up
    // with the windows behind it instead of picking a size of its own. The
    // monitor's reserved area, not the bar's own height: a dock or any other
    // exclusive-zone surface takes its cut of the same budget.
    property int reservedVertical: 0
    property int gapsVertical: 0
    property int borderSize: 0
    readonly property int windowHeight: root.anchorWindow && root.anchorWindow.screen
        ? root.anchorWindow.screen.height - root.reservedVertical - root.gapsVertical
            - root.borderSize * 2
        : root.maxHeight
    readonly property int paneHeight: Math.min(root.usableHeight,
        Math.max(Math.round(root.usableHeight * 0.35),
            Math.min(root.windowHeight - root.chromeHeight, root.menuColumnHeight)))

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

    // XDG-derived defaults stay live; places.json only records what the user
    // added on top and which defaults they removed
    property var xdgPlaces: []
    property var addedPlaces: []
    property var hiddenPlaces: []
    readonly property var places: {
        const out = []
        for (const place of xdgPlaces)
            if (hiddenPlaces.indexOf(place.path) < 0) out.push(place)
        return out.concat(addedPlaces)
    }

    property bool addingPlace: false
    property string placeError: ""

    function savePlaces() {
        placesFile.setText(JSON.stringify({added: addedPlaces, hidden: hiddenPlaces}, null, 2) + "\n")
    }
    function expandPath(raw) {
        let path = raw.replace(/^~(?=\/|$)/, shell.home)
        if (path.indexOf("/") !== 0) path = shell.home + "/" + path
        return path.length > 1 ? path.replace(/\/+$/, "") : path
    }
    function beginAddPlace() {
        placeError = ""
        placeField.text = ""
        addingPlace = true
        placeField.forceActiveFocus()
    }
    function cancelAddPlace() {
        addingPlace = false
        placeError = ""
        placeField.text = ""
        searchField.forceActiveFocus()
    }
    function commitPlace() {
        const raw = placeField.text.trim()
        if (raw === "") { cancelAddPlace(); return }
        placeCheck.candidate = expandPath(raw)
        placeCheck.running = true
    }
    function acceptPlace(path) {
        const hides = hiddenPlaces.slice()
        const at = hides.indexOf(path)
        if (at >= 0) hides.splice(at, 1)
        const adds = addedPlaces.slice()
        if (!xdgPlaces.some(p => p.path === path) && !adds.some(p => p.path === path))
            adds.push({icon: "\u{f024b}", label: path.split("/").pop() || path, path: path})
        hiddenPlaces = hides
        addedPlaces = adds
        savePlaces()
        cancelAddPlace()
    }
    // a default is remembered as hidden so it stays gone; an added one just goes
    function removePlace(place) {
        const adds = addedPlaces.slice()
        const at = adds.findIndex(p => p.path === place.path)
        if (at >= 0) { adds.splice(at, 1); addedPlaces = adds }
        else if (hiddenPlaces.indexOf(place.path) < 0)
            hiddenPlaces = hiddenPlaces.concat([place.path])
        savePlaces()
    }

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
    function secondaryAction(item) {
        if (!item) return
        if (item.type === "app") togglePin(item.app)
        else if (item.type === "place") removePlace(item.place)
        else activate(item)
    }
    function moveCursor(step) {
        if (cursorModel.length === 0) return
        selectedIndex = Math.max(0, Math.min(cursorModel.length - 1, selectedIndex + step))
        const list = searching ? resultList : appList
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
    }
    onOpenChanged: {
        searchField.text = ""
        selectedIndex = 0
        addingPlace = false
        placeError = ""
        placeField.text = ""
        menuPane.reset()
        if (open) {
            searchField.forceActiveFocus()
            menuProc.running = true
            geometryProc.running = true
        }
    }
    onFilterChanged: selectedIndex = 0

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
            root.xdgPlaces = out
        }
    }
    property FileView placesFile: FileView {
        path: root.shell.home + "/.config/quickshell/places.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(String(text()))
                root.addedPlaces = Array.isArray(data.added) ? data.added : []
                root.hiddenPlaces = Array.isArray(data.hidden) ? data.hidden : []
            } catch (error) { root.addedPlaces = []; root.hiddenPlaces = [] }
        }
    }
    property Process placeCheck: Process {
        property string candidate: ""
        command: ["test", "-d", candidate]
        onExited: code => code === 0 ? root.acceptPlace(candidate)
            : root.placeError = "Not a directory"
    }
    // --batch emits one blank-line separated chunk per command, and a failed one
    // is a bare non-JSON line, so each chunk is parsed on its own and dispatched
    // on its shape rather than on its position
    function loadGeometry(raw) {
        const screen = root.anchorWindow ? root.anchorWindow.screen : null
        for (const chunk of String(raw).split(/\n\s*\n/)) {
            const text = chunk.trim()
            if (text === "") continue
            let data
            try { data = JSON.parse(text) } catch (error) { continue }
            if (Array.isArray(data)) {
                for (const monitor of data) {
                    if (!screen || monitor.name !== screen.name) continue
                    if (Array.isArray(monitor.reserved) && monitor.reserved.length === 4)
                        root.reservedVertical = monitor.reserved[1] + monitor.reserved[3]
                }
            } else if (data.option === "general:gaps_out" && typeof data.css === "string") {
                const edges = data.css.trim().split(/\s+/).map(Number)
                if (edges.length === 4 && edges.every(n => !isNaN(n)))
                    root.gapsVertical = edges[0] + edges[2]
            } else if (data.option === "general:border_size" && typeof data.int === "number") {
                root.borderSize = data.int
            }
        }
    }
    property Process geometryProc: Process {
        running: true
        command: ["hyprctl", "-j", "--batch",
            "getoption general:gaps_out ; getoption general:border_size ; monitors"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadGeometry(text) }
    }

    property Process menuProc: Process {
        command: ["hyprshell", "rofi/menutree", "--dump-json"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.menus = JSON.parse(text) } catch (error) {}
        } }
    }

    extraGrabWindows: [flyout, flyout2, flyout3, flyout4]

    // flyouts open on hover and would otherwise sit over the pinned/apps side
    // until something else was clicked. The delay only has to outlast the
    // leave/enter gap when the pointer crosses between the two surfaces
    readonly property bool menuChainHovered: menuPane.hovered
        || flyout.hovered || flyout2.hovered || flyout3.hovered || flyout4.hovered
    onMenuChainHoveredChanged: if (root.menuChainHovered) root.flyoutClose.stop(); else root.flyoutClose.restart()
    property Timer flyoutClose: Timer { interval: 10; onTriggered: if (!root.menuChainHovered) menuPane.reset() }

    property StartMenuFlyout flyout: StartMenuFlyout {
        shell: root.shell; menus: root.menus; openLeft: root.position === "right"
        menuId: menuPane.openSubId; anchorItem: menuPane.openRow
        onActionTriggered: target => root.runAction(target)
    }
    property StartMenuFlyout flyout2: StartMenuFlyout {
        shell: root.shell; menus: root.menus; openLeft: root.position === "right"
        menuId: root.flyout.openSubId; anchorItem: root.flyout.openRow
        onActionTriggered: target => root.runAction(target)
    }
    property StartMenuFlyout flyout3: StartMenuFlyout {
        shell: root.shell; menus: root.menus; openLeft: root.position === "right"
        menuId: root.flyout2.openSubId; anchorItem: root.flyout2.openRow
        onActionTriggered: target => root.runAction(target)
    }
    property StartMenuFlyout flyout4: StartMenuFlyout {
        shell: root.shell; menus: root.menus; openLeft: root.position === "right"
        menuId: root.flyout3.openSubId; anchorItem: root.flyout3.openRow
        onActionTriggered: target => root.runAction(target)
    }

    Column {
        id: startColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        Rectangle {
            width: parent.width; height: Style.px(30); radius: root.shell.rounding
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
                height: Style.px(22)
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                placeholderText: "Search apps, actions, places — Enter launches, Esc closes"
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                background: null
                onTextChanged: root.filter = text
                Keys.onDownPressed: root.moveCursor(1)
                Keys.onUpPressed: root.moveCursor(-1)
                Keys.onReturnPressed: root.activate(root.cursorModel[root.selectedIndex])
                Keys.onEnterPressed: root.activate(root.cursorModel[root.selectedIndex])
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
            readonly property bool overflowing: contentHeight > height
            ScrollBar.vertical: PopupScrollBar { shell: root.shell }
            delegate: PopupRow {
                required property var modelData
                required property int index
                width: resultList.width; shell: root.shell
                rightInset: resultList.overflowing ? Style.md : 0
                iconSource: modelData.type === "app" ? Quickshell.iconPath(modelData.app.icon, true) : ""
                icon: modelData.type === "action" ? modelData.entry.icon
                    : modelData.type === "place" ? modelData.place.icon : ""
                title: modelData.type === "app" ? modelData.app.name
                    : modelData.type === "action" ? modelData.entry.path : modelData.place.label
                detail: modelData.type === "app" ? (modelData.app.genericName || modelData.app.comment)
                    : modelData.type === "place" ? modelData.place.path : ""
                value: modelData.type === "app" && root.pinIds.indexOf(modelData.app.id) >= 0 ? "\u{f0403}" : ""
                cursored: index === root.selectedIndex
                onClicked: button => button === Qt.RightButton
                    ? root.secondaryAction(modelData) : root.activate(modelData)
            }
        }

        Row {
            visible: !root.searching
            width: parent.width
            spacing: Style.sectionGap
            // the narrow places/menu column sits away from the bar, so the apps
            // list is the half under the cursor that just came off the button
            layoutDirection: root.position === "right" ? Qt.RightToLeft : Qt.LeftToRight

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
                    readonly property bool overflowing: contentHeight > height
                    ScrollBar.vertical: PopupScrollBar { shell: root.shell }
                    delegate: PopupRow {
                        required property var modelData
                        required property int index
                        width: appList.width; shell: root.shell
                        rightInset: appList.overflowing ? Style.md : 0
                        iconSource: Quickshell.iconPath(modelData.icon, true)
                        title: modelData.name
                        detail: modelData.genericName || modelData.comment
                        value: root.pinIds.indexOf(modelData.id) >= 0 ? "\u{f0403}" : ""
                        cursored: index === root.selectedIndex
                        onClicked: button => button === Qt.RightButton
                            ? root.togglePin(modelData) : root.activate(modelData)
                    }
                }
            }

            Column {
                id: rightPane
                width: Style.px(216)
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
                            implicitHeight: Style.px(24)
                            icon: modelData.icon
                            title: modelData.label
                            // right-click removes; the glyph is the only hint it does
                            value: hovered ? "\u{f0156}" : ""
                            valueColor: root.shell.role("error", root.shell.foreground)
                            onClicked: button => button === Qt.RightButton
                                ? root.removePlace(modelData)
                                : root.activate({type: "place", place: modelData})
                        }
                    }
                    PopupRow {
                        visible: !root.addingPlace
                        width: placesCol.width; shell: root.shell
                        implicitHeight: Style.px(24)
                        icon: "\u{f0415}"
                        iconColor: root.shell.alpha(root.shell.foreground, .55)
                        title: "Add place…"
                        titleColor: root.shell.alpha(root.shell.foreground, .55)
                        onClicked: root.beginAddPlace()
                    }
                    Rectangle {
                        visible: root.addingPlace
                        width: placesCol.width; height: Style.px(24)
                        radius: root.shell.rounding
                        color: root.shell.alpha(root.shell.foreground, .06)
                        border.color: root.placeError !== ""
                            ? root.shell.role("error", root.shell.foreground)
                            : root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
                        TextField {
                            id: placeField
                            anchors.fill: parent
                            anchors.leftMargin: Style.controlPaddingX
                            anchors.rightMargin: Style.controlPaddingX
                            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                            verticalAlignment: TextInput.AlignVCenter
                            placeholderText: "~/path/to/folder"
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                            background: null
                            onTextChanged: root.placeError = ""
                            Keys.onReturnPressed: root.commitPlace()
                            Keys.onEnterPressed: root.commitPlace()
                            Keys.onEscapePressed: root.cancelAddPlace()
                        }
                    }
                    Text {
                        visible: root.placeError !== ""
                        width: placesCol.width
                        text: root.placeError
                        color: root.shell.role("error", root.shell.foreground)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        elide: Text.ElideRight
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

    }
}
