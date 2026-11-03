pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "StartMenuModel.js" as StartMenuModel

PopupCard {
    id: root
    readonly property string menutreeScript: root.shell.home + "/.local/lib/hypr/rofi/menutree.sh"
    property string activePopupName: "start"
    popupName: activePopupName
    Binding on activePopupName {
        when: root.shell.popupName === "start" || root.shell.popupName === "spotlight"
        value: root.shell.popupName
        restoreMode: Binding.RestoreNone
    }
    keyboardHint: spotlight ? ""
        : placeEditorOpen ? "Enter Save Place  Esc Cancel"
        : browseOnly ? "Tab Section  ↑↓ Move  Enter Open  Esc Close" : "Type to search  Tab Section  ↑↓ Move  Enter Open  Esc Close"
    wantsKeyboard: true
    contentWidth: spotlight ? Style.spotlightWidth : Style.px(620)
    contentHeight: layoutColumn.implicitHeight + padding * 2
    padding: spotlight ? 0 : Style.popupPadding
    Binding on borderOpacity { when: !root.spotlight; value: 0 }
    centeredHeight: spotlight ? spotlightChromeHeight + Style.spotlightListHeight : cardHeight

    property string searchQuery: ""
    property var recentFiles: []
    property var indexedDocuments: []
    property var usage: ({items: {}, queries: {}})
    property var calculation: null
    readonly property int frequentResultLimit: 8
    readonly property bool spotlight: popupName === "spotlight"
    readonly property bool browseOnly: shell.mode === "winbar" && !spotlight
    property int selectedEntryIndex: 0
    property string cursorSection: "entries"
    property int pinnedCursor: 0
    property int placesCursor: 0
    onPinnedApplicationsChanged: pinnedCursor = Math.min(pinnedCursor, Math.max(0, pinnedApplications.length - 1))
    onPlacesChanged: placesCursor = Math.min(placesCursor, places.length)
    readonly property bool searchActive: searchQuery.trim() !== ""
    readonly property bool listingResults: spotlight || searchActive
    readonly property int fixedContentHeight: (browseOnly ? 0 : searchHeader.height + layoutColumn.spacing) + padding * 2
    readonly property int availableContentHeight: root.maxHeight - root.fixedContentHeight
    readonly property int desiredBrowseHeight: Math.max(placesColumn.implicitHeight + paneSeparator.height
        + Style.sm * 2 + menuPane.unconstrainedHeight, applicationList.y + Style.popupRowHeight)

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

    readonly property var openWindows: spotlight && open ? (Hyprland.toplevels?.values ?? []).map(window => {
        const appId = String(window.wayland?.appId || window.lastIpcObject?.class || "")
        const app = DesktopEntries.heuristicLookup(appId)
        return {address: window.address, appId, entryId: app?.id ?? "", name: app?.name || appId, title: String(window.title || ""), icon: app?.icon || appId}
    }) : []
    readonly property var searchIndex: StartMenuModel.searchIndex(availableApplications, menus, places, spotlight ? recentFiles : [], openWindows)
    readonly property var parsedQuery: spotlight ? StartMenuModel.parseQuery(searchQuery) : ({text: searchQuery.trim(), type: ""})
    readonly property string calculatorExpression: StartMenuModel.calculatorExpression(parsedQuery)
    onCalculatorExpressionChanged: calculate()
    readonly property var searchResults: {
        const now = Date.now()
        if (spotlight && !searchActive) return StartMenuModel.frequent(searchIndex, usage, now, frequentResultLimit)
        const results = StartMenuModel.search(parsedQuery, searchIndex, indexedDocuments, spotlight ? usage : null, now)
        if (!spotlight) return results
        const web = StartMenuModel.webSearch(parsedQuery.text)
        const leading = calculation ? [calculation] : [], trailing = []
        if (!parsedQuery.type) (web.explicitEngine ? leading : trailing).push(web)
        if (parsedQuery.text && (!parsedQuery.type || parsedQuery.type === "file"))
            trailing.unshift({type: "fileSearch", query: parsedQuery.text})
        return leading.concat(results, trailing)
    }
    readonly property var browseEntries: browseOnly
        ? recentFiles.map(file => ({type: "file", file: file})).concat(availableApplications)
        : availableApplications
    readonly property var selectableEntries: listingResults ? searchResults : browseEntries
    readonly property var selectedEntry: selectableEntries[selectedEntryIndex]
    readonly property var cursorSections: listingResults ? ["entries"]
        : ["entries"].concat(pinnedApplications.length > 0 ? ["pinned"] : [], ["places"], menuPane.items.length > 0 ? ["menu"] : [])
    onCursorSectionsChanged: if (!cursorSections.includes(cursorSection)) cursorSection = "entries"

    readonly property int spotlightChromeHeight: Style.spotlightSearchHeight + Style.xl * 2
        + Style.popupRowHeight + searchRule.height + footerRule.height
    readonly property int spotlightGutter: Style.xl + Style.controlPaddingX
    readonly property var spotlightKinds: ({
        calc: {section: "Calculator", kind: "Calculator", verb: "Copy"},
        window: {section: "Windows", kind: "Window", verb: "Switch"},
        app: {section: "Applications", kind: "Application", verb: "Open"},
        action: {section: "Commands", kind: "Command", verb: "Run"},
        place: {section: "Places", kind: "Place", verb: "Open"},
        file: {section: "Files", kind: "File", verb: "Open"},
        fileSearch: {section: "Files", kind: "File Finder", verb: "Search"},
        webSearch: {section: "Web", kind: "Web Search", verb: "Search"}
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
        case "window": return row(item.window.title || item.window.name, item.window.name, "", Quickshell.iconPath(item.window.icon, true))
        case "calc": return row(item.result, item.expression, "\u{f00ec}")
        case "action": return row(item.entry.label, item.entry.parent, item.entry.icon, "", actionChecked(item.entry))
        case "place": return row(item.place.label, tildePath(item.place.path), item.place.icon)
        case "file": return row(item.file.text, tildePath(StartMenuModel.filePath(item.file.uri).replace(/\/[^/]*$/, "")),
            item.file.folder ? "\u{f024b}" : "\u{f0219}")
        case "webSearch": return row("Search " + item.engine.name + " for “" + item.query + "”…", "", item.engine.icon)
        }
        return row("Find more files for “" + item.query + "”…", "", "\u{f0349}")
    }
    function actionChecked(entry) { return (shell.menuTargetActive(entry.target) ?? entry.checked) === true }
    function togglesInPlace(item) { return item?.type === "action" && shell.menuTargetActive(item.entry.target) !== undefined }
    function secondaryLabel(item) {
        return !item ? ""
            : item.type === "app" ? (pinnedApplicationIds.includes(item.app.id) ? "Unpin" : "Pin")
            : item.type === "place" ? "Remove"
            : togglesInPlace(item) ? "Toggle" : ""
    }
    property var lastPointer: null
    function followPointer(item, x, y) {
        if (item.cursorSection) pointerMovedTo(item.cursorSection, item.cursorSlot, item.mapToGlobal(x, y))
    }
    function cursorSlotIn(section) {
        return section === "entries" ? selectedEntryIndex : section === "pinned" ? pinnedCursor
            : section === "places" ? placesCursor : menuPane.cursorIndex
    }
    function pointerMovedTo(section, slot, position) {
        const moved = lastPointer !== null && (position.x !== lastPointer.x || position.y !== lastPointer.y)
        lastPointer = position
        if (!moved || cursorSection === section && cursorSlotIn(section) === slot) return
        cursorSection = section
        if (section === "entries") { selectedEntryIndex = slot; holdSelection() }
        else if (section === "pinned") pinnedCursor = slot
        else if (section === "places") placesCursor = slot
        else menuPane.cursorIndex = slot
    }
    property var heldSelection: null
    function selectionKey(result) {
        return result?.app ?? result?.window?.address ?? result?.entry ?? result?.place ?? result?.file ?? result?.type
    }
    function holdSelection() { if (listingResults) heldSelection = {query: searchQuery, key: selectionKey(selectedEntry)} }
    onSearchResultsChanged: if (listingResults) {
        const held = heldSelection?.query === searchQuery
            ? searchResults.findIndex(result => selectionKey(result) === heldSelection.key) : -1
        selectedEntryIndex = Math.max(0, held)
        Qt.callLater(revealSelection)
    }

    function searchDocuments() {
        indexedDocuments = []
        if (!open || !parsedQuery.text || parsedQuery.type && parsedQuery.type !== "file" || documentSearchProcess.running) return
        documentSearchProcess.query = parsedQuery.text
        documentSearchProcess.running = true
    }
    function calculate() {
        if (!calculatorExpression) calculation = null
        else if (!calculatorProcess.running) {
            calculatorProcess.expression = calculatorExpression
            calculatorProcess.running = true
        }
    }
    function rememberUse(item) {
        const key = spotlight ? StartMenuModel.resultKey(item) : ""
        if (!key) return
        usage = StartMenuModel.recordUse(usage, key, StartMenuModel.searchNeedle(parsedQuery.text), Date.now())
        usageFile.setText(JSON.stringify(usage) + "\n")
    }

    function runMenuAction(target, keepOpen) {
        shell.run(["bash", root.menutreeScript, "--action", target])
        if (!keepOpen) shell.closePopup()
    }
    function activateEntry(item) {
        if (!item) return
        rememberUse(item)
        switch (item.type) {
        case "action":
            runMenuAction(item.entry.target)
            return
        case "calc":
            if (item.expression !== calculatorExpression) return
            shell.run(["wl-copy", item.result])
            break
        case "window":
            Hyprland.dispatch('hl.dsp.focus({window = "address:0x' + item.window.address + '"})')
            break
        case "place":
            shell.run(["xdg-open", item.place.path])
            break
        case "file":
            shell.run(["xdg-open", item.file.uri])
            break
        case "fileSearch":
            shell.run([shell.home + "/.local/lib/hypr/launch/file-finder.sh", item.query])
            break
        case "webSearch":
            shell.run(["xdg-open", item.url])
            break
        default:
            (item.type === "app" ? item.app : item).execute()
        }
        shell.closePopup()
    }
    function activateSecondaryEntry(item) {
        if (!item) return
        if (item.type === "app") toggleApplicationPin(item.app)
        else if (item.type === "place") removePlace(item.place)
        else if (togglesInPlace(item)) runMenuAction(item.entry.target, true)
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
        if (spotlight) spotlightList.positionViewAtIndex(selectedEntryIndex, ListView.Contain)
        else if (searchActive) searchResultList.positionViewAtIndex(selectedEntryIndex, ListView.Contain)
        else if (browseOnly && selectedEntryIndex < recentFiles.length)
            recentList.positionViewAtIndex(selectedEntryIndex, ListView.Contain)
        else applicationList.positionViewAtIndex(selectedEntryIndex - (browseOnly ? recentFiles.length : 0), ListView.Contain)
    }
    function cycleSection(step) {
        cursorSection = cursorSections[(cursorSections.indexOf(cursorSection) + step + cursorSections.length) % cursorSections.length]
        if (cursorSection === "entries" && selectedEntryIndex < 0) moveSelection(1)
        else if (cursorSection === "menu" && menuPane.cursorIndex < 0) menuPane.moveCursor(1)
    }
    function moveInSection(step) {
        if (cursorSection === "entries") moveSelection(step)
        else if (cursorSection === "pinned") {
            const next = pinnedCursor + step
            if (next >= 0 && next < pinnedApplications.length) pinnedCursor = next
        } else if (cursorSection === "places") placesCursor = Math.max(0, Math.min(places.length, placesCursor + step))
        else menuPane.moveCursor(step)
    }
    function moveAcross(step) {
        if (cursorSection === "menu") return step > 0 && menuPane.openCursorSubmenu()
        if (cursorSection !== "pinned") return false
        moveInSection(step)
        return true
    }
    function activateCursorItem(event) {
        const secondary = event.modifiers & Qt.ShiftModifier
        if (cursorSection === "entries") activateSelection(event)
        else if (cursorSection === "pinned") {
            const app = pinnedApplications[pinnedCursor]
            if (!app) return
            if (secondary) toggleApplicationPin(app); else activateEntry(app)
        } else if (cursorSection === "places") {
            const place = places[placesCursor]
            if (!place) openPlaceEditor()
            else if (secondary) removePlace(place)
            else activateEntry({type: "place", place: place})
        } else menuPane.activateCursor()
    }
    function handleNavigationKey(event) {
        shell.keyboardInput = true
        const tab = event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
        if (tab && (event.modifiers & Qt.ControlModifier)) return false
        const deepestFlyout = [flyout4, flyout3, flyout2, flyout].find(level => level.open)
        const toggleTarget = event.key === Qt.Key_Space && !searchActive ? deepestFlyout?.cursorToggleTarget() : ""
        if (toggleTarget) { runMenuAction(toggleTarget, true); return true }
        if (deepestFlyout && deepestFlyout.handleKey(event)) return true
        switch (event.key) {
        case Qt.Key_Tab: cycleSection(1); return true
        case Qt.Key_Backtab: cycleSection(-1); return true
        case Qt.Key_Down: moveInSection(cursorSection === "pinned" ? pinnedGrid.columns : 1); return true
        case Qt.Key_Up: moveInSection(cursorSection === "pinned" ? -pinnedGrid.columns : -1); return true
        case Qt.Key_Left: return moveAcross(-1)
        case Qt.Key_Right: return moveAcross(1)
        case Qt.Key_Return:
        case Qt.Key_Enter: activateCursorItem(event); return true
        }
        return false
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
        if (handleNavigationKey(event)) return true
        return browseOnly ? defaultKey(event) : typeKey(event, searchField) || defaultKey(event)
    }
    onOpenChanged: {
        searchField.text = ""
        selectedEntryIndex = browseOnly ? -1 : 0
        cursorSection = "entries"
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
    property FileView usageFile: FileView {
        path: root.shell.home + "/.local/state/quickshell/spotlight-usage.json"
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.usage = JSON.parse(String(text())) } catch (error) {}
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
        command: ["bash", root.menutreeScript, "--dump-json"]
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
            if (root.open && query === root.parsedQuery.text)
                root.indexedDocuments = String(documentSearchOutput.text).split("\n")
                    .filter(line => line.startsWith(root.shell.home + "/Documents/"))
                    .map(line => {
                        const path = line.replace(/\/$/, "")
                        return {text: path.split("/").pop(), uri: path, folder: path !== line}
                    })
            else if (root.open && root.searchActive)
                Qt.callLater(root.searchDocuments)
        }
    }
    property Process calculatorProcess: Process {
        property string expression: ""
        command: ["qalc", "-t", "--", expression]
        stdout: StdioCollector { id: calculatorOutput; waitForEnd: true }
        onExited: code => {
            if (expression !== root.calculatorExpression) {
                Qt.callLater(root.calculate)
                return
            }
            const result = String(calculatorOutput.text).trim()
            root.calculation = code === 0 && result.replace(/\s/g, "") !== expression.replace(/\s/g, "")
                ? {type: "calc", expression, result} : null
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
        onActionTriggered: (target, keepOpen) => root.runMenuAction(target, keepOpen)
        onDismissed: menuPane.reset()
    }
    property StartMenuFlyout flyout2: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout.openSubId; anchorItem: root.flyout.openRow
        onActionTriggered: (target, keepOpen) => root.runMenuAction(target, keepOpen)
        onDismissed: root.flyout.closeSubmenu()
    }
    property StartMenuFlyout flyout3: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout2.openSubId; anchorItem: root.flyout2.openRow
        onActionTriggered: (target, keepOpen) => root.runMenuAction(target, keepOpen)
        onDismissed: root.flyout2.closeSubmenu()
    }
    property StartMenuFlyout flyout4: StartMenuFlyout {
        shell: root.shell; menus: root.menus
        menuId: root.flyout3.openSubId; anchorItem: root.flyout3.openRow
        onActionTriggered: (target, keepOpen) => root.runMenuAction(target, keepOpen)
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
                placeholderText: root.spotlight ? "Search apps, windows, actions, places, files" : "Search apps, actions, places, documents"
                Binding on placeholderTextColor { when: root.spotlight; value: root.shell.faintText }
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: searchHeader.textSize
                background: null
                onTextChanged: root.searchQuery = text
                Keys.onPressed: event => event.accepted = root.handleNavigationKey(event)
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
            visible: root.spotlight && root.searchResults.length > 0
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
                        onPointerMoved: position => root.pointerMovedTo("entries", index, position)
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
                        text: root.spotlight && root.selectedEntry ? "↵  " + root.spotlightKinds[root.selectedEntry.type].verb : ""
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
            delegate: PopupRow {
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
                value: modelData.type === "app" && root.pinnedApplicationIds.indexOf(modelData.app.id) >= 0 ? "\u{f0403}"
                    : modelData.type === "action" && root.actionChecked(modelData.entry) ? "✓" : ""
                readonly property string cursorSection: "entries"
                readonly property int cursorSlot: index
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
                    cursorIndex: root.cursorSection === "pinned" ? root.pinnedCursor : -1
                    onLaunched: app => root.activateEntry(app)
                    onUnpinned: app => root.toggleApplicationPin(app)
                    onPointed: (index, position) => root.pointerMovedTo("pinned", index, position)
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
                    delegate: PopupRow {
                        required property var modelData
                        required property int index
                        width: recentList.width; shell: root.shell
                        rightInset: recentList.overflowing ? Style.md : 0
                        icon: "\u{f0219}"
                        title: modelData.text
                        value: hovered ? "\u{f0156}" : ""
                        valueClickable: true
                        valueHoverColor: root.shell.role("error", root.shell.foreground)
                        readonly property string cursorSection: "entries"
                        readonly property int cursorSlot: index
                        cursored: root.cursorSection === cursorSection && root.selectedEntryIndex === cursorSlot
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
                    delegate: PopupRow {
                        required property var modelData
                        required property int index
                        width: applicationList.width; shell: root.shell
                        rightInset: applicationList.overflowing ? Style.md : 0
                        iconSource: Quickshell.iconPath(modelData.icon, true)
                        title: modelData.name
                        detail: modelData.genericName || modelData.comment
                        value: root.pinnedApplicationIds.indexOf(modelData.id) >= 0 ? "\u{f0403}" : ""
                        readonly property string cursorSection: "entries"
                        readonly property int cursorSlot: index + (root.browseOnly ? root.recentFiles.length : 0)
                        cursored: root.cursorSection === cursorSection && root.selectedEntryIndex === cursorSlot
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
                        PopupRow {
                            required property var modelData
                            required property int index
                            readonly property string cursorSection: "places"
                            readonly property int cursorSlot: index
                            cursored: root.cursorSection === cursorSection && root.placesCursor === cursorSlot
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
                    PopupRow {
                        visible: !root.placeEditorOpen
                        readonly property string cursorSection: "places"
                        readonly property int cursorSlot: root.places.length
                        cursored: root.cursorSection === cursorSection && root.placesCursor === cursorSlot
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
                    PopupHint {
                        shell: root.shell; error: true
                        width: placesColumn.width; text: root.placeEditorError
                    }
                }
                PopupSeparator { id: paneSeparator; shell: root.shell }
                StartMenuPane {
                    id: menuPane
                    width: parent.width
                    shell: root.shell
                    menus: root.menus
                    totalHeight: root.contentPaneHeight - placesColumn.height - paneSeparator.height - Style.sm * 2
                    cursorShown: root.cursorSection === "menu"
                    onAction: target => root.runMenuAction(target)
                }
            }
        }

    }
}
