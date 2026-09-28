pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Item {
    id: root
    required property var shell
    required property var registry
    property bool popupsAllowed: true
    property bool alwaysOpen: false
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
            if (item === root) return true
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
        if (button === Qt.MiddleButton) icon.secondaryActivate()
        else if (button === Qt.LeftButton && !icon.onlyMenu) icon.activate()
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
    readonly property bool popupOwned: ownsPopup()
    readonly property bool dragOver: shell.dragKey !== "" && hover.hovered
    readonly property bool draggingContent: drawerEntries.some(entry => entry.key === shell.dragKey)
    readonly property bool expanded: alwaysOpen || popupHold || popupOwned || chevronDrop.containsDrag || dragOver
        || draggingContent || trayDrag.active
        || (hover.hovered && shell.popupName === "")
    property real reveal: expanded ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    implicitWidth: content.implicitWidth
    implicitHeight: Math.max(content.implicitHeight, scaledIcon + spanY)

    Connections {
        target: root.shell
        function onPopupNameChanged() {
            if (root.shell.popupName === "") root.popupHold = false
        }
        function onPopupCardChanged() {
            if (root.shell.popupCard && !root.ownsPopup()) root.popupHold = false
        }
    }
    HoverHandler { id: hover }
    RowLayout {
        id: content
        anchors.centerIn: parent
        height: root.height
        spacing: root.sectionSpacing
        Item {
            id: iconFrame
            readonly property var box: root.box
            readonly property real radius: root.shell.rounding
            visible: root.reveal > 0 || root.pinnedIcons.length > 0
            Layout.fillHeight: true
            Layout.preferredWidth: frameRow.implicitWidth + root.spanX
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: root.box.margin[0]; anchors.rightMargin: root.box.margin[1]
                anchors.bottomMargin: root.box.margin[2]; anchors.leftMargin: root.box.margin[3]
                radius: sideBorder.radius
                color: root.dragOver ? root.shell.alpha(root.shell.accent, .24) : root.shell.styleColor(root.box.backgroundColor, "transparent")
                border.color: root.dragOver ? root.shell.accent : root.shell.styleColor(root.box.borderColor, "transparent")
                border.width: Math.max(root.borderInset, root.dragOver ? 1 : 0)
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
                Item {
                    id: drawer
                    visible: root.reveal > 0
                    clip: root.reveal < 1
                    Layout.preferredWidth: drawerRow.implicitWidth * root.reveal
                    Layout.preferredHeight: drawerRow.implicitHeight
                    Layout.fillHeight: true
                    RowLayout {
                        id: drawerRow
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        spacing: root.sectionSpacing
                        Repeater {
                            model: root.reveal > 0 ? root.drawerEntries : []
                            delegate: Item {
                                id: slot
                                required property var modelData
                                readonly property bool widget: modelData.widget
                                readonly property string trayKey: modelData.key
                                implicitWidth: widget ? host.implicitWidth : root.scaledIcon
                                implicitHeight: widget ? host.implicitHeight : root.scaledIcon
                                Layout.fillHeight: widget
                                BarModuleLoader {
                                    id: host
                                    height: parent.height
                                    modelData: slot.widget ? slot.modelData.data : ({ entry: "spacer" })
                                    shell: root.shell; registry: root.registry
                                    sectionName: slot.widget ? slot.modelData.data.section : "right"
                                    hosted: true; visible: slot.widget
                                }
                                IconImage { anchors.fill: parent; visible: !slot.widget; source: slot.widget ? "" : slot.modelData.data.icon }
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
                        }
                    }
                }
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
        Text {
            id: chevron
            readonly property var box: root.shell.style.box("tray.chevron")
            text: root.expanded ? "󰅂" : "󰅁"
            color: root.shell.styleColor(chevronMouse.containsMouse && box.hover?.color ? box.hover.color : box.color, root.shell.foreground)
            font.family: root.shell.iconGlyphFont
            font.pixelSize: Style.fontPx(box.fontSize) * root.shell.iconFontScale
            font.weight: box.fontWeight
            Layout.fillHeight: true
            Layout.topMargin: box.margin[0]; Layout.rightMargin: box.margin[1]
            Layout.bottomMargin: box.margin[2]; Layout.leftMargin: box.margin[3]
            verticalAlignment: Text.AlignVCenter
            MouseArea {
                id: chevronMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: event => {
                    if (event.button === Qt.RightButton && root.popupsAllowed) root.shell.togglePopup("tray-manage")
                    else if (event.button === Qt.LeftButton) {
                        if (root.shell.popupName && !root.popupOwned) {
                            root.shell.closePopup()
                            root.popupHold = true
                        } else root.popupHold = !root.popupHold
                    }
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
            }
        }
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
