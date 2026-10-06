pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "StartMenuModel.js" as StartMenuModel

PopupCard {
    id: root
    property string activePopupName: "start"
    popupName: activePopupName
    Binding on activePopupName {
        when: root.shell.popupName === "start" || root.shell.popupName === "spotlight"
        value: root.shell.popupName
        restoreMode: Binding.RestoreNone
    }
    keyboardHint: spotlight ? ""
        : placeEditorOpen ? "Enter save place · Esc cancel"
        : browseOnly ? "↑↓ move · Enter open · Esc close" : "Type to search · ↑↓ move · Enter open · Esc close"
    wantsKeyboard: true
    contentWidth: spotlight ? Style.spotlightWidth : Style.px(620)
    contentHeight: layoutColumn.implicitHeight + padding * 2
    padding: spotlight ? 0 : Style.popupPadding
    centeredHeight: spotlight ? spotlightChromeHeight + Style.spotlightListHeight : cardHeight

    property string searchQuery: ""
    property var recentFiles: []
    property var indexedDocuments: []
    readonly property bool spotlight: popupName === "spotlight"
    readonly property bool browseOnly: shell.mode === "winbar" && !spotlight
    property int selectedEntryIndex: 0
    readonly property bool searchActive: searchQuery.trim() !== ""
    readonly property int fixedContentHeight: (browseOnly ? 0 : searchHeader.height + layoutColumn.spacing) + padding * 2
    readonly property int availableContentHeight: root.maxHeight - root.fixedContentHeight
    readonly property int desiredBrowseHeight: Math.max(placesColumn.implicitHeight + paneSeparator.height
        + Style.sm * 2 + menuPane.contentHeight, applicationList.y + Style.popupRowHeight)

    // What Hyprland leaves a tiled window on this monitor, so the card lines up
    // with the windows behind it instead of picking a size of its own. The
    // monitor's reserved area, not the bar's own height: a dock or any other
    // exclusive-zone surface takes its cut of the same budget.
    property int reservedScreenHeight: 0
    property int outerGapHeight: 0
    property int windowBorderWidth: 0
    readonly property int tiledWindowHeight: root.anchorWindow && root.anchorWindow.screen
        ? root.anchorWindow.screen.height - root.reservedScreenHeight - root.outerGapHeight
            - root.windowBorderWidth * 2
        : root.maxHeight
    readonly property int contentPaneHeight: Math.min(root.availableContentHeight,
        Math.max(Math.round(root.availableContentHeight * 0.35),
            Math.min(root.tiledWindowHeight - root.fixedContentHeight, root.desiredBrowseHeight)))

    readonly property var availableApplications: StartMenuModel.applications(DesktopEntries.applications.values)

    property var pinnedApplicationIds: []
    readonly property var pinnedApplications: {
        const out = []
        for (const id of pinnedApplicationIds) {
            const app = DesktopEntries.byId(id)
            if (app) out.push(app)
        }
        return out
    }
    function toggleApplicationPin(app) {
        const ids = pinnedApplicationIds.slice()
        const at = ids.indexOf(app.id)
        if (at >= 0) ids.splice(at, 1); else ids.push(app.id)
        pinnedApplicationIds = ids
        pinsConfigFile.setText(JSON.stringify(ids, null, 2) + "\n")
    }

    // XDG-derived defaults stay live; places.json only records what the user
    // added on top and which defaults they removed
    property var defaultPlaces: []
    property var customPlaces: []
    property var hiddenDefaultPaths: []
    readonly property var places: StartMenuModel.places(defaultPlaces, hiddenDefaultPaths, customPlaces)

    property bool placeEditorOpen: false
    property string placeEditorError: ""

    function savePlacePreferences() {
        placesConfigFile.setText(JSON.stringify({added: customPlaces, hidden: hiddenDefaultPaths}, null, 2) + "\n")
    }
    function openPlaceEditor() {
        placeEditorError = ""
        placeField.text = ""
        placeEditorOpen = true
        placeField.forceActiveFocus()
    }
    function closePlaceEditor() {
        placeEditorOpen = false
        placeEditorError = ""
        placeField.text = ""
        if (browseOnly) resumeKeyboard(); else searchField.forceActiveFocus()
    }
    function validatePlaceInput() {
        const raw = placeField.text.trim()
        if (raw === "") { closePlaceEditor(); return }
        directoryValidationProcess.candidate = StartMenuModel.resolvePath(raw, shell.home)
        directoryValidationProcess.running = true
    }
    function addPlace(path) {
        const hides = hiddenDefaultPaths.slice()
        const at = hides.indexOf(path)
        if (at >= 0) hides.splice(at, 1)
        const adds = customPlaces.slice()
        if (!defaultPlaces.some(p => p.path === path) && !adds.some(p => p.path === path))
            adds.push({icon: "\u{f024b}", label: path.split("/").pop() || path, path: path})
        hiddenDefaultPaths = hides
        customPlaces = adds
        savePlacePreferences()
        closePlaceEditor()
    }
    // a default is remembered as hidden so it stays gone; an added one just goes
    function removePlace(place) {
        const adds = customPlaces.slice()
        const at = adds.findIndex(p => p.path === place.path)
        if (at >= 0) { adds.splice(at, 1); customPlaces = adds }
        else if (hiddenDefaultPaths.indexOf(place.path) < 0)
            hiddenDefaultPaths = hiddenDefaultPaths.concat([place.path])
        savePlacePreferences()
    }
    function removeRecentFile(uri) {
        if (recentRemovalProcess.running) return
        recentRemovalProcess.uri = uri
        recentRemovalProcess.running = true
    }

    property var menus: ({})

    readonly property var searchIndex: StartMenuModel.searchIndex(availableApplications, menus, places, spotlight ? recentFiles : [])
    readonly property var searchResults: {
        const results = StartMenuModel.search(searchQuery, searchIndex, indexedDocuments)
        if (spotlight && searchActive) results.push({type: "fileSearch", query: searchQuery.trim()})
        return results
    }
    readonly property var browseEntries: browseOnly
        ? recentFiles.map(file => ({type: "file", file: file})).concat(availableApplications)
        : availableApplications
    readonly property var selectableEntries: searchActive ? searchResults : browseEntries
    readonly property var selectedEntry: selectableEntries[selectedEntryIndex]

    readonly property int spotlightChromeHeight: Style.spotlightSearchHeight + Style.xl * 2
        + Style.popupRowHeight + searchRule.height + footerRule.height
    readonly property int spotlightGutter: Style.xl + Style.controlPaddingX
    readonly property var spotlightKinds: ({
        app: {section: "Applications", kind: "Application", verb: "Open"},
        action: {section: "Commands", kind: "Command", verb: "Run"},
        place: {section: "Places", kind: "Place", verb: "Open"},
        file: {section: "Files", kind: "File", verb: "Open"},
        fileSearch: {section: "Files", kind: "File Finder", verb: "Search"}
    })
    readonly property var spotlightHeadings: searchResults.map((item, index) => {
        const section = spotlightKinds[item.type].section
        return index > 0 && spotlightKinds[searchResults[index - 1].type].section === section ? "" : section
    })
    readonly property int spotlightListHeight: Math.max(0, Math.min(
        searchResults.length * Style.popupRowHeight + spotlightHeadings.filter(Boolean).length * Style.spotlightSectionHeight,
        Style.spotlightListHeight, maxHeight - spotlightChromeHeight))
    function tildePath(path) {
        return path.startsWith(shell.home) ? "~" + path.slice(shell.home.length) : path
    }
    function spotlightEntry(item) {
        const row = (title, detail, icon, iconSource = "", checked = false) => ({title, detail, icon, iconSource, checked})
        switch (item.type) {
        case "app": return row(item.app.name, item.app.genericName || item.app.comment, "", Quickshell.iconPath(item.app.icon, true))
        case "action": return row(item.entry.label, item.entry.parent, item.entry.icon, "",
            (shell.menuTargetActive(item.entry.target) ?? item.entry.checked) === true)
        case "place": return row(item.place.label, tildePath(item.place.path), item.place.icon)
        case "file": return row(item.file.text, tildePath(StartMenuModel.filePath(item.file.uri).replace(/\/[^/]*$/, "")),
            item.file.folder ? "\u{f024b}" : "\u{f0219}")
        }
        return row("Find more files for “" + item.query + "”…", "", "\u{f0349}")
    }
    function secondaryLabel(item) {
        return !item ? ""
            : item.type === "app" ? (pinnedApplicationIds.includes(item.app.id) ? "Unpin" : "Pin")
            : item.type === "place" ? "Remove" : ""
    }
    property var lastPointer: null
    function followPointer(index, position) {
        const moved = lastPointer !== null && (position.x !== lastPointer.x || position.y !== lastPointer.y)
        lastPointer = position
        if (moved) { selectedEntryIndex = index; holdSelection() }
    }
    property var heldSelection: null
    function selectionKey(result) { return result?.app ?? result?.entry ?? result?.place ?? result?.file ?? result?.type }
    function holdSelection() { if (searchActive) heldSelection = {query: searchQuery, key: selectionKey(selectedEntry)} }
    function bestMatchIndex() {
        return searchResults.reduce((best, result, index) => (result.score ?? 0) > (searchResults[best].score ?? 0) ? index : best, 0)
    }
    onSearchResultsChanged: if (searchActive) {
        const held = heldSelection?.query === searchQuery
            ? searchResults.findIndex(result => selectionKey(result) === heldSelection.key) : -1
        selectedEntryIndex = held >= 0 ? held : bestMatchIndex()
        Qt.callLater(revealSelection)
    }

    function searchDocuments() {
        indexedDocuments = []
        if (!open || !searchActive || documentSearchProcess.running) return
        documentSearchProcess.query = searchQuery.trim()
        documentSearchProcess.running = true
    }

    function runMenuAction(target) {
        shell.run(["hyprshell", "rofi/menutree", "--action", target])
        shell.closePopup()
    }
    function activateEntry(item) {
        if (!item) return
        if (item.type === "action") {
            runMenuAction(item.entry.target)
            return
        }
        if (item.type === "place") {
            shell.run(["xdg-open", item.place.path])
            shell.closePopup()
            return
        }
        if (item.type === "file") {
            shell.run(["xdg-open", item.file.uri])
            shell.closePopup()
            return
        }
        if (item.type === "fileSearch") {
            shell.run([shell.home + "/.local/lib/hypr/launch/file-finder.sh", item.query])
            shell.closePopup()
            return
        }
        const app = item.type === "app" ? item.app : item
        app.execute()
        shell.closePopup()
    }
    function activateSecondaryEntry(item) {
        if (!item) return
        if (item.type === "app") toggleApplicationPin(item.app)
        else if (item.type === "place") removePlace(item.place)
        else activateEntry(item)
    }
    function activateSelection(event) {
        if (event.modifiers & Qt.ShiftModifier) activateSecondaryEntry(selectedEntry); else activateEntry(selectedEntry)
    }
    function moveSelection(step) {
        if (selectableEntries.length === 0) return
        selectedEntryIndex = Math.max(0, Math.min(selectableEntries.length - 1, selectedEntryIndex + step))
        holdSelection()
        revealSelection()
    }
    function revealSelection() {
        if (searchActive) (spotlight ? spotlightList : searchResultList).positionViewAtIndex(selectedEntryIndex, ListView.Contain)
        else if (browseOnly && selectedEntryIndex < recentFiles.length)
            recentList.positionViewAtIndex(selectedEntryIndex, ListView.Contain)
        else applicationList.positionViewAtIndex(selectedEntryIndex - (browseOnly ? recentFiles.length : 0), ListView.Contain)
    }
    function typeKey(event, field) {
        if (event.key === Qt.Key_Backspace) { field.text = field.text.slice(0, -1); return true }
        if (event.text && event.text.length === 1 && event.text >= " "
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            field.text += event.text; return true
        }
        return false
    }
    function handleKey(event) {
        if (placeEditorOpen) {
            if (event.key === Qt.Key_Escape) { closePlaceEditor(); return true }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { validatePlaceInput(); return true }
            return typeKey(event, placeField)
        }
        if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) { moveSelection(event.key === Qt.Key_Down ? 1 : -1); return true }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activateSelection(event); return true }
        return browseOnly ? defaultKey(event) : typeKey(event, searchField) || defaultKey(event)
    }
    onOpenChanged: {
        searchField.text = ""
        selectedEntryIndex = browseOnly ? -1 : 0
        lastPointer = null
        heldSelection = null
        placeEditorOpen = false
        placeEditorError = ""
        placeField.text = ""
        menuPane.reset()
        if (open) {
            if (browseOnly) resumeKeyboard(); else searchField.forceActiveFocus()
            menuTreeProcess.running = true
            if (spotlight || browseOnly) recentFilesProcess.running = true
            windowGeometryProcess.running = true
            shell.refreshMenuState()
        }
    }
    onSearchQueryChanged: { if (!searchActive) selectedEntryIndex = 0; searchDocuments() }
    onSpotlightChanged: {
        searchDocuments()
        if (open && shell.mode === "winbar") {
            searchField.text = ""
            selectedEntryIndex = browseOnly ? -1 : 0
            placeEditorOpen = false
            placeEditorError = ""
            placeField.text = ""
            menuPane.reset()
            if (spotlight) {
                searchField.forceActiveFocus()
                recentFilesProcess.running = true
            } else resumeKeyboard()
        }
    }

    property FileView pinsConfigFile: FileView {
        path: root.shell.home + "/.config/quickshell/pins.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.pinnedApplicationIds = JSON.parse(String(text())) } catch (error) { root.pinnedApplicationIds = [] }
        }
    }
    property FileView xdgUserDirectoriesFile: FileView {
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
            root.defaultPlaces = out
        }
    }
    property FileView placesConfigFile: FileView {
        path: root.shell.home + "/.config/quickshell/places.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const data = JSON.parse(String(text()))
                root.customPlaces = Array.isArray(data.added) ? data.added : []
                root.hiddenDefaultPaths = Array.isArray(data.hidden) ? data.hidden : []
            } catch (error) { root.customPlaces = []; root.hiddenDefaultPaths = [] }
        }
    }
    property Process directoryValidationProcess: Process {
        property string candidate: ""
        command: ["test", "-d", candidate]
        onExited: code => code === 0 ? root.addPlace(candidate)
            : root.placeEditorError = "Not a directory"
    }
    // --batch emits one blank-line separated chunk per command, and a failed one
    // is a bare non-JSON line, so each chunk is parsed on its own and dispatched
    // on its shape rather than on its position
    function applyWindowGeometry(raw) {
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
                        root.reservedScreenHeight = monitor.reserved[1] + monitor.reserved[3]
                }
            } else if (data.option === "general:gaps_out" && typeof data.css === "string") {
                const edges = data.css.trim().split(/\s+/).map(Number)
                if (edges.length === 4 && edges.every(n => !isNaN(n)))
                    root.outerGapHeight = edges[0] + edges[2]
            } else if (data.option === "general:border_size" && typeof data.int === "number") {
                root.windowBorderWidth = data.int
            }
        }
    }
    property Process windowGeometryProcess: Process {
        running: true
        command: ["hyprctl", "-j", "--batch",
            "getoption general:gaps_out ; getoption general:border_size ; monitors"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyWindowGeometry(text) }
    }

    property Process menuTreeProcess: Process {
        command: ["hyprshell", "rofi/menutree", "--dump-json"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.menus = JSON.parse(text) } catch (error) {}
        } }
    }
    property Process recentFilesProcess: Process {
        command: ["python3", root.shell.home + "/.local/lib/hypr/quickshell/recent-items.py"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.recentFiles = JSON.parse(text) }
    }
    property Process recentRemovalProcess: Process {
        property string uri: ""
        command: ["python3", root.shell.home + "/.local/lib/hypr/quickshell/recent-items.py", "remove", uri]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.recentFiles = JSON.parse(text) }
    }
    property Process documentSearchProcess: Process {
        property string query: ""
        command: ["sh", "-c", 'baloosearch6 -d "$1" -- "$2" | xargs -rd "\\n" ls -1dp -- 2>/dev/null', "sh",
            root.shell.home + "/Documents", query.split(/\s+/).map(term => "filename:" + term).join(" ")]
        stdout: StdioCollector { id: documentSearchOutput; waitForEnd: true }
        onExited: {
            if (root.open && query === root.searchQuery.trim())
                root.indexedDocuments = String(documentSearchOutput.text).split("\n")
                    .filter(line => line.startsWith(root.shell.home + "/Documents/"))
                    .map(line => {
                        const path = line.replace(/\/$/, "")
                        return {text: path.split("/").pop(), uri: path, folder: path !== line}
                    })
            else if (root.open && root.searchActive && query !== root.searchQuery.trim())
                Qt.callLater(root.searchDocuments)
        }
    }

    extraGrabWindows: [flyout, flyout2, flyout3, flyout4]

    readonly property bool menuChainHovered: menuPane.hovered
        || flyout.hovered || flyout2.hovered || flyout3.hovered || flyout4.hovered
    onMenuChainHoveredChanged: if (root.menuChainHovered) root.menuCloseDelay.stop(); else root.menuCloseDelay.restart()
    property Timer menuCloseDelay: Timer { interval: Style.hoverDuration; onTriggered: if (!root.menuChainHovered) menuPane.reset() }

    property StartMenuFlyout flyout: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: menuPane.openSubId; anchorItem: menuPane.openRow
        onActionTriggered: target => root.runMenuAction(target)
        onDismissed: menuPane.reset()
    }
    property StartMenuFlyout flyout2: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout.openSubId; anchorItem: root.flyout.openRow
        onActionTriggered: target => root.runMenuAction(target)
        onDismissed: root.flyout.closeSubmenu()
    }
    property StartMenuFlyout flyout3: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout2.openSubId; anchorItem: root.flyout2.openRow
        onActionTriggered: target => root.runMenuAction(target)
        onDismissed: root.flyout2.closeSubmenu()
    }
    property StartMenuFlyout flyout4: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout3.openSubId; anchorItem: root.flyout3.openRow
        onActionTriggered: target => root.runMenuAction(target)
        onDismissed: root.flyout3.closeSubmenu()
    }

    Column {
        id: layoutColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: root.spotlight ? 0 : Style.sm

        Rectangle {
            id: searchHeader
            visible: !root.browseOnly
            readonly property int textSize: root.spotlight ? Style.display : Style.bodySmall
            width: parent.width; height: root.spotlight ? Style.spotlightSearchHeight : Style.controlHeight
            radius: root.shell.rounding
            color: root.spotlight ? "transparent" : root.shell.alpha(root.shell.foreground, .06)
            border.color: root.spotlight ? "transparent" : root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
            Text {
                id: searchGlyph
                anchors.left: parent.left; anchors.leftMargin: root.spotlight ? root.spotlightGutter : Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0349}"
                color: root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: searchHeader.textSize
            }
            TextField {
                id: searchField
                anchors.left: searchGlyph.right; anchors.leftMargin: root.spotlight ? Style.xl : Style.xs
                anchors.right: root.spotlight ? parent.right : countText.left
                anchors.rightMargin: root.spotlight ? root.spotlightGutter : Style.xs
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                placeholderText: root.spotlight ? "Search apps, actions, places, recent files, documents" : "Search apps, actions, places, documents"
                Binding on placeholderTextColor { when: root.spotlight; value: root.shell.faintText }
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: searchHeader.textSize
                background: null
                onTextChanged: root.searchQuery = text
                Keys.onDownPressed: root.moveSelection(1)
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onReturnPressed: event => root.activateSelection(event)
                Keys.onEnterPressed: event => root.activateSelection(event)
            }
            Text {
                id: countText
                visible: !root.spotlight
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: root.selectableEntries.length
                color: root.shell.faintText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
        }

        Column {
            visible: root.spotlight && root.searchActive
            width: parent.width
            PopupSeparator { id: searchRule; shell: root.shell; x: Style.xl; width: parent.width - Style.xl * 2 }
            Item {
                width: parent.width; height: root.spotlightListHeight + Style.xl * 2
                ListView {
                    id: spotlightList
                    anchors.fill: parent; anchors.topMargin: Style.xl; anchors.bottomMargin: Style.xl
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    model: root.spotlight ? root.searchResults : []
                    ScrollBar.vertical: PopupScrollBar { shell: root.shell }
                    delegate: SpotlightRow {
                        required property var modelData
                        required property int index
                        readonly property var entry: root.spotlightEntry(modelData)
                        width: spotlightList.width; shell: root.shell
                        section: root.spotlightHeadings[index] ?? ""
                        icon: entry.icon; iconSource: entry.iconSource
                        title: entry.title; detail: entry.detail
                        kind: modelData.file?.folder ? "Folder" : root.spotlightKinds[modelData.type].kind
                        cursored: index === root.selectedEntryIndex
                        checked: entry.checked
                        onPointerMoved: position => root.followPointer(index, position)
                        onClicked: button => button === Qt.RightButton
                            ? root.activateSecondaryEntry(modelData) : root.activateEntry(modelData)
                    }
                }
            }
            PopupSeparator { id: footerRule; shell: root.shell; x: Style.xl; width: parent.width - Style.xl * 2 }
            Item {
                width: parent.width; height: Style.popupRowHeight
                Text {
                    anchors.left: parent.left; anchors.leftMargin: root.spotlightGutter
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.searchResults.length + (root.searchResults.length === 1 ? " result" : " results")
                    color: root.shell.faintText
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: root.spotlightGutter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.xxxl
                    Text {
                        visible: text !== ""
                        text: root.searchActive && root.selectedEntry ? "↵  " + root.spotlightKinds[root.selectedEntry.type].verb : ""
                        color: root.shell.mutedText
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                    Text {
                        readonly property string label: root.secondaryLabel(root.selectedEntry)
                        visible: label !== ""
                        text: "⇧↵  " + label
                        color: root.shell.faintText
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }
        }

        ListView {
            id: searchResultList
            visible: root.searchActive && !root.spotlight
            width: parent.width; height: root.contentPaneHeight
            clip: true; spacing: 2
            model: root.spotlight ? [] : root.searchResults
            readonly property bool overflowing: contentHeight > height
            ScrollBar.vertical: PopupScrollBar { shell: root.shell }
            delegate: StartMenuRow {
                required property var modelData
                required property int index
                width: searchResultList.width; shell: root.shell
                rightInset: searchResultList.overflowing ? Style.md : 0
                iconSource: modelData.type === "app" ? Quickshell.iconPath(modelData.app.icon, true) : ""
                icon: modelData.type === "action" ? modelData.entry.icon
                    : modelData.type === "place" ? modelData.place.icon
                    : modelData.type === "file" ? (modelData.file.folder ? "\u{f024b}" : "\u{f0219}") : ""
                title: modelData.type === "app" ? modelData.app.name
                    : modelData.type === "action" ? modelData.entry.path
                    : modelData.type === "file" ? modelData.file.text
                    : modelData.type === "fileSearch" ? "Find more files for “" + modelData.query + "”…" : modelData.place.label
                detail: modelData.type === "app" ? (modelData.app.genericName || modelData.app.comment)
                    : modelData.type === "place" ? modelData.place.path
                    : modelData.type === "file" ? modelData.file.uri
                    : modelData.type === "fileSearch" ? "File Finder" : ""
                value: modelData.type === "app" && root.pinnedApplicationIds.indexOf(modelData.app.id) >= 0 ? "\u{f0403}" : ""
                cursored: index === root.selectedEntryIndex
                onClicked: button => button === Qt.RightButton
                    ? root.activateSecondaryEntry(modelData) : root.activateEntry(modelData)
            }
        }

        Row {
            visible: !root.searchActive && !root.spotlight
            width: parent.width
            spacing: Style.sectionGap

            Column {
                width: parent.width - placesAndMenuPane.width - parent.spacing
                spacing: Style.sm
                StartPinnedGrid {
                    id: pinnedGrid
                    width: parent.width
                    shell: root.shell
                    apps: root.pinnedApplications
                    onLaunched: app => root.activateEntry(app)
                    onUnpinned: app => root.toggleApplicationPin(app)
                }
                PopupSection { visible: recentList.visible; shell: root.shell; text: "RECENT FILES" }
                ListView {
                    id: recentList
                    visible: root.browseOnly && root.recentFiles.length > 0
                    width: parent.width
                    readonly property int visibleRows: Math.min(5, root.recentFiles.length)
                    height: visibleRows * Style.popupRowHeight + Math.max(0, visibleRows - 1) * spacing
                    clip: true; spacing: 2
                    model: root.recentFiles
                    readonly property bool overflowing: contentHeight > height
                    ScrollBar.vertical: PopupScrollBar { shell: root.shell }
                    delegate: StartMenuRow {
                        required property var modelData
                        required property int index
                        width: recentList.width; shell: root.shell
                        rightInset: recentList.overflowing ? Style.md : 0
                        icon: "\u{f0219}"
                        title: modelData.text
                        value: hovered ? "\u{f0156}" : ""
                        valueClickable: true
                        valueHoverColor: root.shell.role("error", root.shell.foreground)
                        cursored: index === root.selectedEntryIndex
                        onValueClicked: root.removeRecentFile(modelData.uri)
                        onClicked: button => button === Qt.RightButton
                            ? root.removeRecentFile(modelData.uri)
                            : root.activateEntry({type: "file", file: modelData})
                    }
                }
                PopupSection { shell: root.shell; text: "ALL APPS" }
                ListView {
                    id: applicationList
                    width: parent.width
                    height: Math.max(0, root.contentPaneHeight - y)
                    clip: true; spacing: 2
                    model: root.availableApplications
                    readonly property bool overflowing: contentHeight > height
                    ScrollBar.vertical: PopupScrollBar { shell: root.shell }
                    delegate: StartMenuRow {
                        required property var modelData
                        required property int index
                        width: applicationList.width; shell: root.shell
                        rightInset: applicationList.overflowing ? Style.md : 0
                        iconSource: Quickshell.iconPath(modelData.icon, true)
                        title: modelData.name
                        detail: modelData.genericName || modelData.comment
                        value: root.pinnedApplicationIds.indexOf(modelData.id) >= 0 ? "\u{f0403}" : ""
                        cursored: index + (root.browseOnly ? root.recentFiles.length : 0) === root.selectedEntryIndex
                        onClicked: button => button === Qt.RightButton
                            ? root.toggleApplicationPin(modelData) : root.activateEntry(modelData)
                    }
                }
            }

            Column {
                id: placesAndMenuPane
                width: Style.px(216)
                spacing: Style.sm
                Column {
                    id: placesColumn
                    width: parent.width
                    spacing: Style.xxs
                    PopupSection { shell: root.shell; text: "PLACES" }
                    Repeater {
                        model: root.places
                        StartMenuRow {
                            required property var modelData
                            width: placesColumn.width; shell: root.shell
                            implicitHeight: Style.px(24)
                            icon: modelData.icon
                            title: modelData.label
                            value: hovered ? "\u{f0156}" : ""
                            valueClickable: true
                            valueHoverColor: root.shell.role("error", root.shell.foreground)
                            onValueClicked: root.removePlace(modelData)
                            onClicked: button => button === Qt.RightButton
                                ? root.removePlace(modelData)
                                : root.activateEntry({type: "place", place: modelData})
                        }
                    }
                    StartMenuRow {
                        visible: !root.placeEditorOpen
                        width: placesColumn.width; shell: root.shell
                        implicitHeight: Style.px(24)
                        icon: "\u{f0415}"
                        iconColor: root.shell.mutedText
                        title: "Add place…"
                        titleColor: root.shell.mutedText
                        onClicked: root.openPlaceEditor()
                    }
                    Rectangle {
                        visible: root.placeEditorOpen
                        width: placesColumn.width; height: Style.px(24)
                        radius: root.shell.rounding
                        color: root.shell.alpha(root.shell.foreground, .06)
                        border.color: root.placeEditorError !== ""
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
                            onTextChanged: root.placeEditorError = ""
                            Keys.onReturnPressed: root.validatePlaceInput()
                            Keys.onEnterPressed: root.validatePlaceInput()
                            Keys.onEscapePressed: root.closePlaceEditor()
                        }
                    }
                    Text {
                        visible: root.placeEditorError !== ""
                        width: placesColumn.width
                        text: root.placeEditorError
                        color: root.shell.role("error", root.shell.foreground)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        elide: Text.ElideRight
                    }
                }
                PopupSeparator { id: paneSeparator; shell: root.shell }
                StartMenuPane {
                    id: menuPane
                    width: parent.width
                    shell: root.shell
                    menus: root.menus
                    totalHeight: root.contentPaneHeight - placesColumn.height - paneSeparator.height - Style.sm * 2
                    onAction: target => root.runMenuAction(target)
                }
            }
        }

    }
}
