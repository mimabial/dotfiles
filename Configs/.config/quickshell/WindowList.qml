pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "taskbar/AppModel.js" as AppModel
import "dock/DockModel.js" as DockModel

Item {
    id: root
    required property var shell
    property bool popupEnabled: true
    property bool pins: false
    property bool dash: false
    property var pinned: []
    readonly property bool ungroup: shell.layoutName === "winbar" && shell.prefs.winbarCombine === "never"
    readonly property bool combinedLabels: shell.layoutName === "winbar" && shell.prefs.winbarButtonType === "icon-label"
    readonly property int activeDashWidth: Style.px(16)
    readonly property var box: shell.style.box("taskbar")
    property int iconSize: 18
    readonly property int scaledIcon: Math.round(box.iconSize !== undefined ? box.iconSize : iconSize)
    readonly property int slotSpacing: box.spacing !== undefined ? box.spacing : 2
    readonly property var buttonBox: shell.style.box("#taskbar button")
    readonly property real buttonInset: Math.max(buttonBox.borderWidth, buttonBox.borderBottomWidth || 0)
    readonly property real buttonWidth: Math.max(Style.px(24), scaledIcon + buttonBox.margin[1] + buttonBox.margin[3] + buttonBox.padding[1] + buttonBox.padding[3] + 2 * buttonInset)
    readonly property real buttonHeight: scaledIcon + buttonBox.margin[0] + buttonBox.margin[2] + buttonBox.padding[0] + buttonBox.padding[2] + 2 * buttonInset
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.borderWidth
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.borderWidth
    implicitWidth: slots.length ? strip.implicitWidth + spanX : 0
    implicitHeight: slots.length ? buttonHeight + spanY : 0
    visible: slots.length > 0

    property Item popupAnchor: root
    property var slots: []
    property int windowSerial: 0
    readonly property var windows: windowDescriptors()
    readonly property string activeAddress: (shell.dock && shell.dock.activeWindowAddress)
        || DockModel.windowAddress(Hyprland.activeToplevel)
    readonly property string activeAppId: ToplevelManager.activeToplevel
        ? String(ToplevelManager.activeToplevel.appId || "").toLowerCase() : ""
    property string lastFingerprint: "\u0000"

    function windowDescriptors() {
        const serial = windowSerial
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : []
        const result = []
        for (const toplevel of list) {
            if (!toplevel) continue
            const ipc = toplevel.lastIpcObject || {}
            const wayland = toplevel.wayland || {}
            const workspace = toplevel.workspace || ipc.workspace || {}
            result.push({
                address: DockModel.windowAddress(toplevel) || DockModel.windowAddress(ipc),
                appId: String(wayland.appId || ""),
                cls: String(ipc.class || ipc.initialClass || ""),
                title: String(toplevel.title || ipc.title || ""),
                workspaceName: String(workspace.name || ""),
                toplevel: toplevel
            })
        }
        return result
    }

    function refreshSlots() {
        const fingerprint = AppModel.windowFingerprint(windows) + "\u0001" + windows.map(window => window.address).join("\u0002") + "\u0001" + pinned.join("\u0002") + "\u0001" + ungroup
        if (fingerprint === lastFingerprint) return
        lastFingerprint = fingerprint
        const groups = AppModel.withPins(pinned, AppModel.recordsFor(windows))
        const next = []
        for (const record of groups) {
            const matches = ungroup ? AppModel.windowsFor(record, windows) : []
            if (!matches.length) next.push(record)
            else for (const window of matches)
                next.push({key: record.key + ":" + window.address, desktopId: record.desktopId, address: window.address})
        }
        if (!AppModel.sameKeys(next, slots)) slots = next
    }
    onWindowsChanged: refreshSlots()
    onPinnedChanged: refreshSlots()
    onUngroupChanged: refreshSlots()
    function isPinned(record) { return !!record && pinned.some(id => String(id).toLowerCase() === String(record.desktopId).toLowerCase()) }
    function togglePin(record) {
        pinned = isPinned(record) ? pinned.filter(id => String(id).toLowerCase() !== String(record.desktopId).toLowerCase()) : pinned.concat(record.desktopId)
        pinsFile.setText(JSON.stringify(pinned, null, 2) + "\n")
    }
    function movePin(source, target, after) {
        const next = pinned.slice()
        const from = next.findIndex(id => String(id).toLowerCase() === String(source.desktopId).toLowerCase())
        if (from < 0) return
        const moved = next.splice(from, 1)[0]
        const to = next.findIndex(id => String(id).toLowerCase() === String(target.desktopId).toLowerCase())
        if (to < 0) return
        next.splice(to + (after ? 1 : 0), 0, moved)
        pinned = next
        pinsFile.setText(JSON.stringify(next, null, 2) + "\n")
    }
    FileView {
        id: pinsFile
        path: root.pins ? root.shell.home + "/.config/quickshell/taskbar/pins.json" : ""
        printErrors: false
        onLoaded: { try { root.pinned = JSON.parse(text()) } catch (error) { root.pinned = [] } }
    }
    Component.onCompleted: refreshSlots()

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const name = String(event.name || "")
            if (name.includes("window") || name === "configreloaded") root.windowSerial++
        }
    }
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root.windowSerial++ }
    }
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { root.windowSerial++ }
    }
    function relatedIds(wanted, found) {
        const a = wanted.toLowerCase(), b = found.toLowerCase()
        if (!a || !b) return false
        return a === b || a.includes(b) || b.includes(a)
    }
    function entryFor(record) {
        const id = String(record && record.desktopId || "")
        if (!id) return null
        const exact = DesktopEntries.byId(id) || DesktopEntries.byId(id + ".desktop")
        if (exact) return exact
        const guess = DesktopEntries.heuristicLookup(id)
        return guess && relatedIds(id, String(guess.id || "")) ? guess : null
    }
    function labelFor(record) {
        const entry = entryFor(record)
        return String(record.label || (entry && entry.name) || record.desktopId || "Application")
    }
    function iconFor(record) {
        const entry = entryFor(record)
        const icon = String(record.icon || (entry && entry.icon) || record.desktopId || "application-x-executable")
        const source = icon.startsWith("/") ? "file://" + icon : Quickshell.iconPath(icon, true)
        return source || Quickshell.iconPath("application-x-executable", true)
    }
    function launch(record) {
        const entry = entryFor(record)
        if (entry) entry.execute()
    }
    function focusWindow(window) {
        if (!window) return
        const address = String(window.address || "")
        if (/^(0x)?[0-9a-f]+$/i.test(address)) {
            if (windowParked(window) && shell.dock && shell.dock.restoreWindow(address, "")) return
            const selector = "address:" + (address.startsWith("0x") ? address : "0x" + address)
            Quickshell.execDetached(["hyprctl", "eval", "local w=hl.get_config('cursor.no_warps');hl.config({cursor={no_warps=true}});hl.exec_scheduled_prop_refresh_immediately();hl.dispatch(hl.dsp.focus({window='" + selector + "'}));hl.config({cursor={no_warps=w}})"])
        } else if (window.toplevel && window.toplevel.wayland) window.toplevel.wayland.activate()
    }
    function activate(record) {
        const matches = windowsFor(record)
        if (!matches.length) { launch(record); return }
        if (record.address) { focusWindow(matches[0]); return }
        const index = AppModel.nextWindowIndex(matches, activeAddress)
        focusWindow(matches[index])
    }
    function windowParked(window) {
        if (shell.dock) return shell.dock.isWinParkedLive(window)
        const workspace = String(window && window.workspaceName || "")
        return workspace === "special:minimized" || workspace.startsWith("special:minimized-")
    }
    function windowRowLabel(window) {
        if (shell.dock) return shell.dock.windowRowLabel(window)
        const workspace = DockModel.workspaceLabel(window.workspaceName)
        const title = String(window.title || "Window")
        return workspace ? "[" + workspace + "] " + title : title
    }
    function tooltipSuffix(matches) {
        if (!matches.length) return ""
        if (matches.every(window => windowParked(window))) return "[minimized]"
        const focused = Hyprland.focusedWorkspace
        if (focused && matches.some(window => window.workspaceName === focused.name)) return ""
        const first = matches.find(window => !windowParked(window))
        const workspace = first ? DockModel.workspaceLabel(shell.dock ? shell.dock.liveWsNameOf(first) : first.workspaceName) : ""
        return workspace ? "[" + workspace + "]" : ""
    }
    function windowsFor(record) { return record && record.address ? windows.filter(window => window.address === record.address) : AppModel.windowsFor(record, windows) }

    Row {
        id: strip
        anchors.left: parent.left
        anchors.leftMargin: root.box.margin[3] + root.box.padding[3] + root.box.borderWidth
        anchors.top: parent.top; anchors.topMargin: root.box.margin[0] + root.box.padding[0] + root.box.borderWidth
        anchors.bottom: parent.bottom; anchors.bottomMargin: root.box.margin[2] + root.box.padding[2] + root.box.borderWidth
        spacing: root.slotSpacing
        Repeater {
            model: root.slots
            delegate: Item {
                id: slot
                required property var modelData
                readonly property var matched: root.windowsFor(modelData)
                property int selectedWindowIdx: -1
                property bool wasDragged: false
                readonly property bool running: matched.length > 0
                readonly property bool labeled: running && (root.ungroup || root.combinedLabels)
                readonly property string buttonLabel: modelData.address && matched.length
                    ? matched[0].title || root.labelFor(modelData) : root.labelFor(modelData)
                readonly property bool active: matched.some(window => window.address === root.activeAddress)
                    || (!modelData.address && !!root.activeAppId && String(modelData.desktopId || "").toLowerCase() === root.activeAppId)
                readonly property bool urgent: !active && !!root.shell.dock && matched.some(window => root.shell.dock.urgentMap[window.address])
                property real pulse: 1
                SequentialAnimation on pulse {
                    running: slot.urgent
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.35; duration: 650; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.35; to: 1; duration: 650; easing.type: Easing.InOutQuad }
                }
                readonly property var box: root.shell.style.box(active ? "#taskbar button.active" : "#taskbar button")
                readonly property real borderInset: Math.max(box.borderWidth, box.borderBottomWidth || 0)
                function boxColor(key, hoverKey, fallback) {
                    const hovered = mouse.containsMouse && box.hover && hoverKey in box.hover
                    const spec = hovered ? box.hover[hoverKey] : box[key]
                    if (!spec) return "transparent"
                    return Array.isArray(spec) ? root.shell.alpha(root.shell.role(spec[0], fallback), spec[1] ?? 1) : root.shell.role(spec, fallback)
                }
                width: root.buttonWidth + (slot.labeled ? root.scaledIcon * 5 : 0)
                height: strip.height
                Rectangle {
                    id: frame
                    anchors.fill: parent
                    anchors.topMargin: slot.box.margin[0]; anchors.rightMargin: slot.box.margin[1]
                    anchors.bottomMargin: slot.box.margin[2]; anchors.leftMargin: slot.box.margin[3]
                    radius: slot.box.borderRadius ?? root.shell.moduleRadius
                    color: slot.boxColor("backgroundColor", "backgroundColor", root.shell.background)
                    border.color: slot.boxColor("borderColor", "borderColor", root.shell.foreground)
                    border.width: taskSideBorder.replacesBorder ? 0 : slot.box.borderWidth
                }
                SideBorder { id: taskSideBorder; shell: root.shell; host: slot; hovered: mouse.containsMouse }
                IconImage {
                    id: icon
                    x: slot.labeled ? slot.box.margin[3] + slot.box.padding[3] : (slot.width - width) / 2
                    y: (slot.height - height + slot.box.margin[0] + slot.box.padding[0] - slot.box.margin[2] - slot.box.padding[2]) / 2
                    width: root.scaledIcon; height: root.scaledIcon
                    source: root.iconFor(slot.modelData)
                }
                Text {
                    visible: slot.labeled
                    x: icon.x + icon.width + Style.sm
                    width: slot.width - x - slot.box.margin[1] - slot.box.padding[1]
                    anchors.verticalCenter: icon.verticalCenter
                    text: slot.buttonLabel
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: root.shell.foreground
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.bodySmall
                }
                Rectangle {
                    visible: root.dash && slot.running
                    anchors.horizontalCenter: frame.horizontalCenter
                    anchors.bottom: frame.bottom; anchors.bottomMargin: Style.xxs
                    width: slot.active ? root.activeDashWidth : indicators.dotSize; height: indicators.dotSize; radius: height / 2
                    color: slot.urgent ? root.shell.urgent : mouse.containsMouse ? root.shell.role("hvr_br", root.shell.accent)
                        : slot.active ? root.shell.accent : root.shell.alpha(root.shell.foreground, .5)
                    opacity: slot.urgent ? 0.4 + 0.6 * slot.pulse : 1
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                }
                Row {
                    id: indicators
                    visible: slot.running && !root.dash
                    readonly property int count: slot.matched.length > 5 ? 2 : slot.matched.length
                    readonly property int dotSize: Style.px(3)
                    spacing: Style.px(1)
                    x: (slot.width - width) / 2
                    y: slot.height - height - Style.px(1)
                    scale: Math.min(1, slot.width / Math.max(1, implicitWidth))
                    transformOrigin: Item.Bottom
                    Repeater {
                        model: indicators.count
                        delegate: Rectangle {
                            required property int index
                            readonly property var window: slot.matched.length > 5 && slot.active
                                ? (index === 0 ? slot.matched.find(entry => entry.address === root.activeAddress)
                                    : slot.matched.find(entry => entry.address !== root.activeAddress)) : slot.matched[index]
                            readonly property bool parked: root.windowParked(window)
                            readonly property bool focused: !parked && window.address === root.activeAddress
                            width: focused ? Style.px(7) : indicators.dotSize
                            height: indicators.dotSize
                            radius: Math.min(width, height) / 2
                            color: focused ? root.shell.accent : parked ? "transparent" : slot.urgent ? root.shell.urgent : root.shell.alpha(root.shell.foreground, 0.88)
                            border.color: focused ? Qt.rgba(0, 0, 0, 0.45) : parked ? (slot.urgent ? root.shell.urgent : root.shell.alpha(root.shell.foreground, 0.88)) : Qt.rgba(0, 0, 0, 0.45)
                            border.width: 1
                            opacity: slot.urgent ? 0.4 + 0.6 * slot.pulse : 1
                            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                        }
                    }
                    Item {
                        visible: slot.matched.length > 5
                        width: overflow.width
                        height: overflow.height
                        Rectangle {
                            id: overflow
                            anchors.centerIn: parent
                            width: overflowText.implicitWidth + Style.px(2)
                            height: Style.px(5)
                            radius: height / 2
                            color: root.shell.alpha(root.shell.foreground, 0.20)
                            border.color: Qt.rgba(0, 0, 0, 0.35)
                            border.width: 1
                            Text {
                                id: overflowText
                                anchors.centerIn: parent
                                text: "+" + (slot.matched.length - indicators.count)
                                textFormat: Text.PlainText
                                color: root.shell.foreground
                                font.family: root.shell.fontFamily
                                font.pixelSize: Math.max(7, Style.caption - 4)
                                font.bold: true
                            }
                        }
                    }
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    hoverEnabled: true
                    onPressed: slot.wasDragged = false
                    onExited: slot.selectedWindowIdx = -1
                    onWheel: wheel => {
                        if (!wheel.angleDelta.y || !slot.matched.length) return
                        const step = wheel.angleDelta.y > 0 ? -1 : 1
                        if (slot.matched.length === 1) { root.focusWindow(slot.matched[0]); return }
                        const focused = slot.matched.findIndex(window => window.address === root.activeAddress)
                        const current = slot.selectedWindowIdx < 0 ? Math.max(0, focused) : slot.selectedWindowIdx
                        slot.selectedWindowIdx = (current + step + slot.matched.length) % slot.matched.length
                        tooltip.showNow()
                    }
                    onClicked: event => {
                        if (slot.wasDragged) return
                        if (event.button === Qt.RightButton) menu.openActions(slot.modelData, slot)
                        else if (event.button === Qt.MiddleButton) root.launch(slot.modelData)
                        else if (slot.selectedWindowIdx >= 0 && slot.selectedWindowIdx < slot.matched.length)
                            root.focusWindow(slot.matched[slot.selectedWindowIdx])
                        else root.activate(slot.modelData)
                        slot.selectedWindowIdx = -1
                    }
                }
                DragHandler {
                    id: pinDrag
                    target: null
                    enabled: root.pins && root.shell.layoutName === "winbar" && root.isPinned(slot.modelData)
                    onActiveChanged: {
                        if (active) { slot.wasDragged = true; pinMarker.Drag.active = true }
                        else if (pinMarker.Drag.active) pinMarker.Drag.drop()
                    }
                }
                Item {
                    id: pinMarker
                    width: 1; height: 1
                    x: pinDrag.centroid.position.x; y: pinDrag.centroid.position.y
                    Drag.source: slot
                    Drag.keys: ["taskbar-pin"]
                    Drag.proposedAction: Qt.MoveAction
                }
                DropArea {
                    anchors.fill: parent
                    keys: ["taskbar-pin"]
                    onDropped: drop => {
                        const source = drop.source as Item
                        if (!source || source === slot || source.modelData.desktopId === slot.modelData.desktopId || !root.isPinned(slot.modelData)) return
                        drop.acceptProposedAction()
                        root.movePin(source.modelData, slot.modelData, drop.x >= width / 2)
                    }
                }
                TaskbarTooltip {
                    id: tooltip
                    anchorItem: slot; shell: root.shell
                    appName: root.labelFor(slot.modelData)
                    suffix: root.tooltipSuffix(slot.matched)
                    windows: slot.matched
                    advanced: !root.shell.dock || root.shell.dock.advancedTooltips
                    delay: root.shell.dock ? root.shell.dock.tooltipDelay : 450
                    selectedIndex: slot.selectedWindowIdx
                    windowFocused: function(window) { return window.address === root.activeAddress }
                    windowParked: function(window) { return root.windowParked(window) }
                    windowLabel: function(window) { return root.windowRowLabel(window) }
                    hovered: mouse.containsMouse && (!root.shell.dock || root.shell.dock.showTooltips)
                    blocked: menu.open
                }
            }
        }
    }
    TaskbarPopup { id: menu; anchorItem: root.popupAnchor; shell: root.shell; taskbar: root; popupEnabled: root.popupEnabled }
}
