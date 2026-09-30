pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.Commons as Commons
import "dock" as Dock

PopupCard {
    id: root
    required property var taskbar
    popupName: "taskbar"
    wantsKeyboard: true
    contentWidth: Commons.Style.space(280)
    contentHeight: actionHost.implicitHeight + padding * 2
    keyboardHint: "↑↓ move · Enter select · ←/Esc back"
    padding: Commons.Style.space(4)
    background: Commons.Color.menu.background
    borderColor: Commons.Color.menu.border
    property var record: null
    property int selectedWindowIdx: -1
    readonly property var actionWindows: record ? taskbar.windowsFor(record) : []
    readonly property var desktopActions: {
        const entry = record ? taskbar.entryFor(record) : null
        return entry && entry.actions ? entry.actions : []
    }
    component ContextRow: Dock.DockMenuRow {
        menuWidth: actionColumn.width
        function activateKeyboard() { triggered() }
    }
    component MenuDivider: Dock.DockMenuDivider { menuWidth: actionColumn.width }

    function openActions(item, anchor) {
        if (!popupEnabled) return
        taskbar.popupAnchor = anchor
        record = item
        selectedWindowIdx = -1
        shell.popupCenteredName = ""
        shell.popupName = popupName
        resumeKeyboard()
    }
    function minimizeSelected() {
        const visible = actionWindows.filter(window => !taskbar.windowParked(window))
        const selected = actionWindows[selectedWindowIdx]
        const target = selected || visible.find(window => window.address === taskbar.activeAddress) || visible[0]
        if (target && shell.dock) shell.dock.minimizeToplevel(target.address)
        shell.closePopup()
    }
    function closeWindows() {
        for (const window of actionWindows)
            if (window.toplevel && window.toplevel.wayland) window.toplevel.wayland.close()
        shell.closePopup()
    }
    Item {
        id: actionHost
        width: parent.width
        implicitHeight: actionColumn.implicitHeight
        height: implicitHeight
        Column {
            id: actionColumn
            width: parent.width
            spacing: Commons.Style.space(2)
            ContextRow {
                visible: root.actionWindows.length > 0
                text: root.actionWindows.length > 1 ? "Windows (" + root.actionWindows.length + ")" : "Active Window"
                isHeader: true
            }
            Repeater {
                model: root.actionWindows
                delegate: ContextRow {
                    id: windowAction
                    required property var modelData
                    required property int index
                    text: root.taskbar.windowRowLabel(modelData)
                    isWindowRow: true
                    winFocused: modelData.address === root.taskbar.activeAddress
                    winParked: root.taskbar.windowParked(modelData)
                    checked: root.selectedWindowIdx === index
                    onTriggered: { root.taskbar.focusWindow(modelData); root.shell.closePopup() }
                }
            }
            MenuDivider { visible: root.actionWindows.length > 0 }
            Repeater {
                model: root.desktopActions
                delegate: ContextRow {
                    id: desktopAction
                    required property var modelData
                    text: String(modelData.name || modelData.id || "Action")
                    onTriggered: {
                        if (modelData.execute) modelData.execute()
                        else if (modelData.command) Quickshell.execDetached(modelData.command)
                        root.shell.closePopup()
                    }
                }
            }
            MenuDivider { visible: root.desktopActions.length > 0 }
            ContextRow {
                visible: root.desktopActions.length === 0
                text: root.actionWindows.length ? "New Window" : "Launch"
                disabled: !root.record || !root.taskbar.entryFor(root.record)
                onTriggered: { root.taskbar.launch(root.record); root.shell.closePopup() }
            }
            ContextRow {
                visible: root.taskbar.pins && root.record !== null
                text: root.taskbar.isPinned(root.record) ? "Unpin from taskbar" : "Pin to taskbar"
                onTriggered: { root.taskbar.togglePin(root.record); root.shell.closePopup() }
            }
            ContextRow {
                visible: !!root.shell.dock && root.shell.dock.minimizeMode !== "off" && root.actionWindows.length > 0
                text: "Minimize Window"
                disabled: (root.selectedWindowIdx >= 0 && root.taskbar.windowParked(root.actionWindows[root.selectedWindowIdx]))
                    || !root.actionWindows.some(window => !root.taskbar.windowParked(window))
                onTriggered: root.minimizeSelected()
            }
            ContextRow {
                visible: root.actionWindows.length > 0
                text: root.actionWindows.length > 1 ? "Close All Windows" : "Close Window"
                danger: true
                onTriggered: root.closeWindows()
            }
        }
        MouseArea {
            anchors.fill: parent
            z: 10
            acceptedButtons: Qt.NoButton
            onWheel: wheel => {
                if (!wheel.angleDelta.y || root.actionWindows.length <= 1) return
                const focused = root.actionWindows.findIndex(window => window.address === root.taskbar.activeAddress)
                const current = root.selectedWindowIdx < 0 ? Math.max(0, focused) : root.selectedWindowIdx
                root.selectedWindowIdx = (current + (wheel.angleDelta.y > 0 ? -1 : 1) + root.actionWindows.length) % root.actionWindows.length
            }
        }
    }
}
