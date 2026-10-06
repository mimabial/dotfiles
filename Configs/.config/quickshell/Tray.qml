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
    readonly property var drawerIcons: shell.prefs.trayShowIcons ? icons.filter(item => !shell.trayHidden.includes(String(item.id || "")) && !shell.trayPinned.includes(String(item.id || ""))) : []
    readonly property var pinnedIcons: shell.prefs.trayShowIcons ? icons.filter(item => !shell.trayHidden.includes(String(item.id || "")) && shell.trayPinned.includes(String(item.id || ""))) : []
    readonly property BarModuleLoader host: parent as BarModuleLoader
    readonly property var drawerEntries: {
        const entries = []
        for (const entry of shell.barLayout.tray || []) {
            const key = shell.trayKey("tray", entry), icon = typeof entry === "string" && entry.startsWith("icon:") ? entry.slice(5) : ""
            const data = icon ? drawerIcons.find(item => String(item.id) === icon) : { key, section: "tray", entry }
            if (data) entries.push({ key, data, widget: !icon })
        }
        for (const data of drawerIcons) {
            const key = shell.trayKey("tray", "icon:" + data.id)
            if (!entries.some(entry => entry.key === key)) entries.push({ key, data, widget: false })
        }
        return entries
    }
    readonly property var hostedEntries: drawerEntries.filter(entry => entry.widget).map(entry => entry.data)
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
        Qt.callLater(() => shell.moveBarModule(key, "tray", before, false))
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
    property bool popupHold: false
    // hosted widgets load with the flyout, and some report their state only later;
    // keeping the cells of those shown last time stops the grid shifting under the pointer
    property var shownKeys: []
    function remember(key, shown) {
        if (shownKeys.includes(key) !== shown) shownKeys = shown ? shownKeys.concat(key) : shownKeys.filter(item => item !== key)
    }
    readonly property bool popupOwned: ownsPopup()
    readonly property bool draggingContent: drawerEntries.some(entry => entry.key === shell.dragKey)
    readonly property bool expanded: popupHold || popupOwned || draggingContent
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
                else if (button === Qt.LeftButton) {
                    const reopen = !root.popupOwned && !root.popupHold
                    root.shell.closePopup()
                    root.popupHold = reopen
                }
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
            visible: root.pinnedIcons.length > 0
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
                    model: root.pinnedIcons
                    delegate: Item {
                        id: pin
                        required property var modelData
                        implicitWidth: root.scaledIcon; implicitHeight: root.scaledIcon
                        IconImage { anchors.fill: parent; source: pin.modelData.icon }
                        MouseArea {
                            id: pinMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            hoverEnabled: true
                            onClicked: event => root.activateIcon(pin.modelData, event.button, pin)
                            onWheel: event => pin.modelData.scroll(event.angleDelta.y, false)
                        }
                        BarTooltip { anchorItem: pin; shell: root.shell; text: pin.modelData.tooltipTitle || pin.modelData.title || pin.modelData.id; hovered: pinMouse.containsMouse }
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
        // drag and drop stays within one window, so a widget dragged out of the
        // flyout lands in whichever bar section lies under the release point
        function dropOnBar(key, position) {
            const barY = position.y + (onTop ? -bar.margins.top : bar.height + bar.margins.bottom - height)
            if (barY < 0 || barY > bar.height) return
            const placement = bar.gapPlacement(position.x - bar.margins.left)
            Qt.callLater(() => root.shell.moveBarModule(key, placement.section, placement.target, false))
        }
        screen: bar ? bar.screen : null
        visible: root.expanded && root.drawerEntries.length > 0
        onVisibleChanged: if (visible) anchorX = bar.margins.left + chevron.mapToItem(null, chevron.width / 2, 0).x
        color: "transparent"
        anchors.left: true; anchors.right: true; anchors.top: onTop; anchors.bottom: !onTop
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "hypr-shell-bar"
        WlrLayershell.keyboardFocus: root.popupOwned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        implicitHeight: (bar ? bar.height + bar.margins.top + bar.margins.bottom : 0) + Style.popupGap + card.height
        mask: Region { item: card }
        // a popup anchored in here may get the keyboard instead of the bar; route it the same way
        Item { anchors.fill: parent; focus: true; Keys.onPressed: event => { if (root.shell.popupCard) event.accepted = root.shell.popupCard.handleKey(event) } }
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
                    model: overflow.visible ? root.drawerEntries : []
                    delegate: TraySlot {}
                }
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
        readonly property bool live: !widget || host.item !== null && host.moduleVisible(host.item)
        property bool reported: false
        visible: live || root.shownKeys.includes(trayKey)
        // recorded only while shown: tearing the flyout down reports its widgets hidden
        function note() { if (widget && overflow.visible && (live || reported)) { reported = true; root.remember(trayKey, live) } }
        onLiveChanged: note()
        Component.onCompleted: note()
        Component.onDestruction: if (widget && !reported) root.remember(trayKey, false)
        width: Math.max(root.cellSize, widget ? host.implicitWidth : 0); height: root.cellSize
        Rectangle { anchors.fill: parent; visible: mouse.containsMouse; radius: root.radius; color: root.shell.hoverFill() }
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
        IconImage { anchors.centerIn: parent; width: root.scaledIcon; height: root.scaledIcon; visible: !slot.widget; source: slot.widget ? "" : slot.modelData.data.icon }
        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: !slot.widget
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            hoverEnabled: true
            onClicked: event => root.activateIcon(slot.modelData.data, event.button, slot)
            onWheel: event => slot.modelData.data.scroll(event.angleDelta.y, false)
        }
        DragHandler {
            id: iconDrag
            target: null
            enabled: !slot.widget
            dragThreshold: 8
            onActiveChanged: {
                if (active) { root.shell.dragKey = slot.trayKey; iconMarker.Drag.active = true }
                else {
                    if (iconMarker.Drag.active) iconMarker.Drag.drop()
                    if (root.shell.dragKey === slot.trayKey) root.shell.dragKey = ""
                }
            }
        }
        Item {
            id: iconMarker
            width: 1; height: 1
            x: iconDrag.centroid.position.x; y: iconDrag.centroid.position.y
            Drag.source: slot
            Drag.keys: ["tray-icon"]
            Drag.proposedAction: Qt.MoveAction
            Rectangle {
                anchors.centerIn: parent
                width: root.scaledIcon + 10; height: width; radius: 4
                color: root.shell.alpha(root.shell.background, .94)
                border.color: root.shell.accent; visible: iconDrag.active
                IconImage { anchors.centerIn: parent; implicitWidth: root.scaledIcon; implicitHeight: root.scaledIcon; source: slot.widget ? "" : slot.modelData.data.icon }
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
        BarTooltip { anchorItem: slot; shell: root.shell; text: slot.widget ? "" : (slot.modelData.data.tooltipTitle || slot.modelData.data.title || slot.modelData.data.id); hovered: mouse.containsMouse }
    }
    TrayMenu {
        shell: root.shell
        anchorItem: root.menuAnchor || root
        handle: root.menuHandle
        label: root.menuLabel
        popupEnabled: root.popupsAllowed
    }
    TrayManagePopup {
        shell: root.shell; anchorItem: root; popupEnabled: root.popupsAllowed; icons: root.icons; hostedEntries: root.hostedEntries
        onRestore: key => root.shell.moveBarModule(key, root.host.sectionName, root.host.moduleKey, true)
    }
}
