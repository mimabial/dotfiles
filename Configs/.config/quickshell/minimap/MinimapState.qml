pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import "Minimap.js" as Minimap

Singleton {
    id: root
    readonly property alias settings: settingsAdapter
    property var themeData: ({})
    readonly property string themeName: themeData.themeName ?? ""
    readonly property string themeAnimStyle: themeData.minimap?.animStyle ?? ""
    readonly property string animStyle: themeAnimStyle ? settings.themeAnimStyles[themeName] ?? themeAnimStyle : settings.animStyle
    readonly property var motion: Minimap.motionFor(animStyle)
    readonly property var animStyles: Minimap.ANIM_STYLES
    readonly property int flashDuration: 3200
    readonly property real fadeLead: 1.8
    readonly property real progressEpsilon: 0.002
    property var alerts: ({})
    property int numberFlash: 0
    property real notifiedThrough: Date.now()
    readonly property bool hasAlerts: Object.keys(alerts).length > 0
    property var openSpecialByMonitor: ({})
    readonly property var shownWorkspace: {
        const monitor = Hyprland.focusedMonitor
        const special = openSpecialByMonitor[monitor?.name] ?? monitor?.lastIpcObject?.specialWorkspace?.name
        return special && Hyprland.workspaces.values.find(workspace => workspace.name === special) || Hyprland.focusedWorkspace
    }
    readonly property var activeAddress: Minimap.normalizeAddress(Hyprland.activeToplevel?.address
        ?? Hyprland.toplevels.values.find(top => top.lastIpcObject.focusHistoryID === 0 && top.lastIpcObject.workspace?.name === shownWorkspace?.name)?.address)

    function recordOpenSpecial(eventData) {
        const comma = eventData.lastIndexOf(",")
        openSpecialByMonitor = Object.assign({}, openSpecialByMonitor, { [eventData.slice(comma + 1)]: eventData.slice(0, comma) })
    }
    function alertTarget() { return Minimap.pickAlertTarget(alerts) }
    function setAnimStyle(style) {
        if (themeAnimStyle) settings.themeAnimStyles = Object.assign({}, settings.themeAnimStyles, { [themeName]: style })
        else settings.animStyle = style
    }
    function focusExpression(address) { return 'hl.dsp.focus({ window = "address:' + address + '" })' }
    function addAlert(address, level) {
        if (!settings.attention || !address || address === activeAddress) return
        alerts = Object.assign({}, alerts, { [address]: { level: Math.max(level, alerts[address]?.level ?? 0), at: Date.now() } })
    }
    function raiseAlert(names, level) {
        if (!settings.attention) return
        const address = Minimap.matchWindow(names, Minimap.clientsOf(Hyprland.toplevels.values, true))
        if (address) addAlert(address, level)
        else {
            numberFlash = Math.max(numberFlash, level)
            flashTimer.restart()
        }
    }
    function keepAlerts(keep) {
        const kept = Object.keys(alerts).filter(keep)
        if (kept.length < Object.keys(alerts).length) alerts = kept.reduce((next, address) => { next[address] = alerts[address]; return next }, {})
    }
    onActiveAddressChanged: {
        const focused = [activeAddress].concat((Hyprland.activeToplevel?.lastIpcObject.grouped ?? []).map(Minimap.normalizeAddress))
        keepAlerts(address => !focused.includes(address))
    }

    Timer { id: flashTimer; interval: root.flashDuration; onTriggered: root.numberFlash = 0 }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "urgent") root.addAlert(Minimap.normalizeAddress(event.data), Minimap.MINOR)
            else if (event.name === "activespecial") root.recordOpenSpecial(event.data)
        }
    }
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() {
            const live = Hyprland.toplevels.values.map(top => Minimap.normalizeAddress(top.address))
            root.keepAlerts(address => live.includes(address))
        }
    }
    Connections {
        target: Notifications
        function onReportChanged() {
            const fresh = (Notifications.report.entries ?? []).filter(entry => entry.ts > root.notifiedThrough)
            if (!fresh.length) return
            root.notifiedThrough = Math.max(...fresh.map(entry => entry.ts))
            for (const entry of fresh)
                root.raiseAlert([entry.app, entry.desktop, String(entry.icon ?? "").split("/").pop().replace(/\.[^.]*$/, "")],
                    entry.urgency === "CRITICAL" ? Minimap.CRITICAL : Minimap.MINOR)
        }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.cache/hypr/render/quickshell/theme.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.themeData = JSON.parse(text()) }
            catch (error) { console.warn("minimap theme: " + error) }
        }
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/minimap.json"
        blockLoading: true
        printErrors: false
        onAdapterUpdated: {
            writeAdapter()
            if (!root.settings.attention) root.alerts = ({})
        }
        JsonAdapter {
            id: settingsAdapter
            property string animStyle: "smooth"
            property var themeAnimStyles: ({})
            property bool attention: true
            property bool showFloating: false
            property bool stateMarkers: true
            property bool boxActions: false
            property bool dragReorder: false
        }
    }
    IpcHandler {
        target: "minimap"
        function alert(app: string, level: string): void { root.raiseAlert([app], level === "critical" ? Minimap.CRITICAL : Minimap.MINOR) }
        function clear(): void { root.alerts = ({}) }
        function jump(): void {
            const target = root.alertTarget()
            if (target) Hyprland.dispatch(root.focusExpression(target))
        }
        function state(): string { return JSON.stringify({ alerts: root.alerts, numberFlash: root.numberFlash, target: root.alertTarget() }) }
    }
}
