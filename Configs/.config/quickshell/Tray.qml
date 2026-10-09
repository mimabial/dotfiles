pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

Item {
    id: root
    required property var shell
    required property var registry
    property bool popupsAllowed: true
    property int iconSize: 12
    property var menuHandle: null
    property Item menuAnchor: null
    property string menuLabel: ""
    property string cursorKey: ""
    readonly property var box: shell.style.box("tray")
    readonly property int scaledIcon: Math.round(box.iconSize !== undefined ? box.iconSize : iconSize)
    readonly property real sectionSpacing: shell.style.box(".modules-" + host?.sectionName).spacing || 0
    readonly property real borderInset: box.borderColor ? box.borderWidth : 0
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * borderInset
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * borderInset
    readonly property real cellSize: height - box.margin[0] - box.margin[2]
    readonly property real radius: box.borderRadius ?? shell.moduleRadius
    readonly property var icons: {
        const values = SystemTray.items.values, result = []
        for (let i = 0; i < values.length; i++) if (values[i].status !== Status.Passive) result.push(values[i])
        return result
    }
    readonly property var shownIcons: shell.prefs.trayShowIcons ? icons.filter(item => !shell.trayHidden.includes(iconId(item))) : []
    readonly property var pinnedIcons: [].concat(...shell.trayPinned.map(id => shownIcons.filter(item => iconId(item) === id)))
    readonly property var attentionIcons: shownIcons.filter(item => item.status === Status.NeedsAttention && !pinnedIcons.includes(item))
    readonly property var barIcons: pinnedIcons.concat(attentionIcons)
    readonly property var drawerIcons: shownIcons.filter(item => !barIcons.includes(item))
    readonly property BarModuleLoader host: parent as BarModuleLoader
    readonly property var drawerEntries: {
        const entries = []
        for (const entry of shell.barLayout.tray || []) {
            const key = shell.trayKey("tray", entry), icon = typeof entry === "string" && entry.startsWith("icon:") ? entry.slice(5) : ""
            const data = icon ? drawerIcons.find(item => iconId(item) === icon) : { key, section: "tray", entry }
            if (data) entries.push({ key, data, widget: !icon })
        }
        for (const data of drawerIcons) {
            const key = iconKey(data)
            if (!entries.some(entry => entry.key === key)) entries.push({ key, data, widget: false })
        }
        return entries
    }
    readonly property var barWidgets: [].concat(...shell.barSections.map(section => (shell.barLayout[section] || []).map(entry =>
        ({ key: shell.trayKey(section, entry), id: typeof entry === "string" ? entry : String(entry.id || ""), onBar: section !== "tray" }))))
        .filter(widget => !["tray", "taskbar", "spacer"].includes(widget.id) && !widget.id.startsWith("icon:"))
        .sort((a, b) => a.id.localeCompare(b.id) || a.key.localeCompare(b.key))
    function iconId(item) { return String(item.id || "") }
    function iconKey(item) { return shell.trayKey("tray", "icon:" + iconId(item)) }
    function setPinned(id, pinned) { if (shell.trayPinned.includes(id) !== pinned) shell.toggleTrayPin(id) }
    // the StatusNotifierItem spec allows markup in the description only
    function tooltipText(item) {
        const title = String(item.tooltipTitle || item.title || item.id).replace(/&/g, "&amp;").replace(/</g, "&lt;")
        return item.tooltipDescription ? title + "<br>" + item.tooltipDescription : title
    }
    function afterKey(key) {
        const keys = drawerEntries.map(entry => entry.key)
        return keys[keys.indexOf(key) + 1] || ""
    }
    function ownsPopup() {
        for (let item = shell.popupCard?.anchorItem; item; item = item.parent)
            if (item === root || item === overflowGrid) return true
        return false
    }
    function acceptDrop(drop, before) {
        const module = drop.source as BarModuleLoader
        const key = module ? module.moduleKey : String(drop.source?.["trayKey"] || "")
        if (!key || key === before || (module && module.moduleId === "tray")) return
        drop.acceptProposedAction()
        const id = String(drop.source?.["iconId"] ?? "")
        Qt.callLater(() => { setPinned(id, false); shell.moveBarModule(key, "tray", before, false) })
    }
    function activateIcon(icon, button, anchor) {
        if (button === Qt.MiddleButton) { icon.secondaryActivate(); popupHold = false }
        else if (button === Qt.LeftButton && !icon.onlyMenu) { icon.activate(); popupHold = false }
        else if (icon.hasMenu && popupsAllowed) {
            if (shell.popupName === "tray" && shell.popupCard?.anchorItem === anchor) {
                shell.closePopup()
                return
            }
            menuHandle = icon.menu
            menuAnchor = anchor
            menuLabel = icon.title || icon.id
            if (shell.popupName !== "tray") shell.togglePopup("tray")
        }
    }
    function toggleFlyout() {
        const reopen = !popupOwned && !popupHold
        shell.closePopup()
        popupHold = reopen
    }
    function keyboardTarget(item) {
        if (!item || item.navigable === true) return item
        for (const child of item.children) {
            const target = child.visible ? keyboardTarget(child) : null
            if (target) return target
        }
        return null
    }
    function handleKey(event) {
        const cells = Array.from({ length: slots.count }, (_, index) => slots.itemAt(index)).filter(cell => cell?.visible)
        const index = cells.findIndex(cell => cell.trayKey === cursorKey)
        const step = { [Qt.Key_Left]: -1, [Qt.Key_Backtab]: -1, [Qt.Key_Right]: 1, [Qt.Key_Tab]: 1,
            [Qt.Key_Up]: -overflowGrid.columns, [Qt.Key_Down]: overflowGrid.columns }[event.key]
        if (step !== undefined) {
            const next = cells[index < 0 ? 0 : index + step]
            if (next) cursorKey = next.trayKey
        } else if (event.key === Qt.Key_Escape) popupHold = false
        else if (index < 0) return false
        else if ([Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) cells[index].activate(Qt.LeftButton)
        else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) cells[index].activate(Qt.RightButton)
        else return false
        return true
    }
    property bool popupHold: false
    // hosted widgets load with the flyout, and some report their state only later;
    // keeping the cells of those shown last time stops the grid shifting under the pointer
    property var shownKeys: []
    function remember(key, shown) {
        if (shownKeys.includes(key) !== shown) shownKeys = shown ? shownKeys.concat(key) : shownKeys.filter(item => item !== key)
    }
    readonly property bool popupOwned: ownsPopup()
    readonly property bool draggingContent: drawerEntries.some(entry => entry.key === shell.dragKey)
    readonly property bool draggingWidget: drawerEntries.some(entry => entry.widget && entry.key === shell.dragKey)
    readonly property bool expanded: popupsAllowed && (popupHold || popupOwned || draggingContent)
    onPopupsAllowedChanged: if (!popupsAllowed) popupHold = false
    implicitWidth: content.implicitWidth
    implicitHeight: Math.max(content.implicitHeight, scaledIcon + spanY)

    Binding { target: root.shell; property: "trayOpen"; value: true; when: root.expanded }
    Connections {
        target: root.shell
        function onPopupNameChanged() {
            if (root.shell.popupName === "") root.popupHold = false
        }
        function onPopupCardChanged() {
            if (root.shell.popupCard && !root.ownsPopup()) root.popupHold = false
        }
        function onTrayToggleRequested() {
            if (!root.popupsAllowed) return
            root.toggleFlyout()
            if (root.popupHold) root.cursorKey = root.drawerEntries[0]?.key ?? ""
        }
    }
    RowLayout {
        id: content
        anchors.centerIn: parent
        height: root.height
        spacing: root.sectionSpacing
        BarButton {
            id: chevron
            shell: root.shell; css: "tray.chevron"
            text: root.expanded !== overflow.onTop ? "\ueab4" : "\ueab7"
            backgroundColor: root.expanded && box.open ? shell.styleColor(box.open.backgroundColor, "transparent") : styleColor("backgroundColor")
            Layout.fillHeight: true
            onClicked: button => {
                if (button === Qt.RightButton && root.popupsAllowed) root.shell.togglePopup("tray-manage")
                else if (button === Qt.LeftButton) root.toggleFlyout()
            }
            DragHandler {
                id: trayDrag
                target: null
                dragThreshold: 8
                onActiveChanged: {
                    if (!root.host) return
                    if (active) { root.shell.dragKey = root.host.moduleKey; trayMarker.Drag.active = true }
                    else {
                        if (trayMarker.Drag.active) trayMarker.Drag.drop()
                        if (root.shell.dragKey === root.host.moduleKey) root.shell.dragKey = ""
                    }
                }
            }
            Item {
                id: trayMarker
                width: 1; height: 1
                x: trayDrag.centroid.position.x; y: trayDrag.centroid.position.y
                Drag.source: root.parent
                Drag.keys: ["bar-module"]
                Drag.proposedAction: Qt.MoveAction
                Rectangle {
                    anchors.centerIn: parent
                    visible: trayDrag.active
                    width: 56; height: 24; radius: 4
                    color: root.shell.alpha(root.shell.background, .94); border.color: root.shell.accent
                    Text { anchors.centerIn: parent; text: "tray"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 11 }
                }
            }
            DropArea {
                id: chevronDrop
                anchors.fill: parent
                z: 10
                keys: ["bar-module", "tray-module", "tray-icon"]
                onDropped: drop => root.acceptDrop(drop, "")
                Rectangle { anchors.fill: parent; visible: chevronDrop.containsDrag; radius: root.radius; color: root.shell.alpha(root.shell.accent, .24); border.color: root.shell.accent }
            }
        }
        Item {
            id: iconFrame
            readonly property var box: root.box
            readonly property real radius: root.radius
            visible: root.barIcons.length > 0
            Layout.fillHeight: true
            Layout.preferredWidth: frameRow.implicitWidth + root.spanX
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
                anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
                radius: sideBorder.radius
                color: root.shell.styleColor(root.box.backgroundColor, "transparent")
                border.color: root.shell.styleColor(root.box.borderColor, "transparent")
                border.width: root.borderInset
            }
            SideBorder { id: sideBorder; shell: root.shell; host: iconFrame }
            RowLayout {
                id: frameRow
                anchors.fill: parent
                anchors.topMargin: root.box.margin[0] + root.borderInset + root.box.padding[0]
                anchors.rightMargin: root.box.margin[1] + root.borderInset + root.box.padding[1]
                anchors.bottomMargin: root.box.margin[2] + root.borderInset + root.box.padding[2]
                anchors.leftMargin: root.box.margin[3] + root.borderInset + root.box.padding[3]
                spacing: root.sectionSpacing
                Repeater {
                    model: root.barIcons
                    delegate: TrayIcon {
                        required property var modelData
                        trayItem: modelData
                        implicitWidth: root.scaledIcon; implicitHeight: root.scaledIcon
                    }
                }
            }
        }
    }
    // A layer surface rather than a popup: widgets hosted in it anchor PopupCards
    // of their own, and PopupCard derives screen coordinates from layer anchors.
    PanelWindow {
        id: overflow
        readonly property var bar: root.QsWindow.window
        readonly property bool onTop: root.shell.barEdge === "top"
        property real anchorX: 0
        property point widgetDragPosition
        function overBar(position) {
            const barY = position.y + (onTop ? -bar.margins.top : bar.height + bar.margins.bottom - height)
            return barY >= 0 && barY <= bar.height
        }
        // drag and drop stays within one window, so a widget dragged out of the
        // flyout lands in whichever bar section lies under the release point
        function dropOnBar(key, position) {
            if (!overBar(position)) return
            const placement = bar.dropPlacement(position.x - bar.margins.left)
            Qt.callLater(() => root.shell.moveBarModule(key, placement.section, placement.target, false))
        }
        screen: bar ? bar.screen : null
        visible: root.expanded && root.drawerEntries.length > 0
        onVisibleChanged: {
            if (!visible) { root.cursorKey = ""; return }
            anchorX = bar.margins.left + chevron.mapToItem(null, chevron.width / 2, 0).x
        }
        color: "transparent"
        anchors.left: true; anchors.right: true; anchors.top: onTop; anchors.bottom: !onTop
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hypr-shell-bar"
        // keyboard navigation holds focus exclusively, as the dock's does: dropping to
        // on-demand hands it back to the window under the pointer
        WlrLayershell.keyboardFocus: root.cursorKey && root.shell.popupName === "" ? WlrKeyboardFocus.Exclusive
            : root.popupOwned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        implicitHeight: (bar ? bar.height + bar.margins.top + bar.margins.bottom : 0) + Style.popupGap + card.height
        mask: Region { item: card }
        // a popup anchored in here may get the keyboard instead of the bar; route it the same way
        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => { event.accepted = root.shell.popupName && root.shell.popupCard ? root.shell.popupCard.handleKey(event) : root.handleKey(event) }
        }
        Rectangle {
            id: card
            x: Math.max(Style.popupGap, Math.min(overflow.width - width - Style.popupGap, overflow.anchorX - width / 2))
            y: overflow.onTop ? overflow.height - height : 0
            width: overflowGrid.width + 2 * Style.lg; height: overflowGrid.height + 2 * Style.lg
            radius: root.shell.rounding
            color: root.shell.alpha(root.shell.background, Style.popupSurfaceOpacity)
            border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), Style.popupBorderOpacity)
            border.width: root.shell.borderWidth
            Grid {
                id: overflowGrid
                anchors.centerIn: parent
                columns: Math.ceil(Math.sqrt(root.drawerEntries.length))
                spacing: Style.xxs
                Repeater {
                    id: slots
                    model: overflow.visible ? root.drawerEntries : []
                    delegate: TraySlot {}
                }
            }
        }
        Loader {
            active: root.draggingWidget
            sourceComponent: Rectangle {
                visible: overflow.overBar(overflow.widgetDragPosition)
                x: overflow.bar.margins.left + Math.min(overflow.bar.width - width, overflow.bar.dropPlacement(overflow.widgetDragPosition.x - overflow.bar.margins.left).x)
                y: overflow.onTop ? overflow.bar.margins.top : overflow.height - overflow.bar.margins.bottom - overflow.bar.height
                width: 2; height: overflow.bar.height; color: root.shell.accent
            }
        }
        HyprlandFocusGrab {
            active: overflow.visible && root.shell.popupName === ""
            windows: [overflow, overflow.bar]
            onCleared: root.popupHold = false
        }
    }
    component TraySlot: Item {
        id: slot
        required property var modelData
        readonly property bool widget: modelData.widget
        readonly property string trayKey: modelData.key
        readonly property bool cursored: root.cursorKey === trayKey
        readonly property bool live: !widget || host.item !== null && host.moduleVisible(host.item)
        property bool reported: false
        visible: live || root.shownKeys.includes(trayKey)
        // recorded only while shown: tearing the flyout down reports its widgets hidden
        function note() { if (widget && overflow.visible && (live || reported)) { reported = true; root.remember(trayKey, live) } }
        function activate(button) {
            if (widget) root.keyboardTarget(host.item)?.clicked(button)
            else root.activateIcon(modelData.data, button, slot)
        }
        onLiveChanged: note()
        Component.onCompleted: note()
        Component.onDestruction: if (widget && !reported) root.remember(trayKey, false)
        width: Math.max(root.cellSize, widget ? host.implicitWidth : 0); height: root.cellSize
        HoverHandler { id: hover }
        Rectangle {
            anchors.fill: parent
            visible: slot.cursored || hover.hovered && !slot.widget
            radius: root.radius; color: root.shell.hoverFill()
            border.color: root.shell.hoverEdge(.85); border.width: slot.cursored ? 2 : 0
        }
        BarModuleLoader {
            id: host
            anchors.centerIn: parent
            height: parent.height
            modelData: slot.widget ? slot.modelData.data : ({ entry: "spacer" })
            shell: root.shell; registry: root.registry
            sectionName: slot.widget ? slot.modelData.data.section : "right"
            hosted: true; visible: slot.widget
            onDroppedOutside: position => overflow.dropOnBar(moduleKey, position)
        }
        Binding { target: overflow; property: "widgetDragPosition"; value: host.dragPosition; when: slot.widget && root.shell.dragKey === slot.trayKey }
        Loader {
            anchors.fill: parent
            active: !slot.widget
            sourceComponent: TrayIcon {
                id: drawerIcon
                trayItem: slot.modelData.data
                onDroppedOutside: position => { if (overflow.overBar(position)) Qt.callLater(() => root.setPinned(drawerIcon.iconId, true)) }
            }
        }
        DropArea {
            id: slotTarget
            anchors.fill: parent
            z: 10
            keys: ["bar-module", "tray-module", "tray-icon"]
            onDropped: drop => root.acceptDrop(drop, drop.x >= width / 2 ? root.afterKey(slot.trayKey) : slot.trayKey)
            Rectangle {
                visible: slotTarget.containsDrag
                x: slotTarget.drag.x >= slotTarget.width / 2 ? parent.width - width : 0
                width: 2; height: parent.height; color: root.shell.accent
            }
        }
    }
    component TrayIcon: Item {
        id: trayIcon
        required property var trayItem
        readonly property string iconId: root.iconId(trayItem)
        readonly property string trayKey: root.iconKey(trayItem)
        signal droppedOutside(point position)
        IconImage { anchors.centerIn: parent; width: root.scaledIcon; height: root.scaledIcon; source: trayIcon.trayItem.icon }
        MouseArea {
            id: pointer
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            onClicked: event => root.activateIcon(trayIcon.trayItem, event.button, trayIcon)
            onWheel: event => trayIcon.trayItem.scroll(event.angleDelta.y, false)
        }
        DragHandler {
            id: iconDrag
            target: null
            dragThreshold: 8
            onActiveChanged: {
                if (active) { root.shell.dragKey = trayIcon.trayKey; marker.Drag.active = true }
                else {
                    if (marker.Drag.active && marker.Drag.drop() === Qt.IgnoreAction) trayIcon.droppedOutside(marker.mapToItem(null, 0, 0))
                    if (root.shell.dragKey === trayIcon.trayKey) root.shell.dragKey = ""
                }
            }
        }
        Item {
            id: marker
            width: 1; height: 1
            x: iconDrag.centroid.position.x; y: iconDrag.centroid.position.y
            Drag.source: trayIcon
            Drag.keys: ["tray-icon"]
            Drag.proposedAction: Qt.MoveAction
            Rectangle {
                anchors.centerIn: parent
                width: root.scaledIcon + 10; height: width; radius: 4
                color: root.shell.alpha(root.shell.background, .94)
                border.color: root.shell.accent; visible: iconDrag.active
                IconImage { anchors.centerIn: parent; implicitWidth: root.scaledIcon; implicitHeight: root.scaledIcon; source: trayIcon.trayItem.icon }
            }
        }
        BarTooltip { anchorItem: trayIcon; shell: root.shell; text: root.tooltipText(trayIcon.trayItem); textFormat: Text.StyledText; hovered: pointer.containsMouse }
    }
    TrayMenu {
        shell: root.shell
        anchorItem: root.menuAnchor || root
        handle: root.menuHandle
        label: root.menuLabel
        popupEnabled: root.popupsAllowed
    }
    TrayManagePopup {
        shell: root.shell; anchorItem: root; popupEnabled: root.popupsAllowed; icons: root.icons; widgets: root.barWidgets
        onRestoreWidget: key => root.shell.moveBarModule(key, root.host.sectionName, root.host.moduleKey, true, true)
        onHideWidget: key => root.shell.moveBarModule(key, "tray", "", false)
    }
}
