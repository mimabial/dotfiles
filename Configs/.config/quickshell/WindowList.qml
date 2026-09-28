pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "taskbar/AppModel.js" as AppModel
import "dock/DockModel.js" as DockModel

Item {
    id: root
    required property var shell
    property bool popupEnabled: true
    readonly property var box: shell.style.box("taskbar")
    property int iconSize: 18
    readonly property int scaledIcon: Math.round(box.iconSize !== undefined ? box.iconSize : iconSize)
    readonly property int slotSpacing: box.spacing !== undefined ? box.spacing : 2
    readonly property var buttonBox: shell.style.box("#taskbar button")
    readonly property real buttonInset: Math.max(buttonBox.borderWidth, buttonBox.borderBottomWidth || 0)
    readonly property real buttonWidth: Math.max(Style.px(24), scaledIcon + buttonBox.margin[1] + buttonBox.margin[3] + buttonBox.padding[1] + buttonBox.padding[3] + 2 * buttonInset)
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.borderWidth
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.borderWidth
    implicitWidth: slots.length ? strip.implicitWidth + spanX : 0
    implicitHeight: slots.length ? strip.implicitHeight + spanY : 0
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
        const fingerprint = AppModel.windowFingerprint(windows)
        if (fingerprint === lastFingerprint) return
        lastFingerprint = fingerprint
        const next = AppModel.recordsFor(windows)
        if (!AppModel.sameKeys(next, slots)) slots = next
    }
    onWindowsChanged: refreshSlots()
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
        const matches = AppModel.windowsFor(record, windows)
        if (!matches.length) { launch(record); return }
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
    function windowsFor(record) { return AppModel.windowsFor(record, windows) }

    Row {
        id: strip
        anchors.left: parent.left
        anchors.leftMargin: root.box.margin[3] + root.box.padding[3] + root.box.borderWidth
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: (root.box.margin[0] + root.box.padding[0] - root.box.margin[2] - root.box.padding[2]) / 2
        spacing: root.slotSpacing
        Repeater {
            model: root.slots
            delegate: Item {
                id: slot
                required property var modelData
                readonly property var matched: AppModel.windowsFor(modelData, root.windows)
                property int selectedWindowIdx: -1
                readonly property bool running: matched.length > 0
                readonly property bool active: matched.some(window => window.address === root.activeAddress)
                    || (!!root.activeAppId && String(modelData.desktopId || "").toLowerCase() === root.activeAppId)
                readonly property bool urgent: !active && !!root.shell.dock && matched.some(window => root.shell.dock.urgentMap[window.address])
                readonly property color indicatorForeground: root.shell.dock ? root.shell.dock.dockForeground : root.shell.foreground
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
                width: root.buttonWidth
                height: root.scaledIcon + box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * borderInset
                Rectangle {
                    id: frame
                    anchors.fill: parent
                    anchors.topMargin: slot.box.margin[0]; anchors.rightMargin: slot.box.margin[1]
                    anchors.bottomMargin: slot.box.margin[2]; anchors.leftMargin: slot.box.margin[3]
                    radius: root.shell.moduleRadius
                    color: slot.boxColor("backgroundColor", "backgroundColor", root.shell.background)
                    border.color: slot.boxColor("borderColor", "borderColor", root.shell.foreground)
                    border.width: taskSideBorder.replacesBorder ? 0 : slot.box.borderWidth
                }
                SideBorder { id: taskSideBorder; shell: root.shell; host: slot; hovered: mouse.containsMouse }
                IconImage {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    width: root.scaledIcon; height: root.scaledIcon
                    source: root.iconFor(slot.modelData)
                }
                Row {
                    id: indicators
                    visible: slot.running
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
                            color: focused ? root.shell.accent : parked ? "transparent" : slot.urgent ? root.shell.urgent : root.shell.alpha(slot.indicatorForeground, 0.88)
                            border.color: focused ? Qt.rgba(0, 0, 0, 0.45) : parked ? (slot.urgent ? root.shell.urgent : root.shell.alpha(slot.indicatorForeground, 0.88)) : Qt.rgba(0, 0, 0, 0.45)
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
                            color: root.shell.alpha(slot.indicatorForeground, 0.20)
                            border.color: Qt.rgba(0, 0, 0, 0.35)
                            border.width: 1
                            Text {
                                id: overflowText
                                anchors.centerIn: parent
                                text: "+" + (slot.matched.length - indicators.count)
                                textFormat: Text.PlainText
                                color: slot.indicatorForeground
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
                        if (event.button === Qt.RightButton) menu.openActions(slot.modelData, slot)
                        else if (event.button === Qt.MiddleButton) root.launch(slot.modelData)
                        else if (slot.selectedWindowIdx >= 0 && slot.selectedWindowIdx < slot.matched.length)
                            root.focusWindow(slot.matched[slot.selectedWindowIdx])
                        else root.activate(slot.modelData)
                        slot.selectedWindowIdx = -1
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
