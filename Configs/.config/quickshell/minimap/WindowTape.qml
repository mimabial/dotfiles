pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs
import qs.modules
import qs.Commons as Commons
import "Minimap.js" as Minimap

Item {
    id: root
    required property var shell
    required property color inactiveColor
    required property Item tabAnchor
    property bool popupEnabled: false
    property real maxWidth: Style.px(200)
    property real gap: Style.px(3)
    readonly property var settings: MinimapState.settings
    readonly property var motion: MinimapState.motion
    readonly property int menuWorkspaces: 10
    readonly property real thickness: Style.controlHeight - Style.xs * 2
    readonly property real stackGap: Math.max(gap, Style.xs)
    readonly property real corner: Math.min(shell.rounding, Style.xxs)
    readonly property real dragThreshold: Style.md
    readonly property var refreshEvents: ["activewindowv2", "openwindow", "closewindow", "movewindowv2", "changefloatingmode", "fullscreen", "pin",
        "togglegroup", "moveintogroup", "moveoutofgroup", "workspacev2", "activespecial", "focusedmonv2", "monitoraddedv2", "monitorremovedv2", "custom"]
    readonly property var workspace: MinimapState.shownWorkspace
    readonly property string tiledLayout: workspace?.lastIpcObject?.tiledLayout ?? ""
    readonly property bool columnDrag: tiledLayout === "scrolling"
    readonly property bool reorderable: settings.dragReorder && tiledLayout !== "monocle"
    readonly property var monitor: workspace?.monitor ?? null
    readonly property var viewport: monitor ? { x: monitor.x, y: monitor.y, width: monitor.width / monitor.scale, height: monitor.height / monitor.scale } : null
    readonly property string activeAddress: MinimapState.activeAddress
    readonly property var columns: viewport ? Minimap.buildColumns(Minimap.clientsOf(workspace.toplevels.values, settings.showFloating), viewport, activeAddress) : []
    readonly property var tape: Minimap.layoutTape(columns, viewport ? thickness / viewport.height : 0, gap, stackGap)
    readonly property var cues: Minimap.attentionFor(MinimapState.alerts, columns)
    readonly property int otherLevel: cues.other
    property string tapeSignature: ""
    property real tapeTotal: 0
    property bool completed: false
    property real scrollTarget: 0
    property real scrollOffset: scrollTarget
    readonly property real viewLength: Math.min(tapeTotal, maxWidth)
    readonly property real maxScroll: Math.max(0, tapeTotal - viewLength)
    property string hoverAddress: ""
    property Item hoverItem: null
    readonly property var shownWindow: hoverAddress ? Minimap.windowAt(columns, hoverAddress) : null
    readonly property var shownToplevel: shownWindow ? Array.from(workspace.toplevels.values).find(top => Minimap.normalizeAddress(top.address) === hoverAddress) ?? null : null
    property Item menuAnchor: null
    property var menuWindow: ({})
    property int dragFrom: -1
    property int dragTarget: -1
    property string swapTarget: ""
    signal wheeled(int delta)
    implicitWidth: Math.min(strip.width, maxWidth)
    implicitHeight: thickness
    MotionBehavior on scrollOffset { WindowMove {} }

    function focusWindow(address) { shell.dispatchWithoutWarp([MinimapState.focusExpression(address)]) }
    function runAction(id, address, workspace) { shell.dispatchWithoutWarp(Minimap.actionCommands(id, address, workspace)) }
    function rowIndex(key) {
        for (let index = 0; index < rows.count; index++)
            if (rows.get(index).key === key) return index
        return -1
    }
    function removeClosed(key) {
        const index = rowIndex(key)
        if (index >= 0 && rows.get(index).closing) rows.remove(index)
    }
    function syncRows() {
        const signature = JSON.stringify(tape.items)
        if (signature === tapeSignature) return
        tapeSignature = signature
        tapeTotal = tape.total
        updateScroll()
        const keys = tape.items.map(item => item.key)
        for (const item of tape.items) {
            const index = rowIndex(item.key)
            if (index < 0) rows.append(Object.assign({ closing: false, fresh: completed }, item))
            else {
                const row = rows.get(index)
                for (const field in item) if (row[field] !== item[field]) rows.setProperty(index, field, item[field])
                if (row.closing) rows.setProperty(index, "closing", false)
            }
        }
        for (let index = 0; index < rows.count; index++)
            if (!keys.includes(rows.get(index).key)) rows.setProperty(index, "closing", true)
    }
    function updateScroll() {
        const focused = tape.items.find(item => item.focused)
        let target = Math.min(scrollTarget, maxScroll)
        if (focused && focused.bx - thickness < target) target = focused.bx - thickness
        else if (focused && focused.bx + focused.bw + thickness > target + viewLength) target = focused.bx + focused.bw + thickness - viewLength
        scrollTarget = Math.max(0, Math.min(target, maxScroll))
    }
    function hoverEntered(address, item) {
        hoverClear.stop()
        hoverAddress = address
        hoverItem = item
    }
    function hoverLeft(address) { if (hoverAddress === address) hoverClear.restart() }
    function openSettings() { shell.togglePopup("workspaces") }
    function secondaryClick(item, window) {
        if (!settings.boxActions) return openSettings()
        menuAnchor = item
        menuWindow = window
        shell.togglePopup("minimap-box")
    }
    function menuItems(window) {
        const act = id => () => root.runAction(id, window.address)
        return [
            { text: "Focus", run: () => root.focusWindow(window.address) },
            { text: window.floating ? "Make tiled" : "Make floating", run: act("float") },
            { text: window.fullscreen ? "Exit fullscreen" : "Fullscreen", run: act("fullscreen") },
            { text: window.pinned ? "Unpin" : "Pin", run: window.floating || window.pinned ? act("pin") : null },
            ...(window.tabbed ? [{ text: "Ungroup tabs", run: act("ungroup") }] : []),
            { text: "Move to workspace", submenu: Array.from({ length: menuWorkspaces }, (_, index) =>
                ({ text: String(index + 1), run: () => root.runAction("moveto", window.address, index + 1) })) },
            null,
            { text: "Close window", run: act("close") },
            { text: "Settings…", run: () => root.openSettings() }
        ]
    }
    function reorder(address) {
        const from = dragFrom, to = dragTarget, target = swapTarget
        dragFrom = -1
        dragTarget = -1
        swapTarget = ""
        if (target) shell.dispatchWithoutWarp([Minimap.windowSwapCommand(address, target)])
        else if (from >= 0 && to >= 0 && from !== to) shell.dispatchWithoutWarp([MinimapState.focusExpression(address)].concat(Minimap.columnSwapCommands(from, to)))
    }
    onTapeChanged: syncRows()
    onMaxScrollChanged: updateScroll()
    Component.onCompleted: { Hyprland.refreshToplevels(); syncRows(); completed = true }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.refreshEvents.includes(event.name)) Hyprland.refreshToplevels()
        }
    }
    Timer { id: hoverClear; interval: 140; onTriggered: { root.hoverAddress = ""; root.hoverItem = null } }
    ListModel { id: rows }

    component WindowMove: NumberAnimation {
        duration: Style.duration(Style.windowMoveAnimation.duration)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Style.windowMoveAnimation.curve
    }
    component Fade: NumberAnimation { duration: 220; easing.type: Easing.InOutSine }

    MouseArea {
        id: view
        anchors.fill: parent
        clip: true
        acceptedButtons: Qt.RightButton
        onClicked: root.openSettings()
        onWheel: wheel => { if (wheel.angleDelta.y) root.wheeled(wheel.angleDelta.y) }

        Item {
            id: strip
            x: -root.scrollOffset
            width: root.tapeTotal
            height: root.thickness
            MotionBehavior on width { WindowMove {} }

            Rectangle {
                readonly property var span: root.tape.spans[root.dragTarget] ?? null
                visible: root.dragFrom >= 0 && span !== null && root.dragTarget !== root.dragFrom
                z: 60
                x: span ? (root.dragTarget > root.dragFrom ? span.start + span.len + root.gap / 2 : span.start - root.gap / 2) - width / 2 : 0
                width: Style.xxs
                height: parent.height
                radius: width / 2
                color: root.shell.accent
            }

            Repeater {
                model: rows
                delegate: Rectangle {
                    id: box
                    required property string key
                    required property string address
                    required property real bx
                    required property real by
                    required property real bw
                    required property real bh
                    required property bool focused
                    required property bool onScreen
                    required property bool floating
                    required property bool pinned
                    required property bool fullscreen
                    required property bool closing
                    required property bool fresh
                    required property string tabsJson
                    readonly property var tabs: tabsJson ? JSON.parse(tabsJson) : []
                    readonly property bool tabbed: tabs.length > 1
                    readonly property bool hot: root.hoverAddress !== "" && !closing
                        && (root.hoverAddress === address || tabs.some(tab => tab.address === root.hoverAddress))
                    readonly property int attention: root.settings.attention ? root.cues.attention[key] ?? 0 : 0
                    readonly property bool dropTarget: root.swapTarget !== "" && root.swapTarget === address
                    readonly property color baseFill: focused || dropTarget ? root.shell.accent : onScreen ? root.shell.foreground : root.inactiveColor
                    readonly property color alertFill: Qt.lighter(fx.tone, 1 + 0.3 * fx.pulse)
                    readonly property color ink: 0.299 * color.r + 0.587 * color.g + 0.114 * color.b > 0.45 ? root.shell.background : root.shell.foreground
                    readonly property var menuWindow: ({ address, floating, pinned, fullscreen, tabbed })
                    property bool arrived: !fresh
                    property real appear: closing || !arrived ? 0 : 1
                    property real engage: attention > 0 ? 1 : 0
                    property real pop: 1
                    property real lift: hot || dropTarget ? root.motion.hover : 1
                    property bool dragging: false
                    property real dragX: 0
                    x: bx
                    y: by
                    width: bw
                    height: bh
                    z: dragging ? 50 : 0
                    scale: Math.max(0.001, appear * pop * lift)
                    radius: root.corner
                    color: engage > 0.001 ? Qt.tint(baseFill, Qt.rgba(alertFill.r, alertFill.g, alertFill.b, engage)) : baseFill
                    opacity: Math.min(1, appear * MinimapState.fadeLead) * fx.flick * (focused || dropTarget || engage > 0.5 ? 1 : hot ? 0.95 : onScreen ? 0.75 : 0.4)
                        * (attention > 0 && !Style.reduceMotion ? (1 + fx.power * fx.pulse) / (1 + fx.power) : 1)
                    transform: Translate { x: box.dragX }
                    MotionBehavior on x { WindowMove {} }
                    MotionBehavior on y { WindowMove {} }
                    MotionBehavior on width { WindowMove {} }
                    MotionBehavior on height { WindowMove {} }
                    MotionBehavior on appear { SpringAnimation { spring: root.motion.k; damping: root.motion.d; epsilon: MinimapState.progressEpsilon } }
                    MotionBehavior on lift { SpringAnimation { spring: 4; damping: 0.45; epsilon: 0.002 } }
                    MotionBehavior on engage { NumberAnimation { duration: 320; easing.type: Easing.InOutSine } }
                    MotionBehavior on color { enabled: !Style.reduceMotion && box.engage < 0.001 && box.attention === 0; ColorAnimation { duration: 260; easing.type: Easing.InOutSine } }
                    MotionBehavior on opacity { enabled: !Style.reduceMotion && box.attention === 0; Fade {} }
                    MotionBehavior on dragX { enabled: !Style.reduceMotion && !box.dragging; WindowMove {} }
                    onFocusedChanged: if (focused && arrived && !Style.reduceMotion) { focusPop.restart(); fx.play("focus") }
                    onAppearChanged: if (closing && appear < 0.01) Qt.callLater(root.removeClosed, key)
                    Component.onCompleted: Qt.callLater(() => { box.arrived = true; if (box.fresh) fx.play("appear") })

                    SequentialAnimation {
                        id: focusPop
                        readonly property bool motionEnabled: !Style.reduceMotion
                        onMotionEnabledChanged: if (!motionEnabled) complete()
                        NumberAnimation { target: box; property: "pop"; to: root.motion.popTo; duration: root.motion.popIn; easing.type: Easing.OutSine }
                        NumberAnimation { target: box; property: "pop"; to: 1; duration: root.motion.popOut; easing.type: Easing.OutBack; easing.overshoot: root.motion.popOvershoot }
                    }
                    StateMarks {
                        z: 4
                        visible: root.settings.stateMarkers && !box.closing
                        pinned: box.pinned
                        fullscreen: box.fullscreen
                        floating: box.floating
                        ink: box.ink
                        corner: root.corner
                    }
                    BoxFx {
                        id: fx
                        z: 5
                        shell: root.shell
                        style: MinimapState.animStyle
                        level: box.attention
                        fill: box.color
                        corner: root.corner
                        onLevelChanged: if (level === 0) play("resolve")
                    }
                    MouseArea {
                        id: body
                        property point pressPoint
                        property bool moved: false
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | (root.settings.boxActions ? Qt.MiddleButton : Qt.NoButton)
                        hoverEnabled: true
                        enabled: !box.closing
                        cursorShape: Qt.PointingHandCursor
                        onPressed: mouse => {
                            if (mouse.button !== Qt.RightButton) return
                            pressPoint = mapToItem(strip, mouse.x, mouse.y)
                            moved = false
                        }
                        onPositionChanged: mouse => {
                            if (!root.reorderable || box.floating || !(pressedButtons & Qt.RightButton)) return
                            const here = mapToItem(strip, mouse.x, mouse.y)
                            if (!moved && Math.hypot(here.x - pressPoint.x, here.y - pressPoint.y) < root.dragThreshold) return
                            if (!moved && root.columnDrag) root.dragFrom = Minimap.slotAt(root.tape.spans, box.bx + box.bw / 2)
                            moved = true
                            box.dragging = true
                            box.dragX = here.x - pressPoint.x
                            if (root.columnDrag) root.dragTarget = Minimap.slotAt(root.tape.spans, here.x)
                            else root.swapTarget = Minimap.swapTargetAt(root.tape.items, here.x, here.y, box.address)
                        }
                        onReleased: {
                            if (!box.dragging) return
                            box.dragging = false
                            box.dragX = 0
                            root.reorder(box.address)
                        }
                        onClicked: mouse => {
                            if (moved) moved = false
                            else if (mouse.button === Qt.MiddleButton) root.runAction("close", box.address)
                            else if (mouse.button === Qt.RightButton) root.secondaryClick(box, box.menuWindow)
                            else root.focusWindow(box.address)
                        }
                        onEntered: root.hoverEntered(box.address, box)
                        onExited: root.hoverLeft(box.address)
                    }
                    Row {
                        id: tabRow
                        readonly property int count: box.tabbed ? box.tabs.length : 0
                        readonly property real nubWidth: count ? (box.width - Style.sm - (count - 1) * spacing) / count : 0
                        x: Style.xxs
                        y: Style.xxs
                        spacing: Style.uiScale
                        opacity: box.tabbed ? 1 : 0
                        visible: opacity > 0.01
                        MotionBehavior on opacity { Fade {} }
                        Repeater {
                            model: tabRow.count
                            Rectangle {
                                id: nub
                                required property int index
                                readonly property var tab: box.tabs[index] ?? null
                                width: Math.max(1, tabRow.nubWidth)
                                height: Math.max(Style.xs, Math.round(box.height * 0.3))
                                radius: height / 2.5
                                color: box.ink
                                opacity: tab?.active ? 0.9 : 0.3
                                MotionBehavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.InOutSine } }
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -Style.uiScale
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton | (root.settings.boxActions ? Qt.MiddleButton : Qt.NoButton)
                                    hoverEnabled: true
                                    enabled: tabRow.visible && !box.closing && nub.tab !== null
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.MiddleButton) root.runAction("close", nub.tab.address)
                                        else if (mouse.button === Qt.RightButton) root.secondaryClick(nub, Object.assign({}, box.menuWindow, { address: nub.tab.address }))
                                        else root.focusWindow(nub.tab.address)
                                    }
                                    onEntered: root.hoverEntered(nub.tab.address, nub)
                                    onExited: root.hoverLeft(nub.tab.address)
                                }
                            }
                        }
                    }
                }
            }
        }

        Repeater {
            model: [false, true]
            Item {
                id: glow
                required property bool modelData
                readonly property bool lit: modelData ? root.scrollOffset < root.maxScroll - 1 : root.scrollOffset > 1
                property real breathe: 0.6
                z: 100
                x: modelData ? parent.width - width : 0
                width: Math.max(Style.lg, root.thickness * 0.6)
                height: parent.height
                opacity: lit ? 1 : 0
                visible: opacity > 0.01
                MotionBehavior on opacity { Fade {} }
                SequentialAnimation on breathe {
                    running: glow.lit && !Style.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 0.5; duration: 900; easing.type: Easing.InOutSine }
                }
                Rectangle {
                    anchors.fill: parent
                    opacity: glow.breathe * 0.7
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: glow.modelData ? "transparent" : root.shell.accent }
                        GradientStop { position: 1; color: glow.modelData ? root.shell.accent : "transparent" }
                    }
                }
                Rectangle {
                    x: glow.modelData ? parent.width - width : 0
                    width: Style.xxs
                    height: parent.height
                    color: root.shell.accent
                    opacity: 0.6 + glow.breathe * 0.4
                }
            }
        }
    }

    FocusTab {
        shell: root.shell
        host: root.tabAnchor
        target: root.hoverItem
        title: root.shell.popupName === "" ? root.shownWindow?.title ?? "" : ""
        appClass: root.shownWindow?.appClass ?? ""
        iconSource: root.shownToplevel ? Commons.WindowApp.lookup(root.shownToplevel).icon : ""
        highlighted: root.hoverAddress === root.activeAddress
    }
    MenuBarPopup {
        anchorItem: root.menuAnchor ?? root
        shell: root.shell
        popupName: "minimap-box"
        popupEnabled: root.popupEnabled
        items: open ? root.menuItems(root.menuWindow) : []
    }
}
