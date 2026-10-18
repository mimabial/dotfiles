pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons as Commons
import "BarOrganizer.js" as Organizer

PopupCard {
    id: root
    required property var registry
    property var icons: []
    property string defaultSection: "right"
    signal restoreWidget(string key)
    signal hideWidget(string key)
    popupName: "bar-organizer"
    padding: Commons.Style.space(12)
    contentWidth: preferredWidth + padding * 2
    contentHeight: rows.implicitHeight + padding * 2
    wantsKeyboard: true
    keyboardHint: ""

    readonly property int chipSize: Commons.Style.space(22)
    readonly property int switchHeight: Commons.Style.space(18)
    readonly property int preferredWidth: Commons.Style.space(372)
    readonly property int preferredHeight: Commons.Style.space(480)
    readonly property int rowHeight: Commons.Style.spacing.popupRowHeight + Commons.Style.spacing.md
    readonly property int headerRowHeight: Commons.Style.spacing.controlHeight
    readonly property int indent: Commons.Style.spacing.popupPadding
    property var storeData: ({ layouts: {}, collapsed: {} })
    property var pendingStore: null
    property var pendingRestore: null
    property bool storageReady: false
    property bool storageFailed: false
    property string status: ""
    property string currentKey: ""
    property string armedSlot: ""
    property var draggedRow: null
    property point dragPosition: Qt.point(0, 0)
    readonly property var saved: storeData.layouts[root.shell.layoutName] || ({})
    readonly property var collapsed: storeData.collapsed[root.shell.layoutName] || ({})
    readonly property var entries: Organizer.buildRows(root.shell.barLayout, registry, collapsed,
        (section, entry) => root.shell.trayKey(section, entry), saved, icons)
    readonly property var currentRow: entries.find(row => row.key === currentKey)
    onEntriesChanged: Qt.callLater(restoreCursor)
    onOpenChanged: {
        armedSlot = ""
        if (open) { status = ""; dataFile.reload(); Qt.callLater(restoreCursor) }
        else cancelDrag()
    }

    function restoreCursor() {
        if (!open) return
        const index = Math.max(0, entries.findIndex(row => row.key === currentKey))
        selectEntry(index)
    }
    function selectEntry(index) {
        entryRows.positionViewAtIndex(index, ListView.Contain)
        Qt.callLater(() => {
            const item = entryRows.itemAtIndex(index)
            if (item) selectRow(item)
        })
    }
    function writeStore(next, restore) {
        if (!storageReady || storageFailed || pendingStore) return
        const output = JSON.stringify(next, null, 2) + "\n"
        if (output === dataFile.text()) return
        pendingStore = next
        pendingRestore = restore || null
        dataFile.setText(output)
    }
    function loadStore(raw) {
        try {
            storeData = raw ? JSON.parse(raw) : { layouts: {}, collapsed: {} }
            if (!storeData.layouts || !storeData.collapsed) throw new Error("invalid saved layouts")
            storageReady = true
            storageFailed = false
            if (!saved.initial) {
                const next = Organizer.clone(storeData)
                next.layouts[shell.layoutName] = { initial: Organizer.snapshot(shell.editableBarLayout(), "Initial layout"), snapshots: [] }
                Qt.callLater(() => writeStore(next))
            }
        } catch (error) { storageFailed = true; status = "Could not read saved layouts: " + error }
    }
    function fold(row, value) {
        const next = Organizer.clone(storeData)
        next.collapsed[shell.layoutName] = Object.assign({}, collapsed, { [row.section]: value })
        writeStore(next)
    }
    function cancelDrag() {
        dragMarker.Drag.cancel()
        draggedRow = null
    }
    function dropPlacement(row, after) {
        if (row.type === "widget") return { section: row.section, key: row.key, after }
        const entries = shell.barLayout[row.section] || [], last = entries[entries.length - 1]
        return { section: row.section, key: last === undefined ? "" : shell.trayKey(row.section, last), after: true }
    }
    function send(row, section, targetKey = "", afterTarget = false) {
        if (!row?.canMove || !Organizer.SECTIONS.includes(section) || row.key === targetKey || row.section === section && !targetKey) return
        armedSlot = ""
        let entry, error
        if (row.type === "available") {
            const layout = shell.editableBarLayout()
            const destination = layout[section] || (layout[section] = [])
            let index = destination.findIndex(item => shell.trayKey(section, item) === targetKey)
            if (index < 0) index = destination.length
            else if (afterTarget) index++
            entry = row.id
            destination.splice(index, 0, entry)
            error = shell.saveMovedBarLayout(layout)
        } else {
            entry = shell.barLayout[row.section][row.index]
            error = shell.moveBarModule(row.key, section, targetKey, afterTarget)
        }
        if (!error) currentKey = shell.trayKey(section, entry)
    }
    function chooseSection(row, section) {
        if (!row?.canMove) return
        if (row.section !== section) { send(row, section); return }
        const layout = shell.editableBarLayout()
        const index = layout[section].findIndex(entry => shell.trayKey(section, entry) === row.key)
        if (index < 0) return
        armedSlot = ""
        layout[section].splice(index, 1)
        if (!shell.saveMovedBarLayout(layout)) currentKey = section
    }
    function reorder(row, step) {
        if (!row?.canMove) return
        const target = shell.barLayout[row.section][row.index + step]
        if (target !== undefined) send(row, row.section, shell.trayKey(row.section, target), step > 0)
    }
    function toggle(row) {
        if (!row) return
        if (row.type === "header") { fold(row, !row.collapsed); return }
        if (row.type === "layout") { restore(row); return }
        if (row.type === "icon-toggle") { shell.prefs.trayShowIcons = !shell.prefs.trayShowIcons; return }
        if (row.type === "icon") { shell.toggleTrayIcon(row.id); return }
        if (!row.canToggle) return
        if (row.type === "available") send(row, defaultSection)
        else {
            const entry = shell.barLayout[row.section][row.index]
            currentKey = shell.trayKey(row.section === "tray" ? entry.trayPosition?.section || defaultSection : "tray", entry)
            if (row.section === "tray") restoreWidget(row.key)
            else hideWidget(row.key)
        }
    }
    function saveMine() {
        const next = Organizer.clone(storeData), layouts = next.layouts[shell.layoutName]
        if (!layouts) return
        if (layouts.mine) layouts.snapshots = [Object.assign({}, layouts.mine, { name: "Before a save" })]
            .concat(layouts.snapshots || []).slice(0, Organizer.SNAPSHOT_LIMIT)
        layouts.mine = Organizer.snapshot(shell.editableBarLayout(), "My layout")
        writeStore(next)
    }
    function restore(row) {
        if (!row.saved || !storageReady || pendingStore) return
        if (armedSlot !== row.slot) { armedSlot = row.slot; status = "Restore " + row.name + "? Press again to confirm."; return }
        const next = Organizer.clone(storeData), layouts = next.layouts[shell.layoutName]
        layouts.snapshots = [Organizer.snapshot(shell.editableBarLayout(), "Before a restore")]
            .concat(layouts.snapshots || []).slice(0, Organizer.SNAPSHOT_LIMIT)
        armedSlot = ""
        writeStore(next, row.saved)
    }
    function keyToken(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return ""
        const names = { [Qt.Key_Up]: "up", [Qt.Key_Down]: "down", [Qt.Key_Left]: "left", [Qt.Key_Right]: "right",
            [Qt.Key_Home]: "home", [Qt.Key_End]: "end", [Qt.Key_Return]: "enter", [Qt.Key_Enter]: "enter", [Qt.Key_Space]: "space" }
        const shifted = event.modifiers & Qt.ShiftModifier
        if (names[event.key]) return (shifted ? "shift+" : "") + names[event.key]
        if (event.key >= Qt.Key_A && event.key <= Qt.Key_Z)
            return shifted ? String.fromCharCode(event.key) : String.fromCharCode(event.key).toLowerCase()
        return event.text
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape && draggedRow) { cancelDrag(); return true }
        if (event.key === Qt.Key_Escape && armedSlot) { armedSlot = ""; status = ""; return true }
        const action = Organizer.resolveKey(currentRow, keyToken(event))
        if (action.kind === "none") return defaultKey(event)
        if (!["cursor", "end", "lane", "parent"].includes(action.kind) && event.isAutoRepeat) return true
        switch (action.kind) {
        case "cursor": moveCursor(action.step); break
        case "end": selectEntry(action.last ? entries.length - 1 : 0); break
        case "lane": selectEntry(Organizer.laneHeader(entries, entries.indexOf(currentRow), action.step)); break
        case "parent": selectEntry(Organizer.parentHeader(entries, entries.indexOf(currentRow))); break
        case "fold": fold(currentRow, action.collapsed); break
        case "send": chooseSection(currentRow, action.section); break
        case "reorder": reorder(currentRow, action.step); break
        case "toggle": toggle(currentRow); break
        case "save": saveMine(); break
        case "restore": restore(currentRow); break
        case "pin": shell.toggleTrayPin(currentRow.id); break
        }
        return true
    }

    Item {
        id: dragMarker
        parent: root.contentItem
        z: 1
        x: root.dragPosition.x; y: root.dragPosition.y
        width: Commons.Style.spacing.hairline; height: width
        Drag.source: root
        Drag.keys: ["bar-organizer-widget"]
        Drag.proposedAction: Qt.MoveAction
        Rectangle {
            x: Commons.Style.spacing.labelGap; y: x
            visible: !!root.draggedRow
            width: dragLabel.implicitWidth + Commons.Style.spacing.controlPaddingX * 2
            height: dragLabel.implicitHeight + Commons.Style.spacing.controlPaddingY * 2
            radius: root.shell.rounding
            color: root.shell.background
            border.color: root.shell.accent
            border.width: Commons.Style.normalBorderWidth
            Text {
                id: dragLabel
                anchors.centerIn: parent
                text: root.draggedRow?.name || ""
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.body
            }
        }
    }
    component Chip: Rectangle {
        id: chip
        property string text: ""
        property bool current: false
        property bool shown: true
        property bool urgent: false
        signal clicked()
        implicitWidth: text.length > 1 ? Math.max(root.chipSize, chipText.implicitWidth + root.indent) : root.chipSize
        implicitHeight: root.chipSize
        width: implicitWidth; height: implicitHeight
        opacity: !shown ? 0 : enabled || current ? 1 : Commons.Style.mutedTextAlpha
        radius: root.shell.rounding
        color: current ? root.shell.selectedFill() : chipMouse.containsMouse && enabled ? root.shell.hoverFill() : "transparent"
        border.width: current ? Commons.Style.normalBorderWidth : 0
        border.color: root.shell.selectedEdge()
        Behavior on color { ColorAnimation { duration: Commons.Style.hoverDuration } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.text
            textFormat: Text.PlainText
            color: chip.urgent ? root.shell.urgent : chip.current ? root.shell.accent : root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.caption
            font.bold: chip.current
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }
    Connections {
        target: root.shell
        function onLayoutSaveErrorChanged() { if (root.shell.layoutSaveError) root.status = "Could not save the bar: " + root.shell.layoutSaveError }
    }
    FileView {
        id: dataFile
        path: root.shell.home + "/.config/quickshell/bar-organizer.json"
        preload: root.open
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: if (root.open && !root.pendingStore) reload()
        onLoaded: root.loadStore(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) root.loadStore("")
            else { root.storageFailed = true; root.status = "Could not read saved layouts" }
        }
        onSaveFailed: {
            root.pendingStore = null; root.pendingRestore = null
            root.status = "Could not save layouts; the bar was left unchanged"
        }
        onSaved: {
            if (!root.pendingStore) return
            root.storeData = root.pendingStore
            root.pendingStore = null
            const saved = root.pendingRestore
            root.pendingRestore = null
            const error = saved ? root.shell.saveMovedBarLayout(Organizer.restoredLayout(root.shell.editableBarLayout(), saved)) : ""
            root.status = error ? "Could not restore the bar: " + error : saved ? "Layout restored" : "Saved"
        }
    }

    Column {
        id: rows
        width: parent.width
        height: root.preferredHeight
        spacing: Commons.Style.spacing.lg
        PopupHero {
            id: hero
            shell: root.shell
            icon: "\uf0e8"
            title: "Bar Organizer"
            status: root.entries.filter(row => row.type === "header" && Organizer.SECTIONS.includes(row.section) && row.section !== "tray")
                .reduce((count, row) => count + row.count, 0) + " on the bar · "
                + (root.entries.find(row => row.key === "available")?.count || 0) + " available"
        }
        Column {
            id: hint
            width: rows.width
            spacing: Commons.Style.spacing.xxs
            Text {
                width: parent.width
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                text: "↑↓ move · [ ] sections · Shift+↑↓ order · Shift+←→ section"
                color: root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.caption
            }
            Text {
                width: parent.width
                height: Commons.Style.font.caption + Commons.Style.spacing.md
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: root.status || (root.draggedRow ? "Drop between rows or onto a section heading" : Organizer.hintFor(root.currentRow, !!root.armedSlot))
                color: root.shell.accent
                font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.caption
            }
        }
        PopupSeparator { id: separator; width: rows.width; shell: root.shell }
        ListView {
            id: entryRows
            width: rows.width
            height: rows.height - hero.height - hint.height - separator.height - bottomSeparator.height - footer.height
                - rows.spacing * (rows.children.length - 1)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: root.draggedRow ? contentHeight : height
            ScrollBar.vertical: PopupScrollBar { shell: root.shell }
            model: root.open ? root.entries : []
            delegate: Item {
                id: entryRow
                required property var modelData
                readonly property bool headerRow: modelData.type === "header"
                readonly property bool widget: ["widget", "available"].includes(modelData.type)
                readonly property bool navigable: true
                property bool cursored: false
                readonly property string title: modelData.name
                width: entryRows.width
                height: headerRow ? root.headerRowHeight : root.rowHeight
                onCursoredChanged: if (cursored && !root.draggedRow) {
                    if (root.currentKey !== modelData.key) { root.armedSlot = ""; root.status = "" }
                    root.currentKey = modelData.key
                }
                Rectangle {
                    visible: !entryRow.headerRow
                    x: root.indent - Commons.Style.spacing.xxs
                    width: Commons.Style.spacing.hairline; height: parent.height
                    color: separator.color
                }
                Rectangle {
                    id: rowSurface
                    x: entryRow.headerRow ? 0 : root.indent + Commons.Style.spacing.md
                    y: entryRow.headerRow ? Commons.Style.spacing.xxs : Commons.Style.spacing.hairline
                    width: entryRow.width - x
                    height: entryRow.height - y - (entryRow.headerRow ? 0 : Commons.Style.spacing.hairline)
                    radius: root.shell.rounding
                    color: entryRow.cursored ? root.shell.hoverFill() : "transparent"
                    border.color: entryRow.cursored ? root.shell.hoverEdge(.85) : "transparent"
                    Behavior on color { ColorAnimation { duration: Commons.Style.hoverDuration; easing.type: Easing.OutCubic } }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: entryRow.modelData.canMove ? Qt.OpenHandCursor : Qt.PointingHandCursor
                        onClicked: event => {
                            root.selectRow(entryRow)
                            if (event.button === Qt.RightButton && entryRow.modelData.type === "icon") root.shell.toggleTrayPin(entryRow.modelData.id)
                            else if (["header", "icon", "icon-toggle"].includes(entryRow.modelData.type)) root.toggle(entryRow.modelData)
                        }
                    }
                    Row {
                        visible: entryRow.headerRow
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left; anchors.leftMargin: Commons.Style.spacing.lg
                        spacing: Commons.Style.spacing.lg
                        Text {
                            text: entryRow.modelData.collapsed ? "▸" : "▾"
                            color: root.shell.mutedText
                            font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.body
                        }
                        PopupSection {
                            shell: root.shell
                            topPadding: 0
                            text: entryRow.title.toUpperCase() + "  " + entryRow.modelData.count
                        }
                    }
                    Row {
                        id: rowContents
                        visible: !entryRow.headerRow
                        anchors.fill: parent
                        anchors.leftMargin: Commons.Style.spacing.lg; anchors.rightMargin: Commons.Style.spacing.md
                        spacing: Commons.Style.spacing.md
                        IconImage {
                            id: iconImage
                            visible: entryRow.modelData.type === "icon"
                            source: visible ? entryRow.modelData.icon.icon : ""
                            implicitWidth: root.switchHeight; implicitHeight: implicitWidth
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Column {
                            id: labels
                            anchors.verticalCenter: parent.verticalCenter
                            width: rowContents.width - controls.width - rowContents.spacing
                                - (iconImage.visible ? iconImage.width + rowContents.spacing : 0)
                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: entryRow.title
                                elide: Text.ElideRight
                                color: entryRow.modelData.type === "available" ? root.shell.mutedText : root.shell.foreground
                                font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.body
                            }
                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                text: entryRow.modelData.type === "layout" ? entryRow.modelData.saved
                                        ? new Date(entryRow.modelData.saved.savedAt).toLocaleString() : "Not saved yet"
                                    : entryRow.widget ? Organizer.DESCRIPTIONS[entryRow.modelData.id] || ""
                                    : entryRow.modelData.type === "icon" ? entryRow.modelData.id : ""
                                visible: text !== ""
                                color: root.shell.mutedText
                                font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.caption
                            }
                            DragHandler {
                                id: rowDrag
                                target: null
                                enabled: root.open && !!entryRow.modelData.canMove
                                cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                onCentroidChanged: if (active) root.dragPosition = centroid.scenePosition
                                onActiveChanged: if (active) {
                                    root.selectRow(entryRow)
                                    root.armedSlot = ""
                                    root.draggedRow = entryRow.modelData
                                    root.dragPosition = centroid.scenePosition
                                    dragMarker.Drag.active = true
                                }
                                onGrabChanged: transition => {
                                    if (root.draggedRow?.key !== entryRow.modelData.key) return
                                    if (transition === PointerDevice.UngrabExclusive) {
                                        dragMarker.Drag.drop()
                                        root.draggedRow = null
                                    } else if (transition === PointerDevice.CancelGrabExclusive) root.cancelDrag()
                                }
                            }
                        }
                        Row {
                            id: controls
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Commons.Style.spacing.xxs
                            Repeater {
                                model: entryRow.modelData.type === "widget" ? [-1, 1] : []
                                delegate: Chip {
                                    required property var modelData
                                    text: modelData < 0 ? "▲" : "▼"
                                    shown: entryRow.cursored
                                    enabled: shown && entryRow.modelData.canMove && entryRow.modelData.index + modelData >= 0
                                        && entryRow.modelData.index + modelData < entryRow.modelData.sectionSize
                                    onClicked: root.reorder(entryRow.modelData, modelData)
                                }
                            }
                            Item { width: Commons.Style.spacing.sm; height: Commons.Style.spacing.hairline; visible: entryRow.modelData.type === "widget" }
                            Chip {
                                visible: entryRow.modelData.type === "layout" && entryRow.modelData.slot === "mine"
                                text: "Save"
                                enabled: root.storageReady && !root.storageFailed && !root.pendingStore
                                onClicked: root.saveMine()
                            }
                            Chip {
                                visible: entryRow.modelData.type === "layout"
                                text: root.armedSlot === entryRow.modelData.slot ? "Sure?" : "Restore"
                                urgent: root.armedSlot === entryRow.modelData.slot
                                enabled: !!entryRow.modelData.saved && !root.pendingStore
                                onClicked: { root.selectRow(entryRow); root.restore(entryRow.modelData) }
                            }
                            Repeater {
                                model: entryRow.widget ? Organizer.SECTIONS : []
                                delegate: Chip {
                                    required property string modelData
                                    text: modelData[0].toUpperCase()
                                    current: entryRow.modelData.section === modelData
                                    enabled: entryRow.modelData.canMove
                                    onClicked: root.chooseSection(entryRow.modelData, modelData)
                                }
                            }
                            Chip {
                                visible: entryRow.modelData.type === "icon"
                                text: "Pin"
                                current: root.shell.trayPinned.includes(entryRow.modelData.id)
                                onClicked: root.shell.toggleTrayPin(entryRow.modelData.id)
                            }
                            Item { width: Commons.Style.spacing.sm; height: Commons.Style.spacing.hairline; visible: entryRow.modelData.type !== "layout" }
                            ToggleSwitch {
                                visible: entryRow.widget || ["icon", "icon-toggle"].includes(entryRow.modelData.type)
                                anchors.verticalCenter: parent.verticalCenter
                                shell: root.shell; keyboardEnabled: false
                                checked: entryRow.modelData.type === "icon" ? !root.shell.trayHidden.includes(entryRow.modelData.id)
                                    : entryRow.modelData.type === "icon-toggle" ? root.shell.prefs.trayShowIcons : entryRow.modelData.type === "widget" && entryRow.modelData.section !== "tray"
                                enabled: entryRow.widget ? entryRow.modelData.canToggle : true
                                opacity: enabled ? 1 : Commons.Style.mutedTextAlpha
                                onToggled: root.toggle(entryRow.modelData)
                            }
                        }
                    }
                }
                PopupPointer { shell: root.shell; row: entryRow }
                DropArea {
                    id: rowDrop
                    anchors.fill: parent
                    keys: ["bar-organizer-widget"]
                    enabled: root.open && (entryRow.modelData.type === "widget"
                        || entryRow.headerRow && Organizer.SECTIONS.includes(entryRow.modelData.section))
                    onEntered: drag => {
                        if (drag.source !== root || !root.draggedRow?.canMove || root.draggedRow.key === entryRow.modelData.key) drag.accepted = false
                    }
                    onDropped: drop => {
                        const row = root.draggedRow, placement = root.dropPlacement(entryRow.modelData, drop.y >= height / 2)
                        if (drop.source !== root || !row?.canMove || row.key === entryRow.modelData.key) return
                        drop.acceptProposedAction()
                        Qt.callLater(() => root.send(row, placement.section, placement.key, placement.after))
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: rowDrop.containsDrag && entryRow.headerRow
                        radius: root.shell.rounding
                        color: "transparent"
                        border.color: root.shell.accent; border.width: Commons.Style.normalBorderWidth
                    }
                    Rectangle {
                        visible: rowDrop.containsDrag && entryRow.modelData.type === "widget"
                        width: parent.width; height: Commons.Style.spacing.hairline
                        y: rowDrop.drag.y >= rowDrop.height / 2 ? parent.height - height : 0
                        color: root.shell.accent
                    }
                }
            }
        }
        PopupSeparator { id: bottomSeparator; width: rows.width; shell: root.shell }
        Text {
            id: footer
            width: rows.width; height: root.chipSize
            verticalAlignment: Text.AlignVCenter
            text: "Click selected L/C/R/T again to remove"
            textFormat: Text.PlainText; elide: Text.ElideRight
            color: root.shell.mutedText
            font.family: root.shell.fontFamily; font.pixelSize: Commons.Style.font.caption
        }
    }
}
