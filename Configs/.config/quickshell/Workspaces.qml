pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.minimap
import "minimap/Minimap.js" as Minimap

Item {
    id: root
    readonly property int slotCount: 20
    readonly property int persistentSlots: 5
    readonly property int compactSlots: 10
    required property var shell
    readonly property var box: shell.style.box("workspaces")
    readonly property color inactiveColor: shell.alpha(shell.foreground, .5)
    readonly property color inactiveWindowColor: shell.alpha(shell.foreground, .10)
    property bool activeOnly: false
    property bool hideActive: false
    property bool popupEnabled: false
    property bool compactStyle: false
    property bool fixedCompactSlots: true
    property bool showAll: false
    property string numerals: "standard"
    property bool minimap: false
    property real tapeMaxWidth: Style.px(200)
    property real tapeGap: Style.px(3)
    readonly property var numeralSets: ({
        standard: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20"],
        hindi: ["१", "२", "३", "४", "५", "६", "७", "८", "९", "१०", "११", "१२", "१३", "१४", "१५", "१६", "१७", "१८", "१९", "२०"],
        kanji: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十"],
        roman: ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"],
        dots: Array.from({ length: slotCount }, (_, index) => (index % 2 ? "" : ".") + ":".repeat((index + 1) >> 1))
    })
    readonly property string decodeGlyphs: "0123456789ABCDEF#$%&@/<>=+*"
    readonly property int decodeDelay: 4
    readonly property int decodeStride: 3
    readonly property int alertLevel: minimap ? Math.max((tapeLoader.item as WindowTape)?.otherLevel ?? 0, MinimapState.numberFlash) : 0
    readonly property real trailingGap: compactStyle ? 1.5 : 0
    readonly property real horizontalInsets: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3]
    readonly property real verticalInsets: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2]

    // This Hyprland evaluates a dispatch as Lua, where a legacy dispatcher
    // string is a syntax error ("workspace 2" -> ')' expected near '2'), so the
    // switch silently did nothing. ws.activate() covers workspaces that already
    // exist; these two paths — a workspace not yet created, and wheel scrolling
    // by a relative target — have to dispatch by hand. The guard mirrors the
    // dock's, so a build without the Lua plugin still works.
    function gotoWorkspace(target) {
        Hyprland.dispatch(Hyprland.usingLua
            ? 'hl.dsp.focus({ workspace = "' + target + '" })'
            : "workspace " + target)
    }
    implicitWidth: grid.implicitWidth + horizontalInsets + trailingGap
    implicitHeight: grid.implicitHeight + verticalInsets

    function workspace(id) {
        const values = Hyprland.workspaces.values
        for (let i = 0; i < values.length; ++i)
            if (values[i].id === id) return values[i]
        return null
    }
    function symbol(id) { return (numeralSets[numerals] || numeralSets.standard)[id - 1] }
    function decoded(target, step) {
        return Array.from(target, (character, index) => step >= decodeDelay + index * decodeStride ? character
            : decodeGlyphs.charAt(Math.floor(Math.random() * decodeGlyphs.length))).join("")
    }
    function jumpToAlert() { shell.dispatchWithoutWarp([MinimapState.focusExpression(MinimapState.alertTarget())]) }

    Connections {
        target: Hyprland
        enabled: root.minimap
        function onFocusedWorkspaceChanged() { (workspaceFx.item as WorkspaceFx)?.play() }
    }

    GridLayout {
        id: grid
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0] + root.box.padding[0]
        anchors.rightMargin: root.box.margin[1] + root.box.padding[1] + root.trailingGap
        anchors.bottomMargin: root.box.margin[2] + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.box.padding[3]
        rows: 1
        columnSpacing: root.compactStyle ? Style.px(1) : 0
        rowSpacing: 0

        Repeater {
            model: root.slotCount
            delegate: BarButton {
                id: workspaceButton
                required property int index
                property var ws: root.workspace(index + 1)
                readonly property string numeral: root.symbol(index + 1)
                readonly property bool focused: ws !== null && ws.focused
                readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0
                property bool shown: root.compactStyle && root.fixedCompactSlots
                    ? index < root.persistentSlots || index < root.compactSlots && ws !== null
                    : root.showAll && index < root.persistentSlots || ws !== null && (!root.activeOnly || ws.focused) && (!root.hideActive || !ws.focused)
                property int decodeStep: -1
                property real swapShift: 0
                property real swapFade: 1
                shell: root.shell
                opensPopup: true
                css: focused ? "#workspaces button.active" : "#workspaces button"
                Layout.fillHeight: true
                fixedWidth: root.compactStyle ? Style.px(20 + Math.max(0, numeral.length - 1) * 7) : 0
                text: root.compactStyle && focused ? "󱓻" : decodeStep >= 0 ? root.decoded(numeral, decodeStep) : numeral
                fontSize: Style.fontPx(box.fontSize)
                textColor: decodeStep >= 0 ? root.shell.role("c14", root.shell.accent)
                    : focused && root.alertLevel > 0 ? root.shell.role(root.alertLevel >= Minimap.CRITICAL ? "error" : "warning", root.shell.foreground)
                    : root.compactStyle ? root.shell.foreground
                    : ws && ws.urgent ? root.shell.role("warning", root.shell.foreground)
                    : box.color !== undefined ? styleColor("color")
                    : !focused && !hovered ? (occupied ? root.inactiveColor : root.inactiveWindowColor)
                    : root.shell.alpha(root.shell.role(hovered || focused && root.numerals === "roman" ? "hvr_br" : "act_br", root.shell.foreground), occupied ? 1 : focused && root.numerals === "roman" ? .7 : .8)
                opacity: (root.compactStyle && !occupied && !focused ? .5 : 1) * swapFade
                transform: Translate { y: workspaceButton.swapShift }
                visible: shown
                onFocusedChanged: {
                    if (!focused || !root.minimap || Style.reduceMotion) return
                    if (MinimapState.animStyle !== "cyberpunk") return swapIn.restart()
                    decodeStep = 0
                }
                onClicked: button => {
                    if (button === Qt.RightButton) return root.shell.togglePopup("workspaces")
                    if (focused && root.minimap && MinimapState.hasAlerts) return root.jumpToAlert()
                    if (ws) return ws.activate()
                    root.gotoWorkspace(index + 1)
                }
                onWheeled: delta => root.gotoWorkspace(delta > 0 ? "r-1" : "r+1")
                MotionBehavior on opacity { enabled: !Style.reduceMotion && !swapIn.running; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                ParallelAnimation {
                    id: swapIn
                    readonly property bool motionEnabled: !Style.reduceMotion
                    onMotionEnabledChanged: if (!motionEnabled) complete()
                    NumberAnimation { target: workspaceButton; property: "swapShift"; from: workspaceButton.height / 2; to: 0; duration: MinimapState.motion.swapIn; easing.type: Easing.OutCubic }
                    NumberAnimation { target: workspaceButton; property: "swapFade"; from: 0; to: 1; duration: MinimapState.motion.swapIn; easing.type: Easing.OutCubic }
                }
                Timer {
                    id: decodeTimer
                    interval: 48
                    repeat: true
                    running: workspaceButton.decodeStep >= 0 && !Style.reduceMotion
                    onRunningChanged: if (!running) workspaceButton.decodeStep = -1
                    onTriggered: if (++workspaceButton.decodeStep >= root.decodeDelay + workspaceButton.numeral.length * root.decodeStride) {
                        workspaceButton.decodeStep = -1
                    }
                }
                Loader {
                    z: -1
                    anchors.fill: parent
                    active: root.minimap && workspaceButton.focused
                    sourceComponent: BoxFx { shell: root.shell; style: MinimapState.animStyle; corner: workspaceButton.radius }
                    onLoaded: (item as BoxFx).play("focus")
                }
            }
        }

        Loader {
            id: tapeLoader
            active: root.minimap
            visible: active
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.floor((grid.height - implicitHeight) / 2)
            Layout.leftMargin: root.box.margin[3]
            sourceComponent: WindowTape {
                shell: root.shell; inactiveColor: root.inactiveColor; popupEnabled: root.popupEnabled; tabAnchor: root
                maxWidth: root.tapeMaxWidth; gap: root.tapeGap
                onWheeled: delta => root.gotoWorkspace(delta > 0 ? "r-1" : "r+1")
            }
        }

    }

    Loader {
        id: workspaceFx
        anchors.fill: grid
        active: root.minimap
        sourceComponent: WorkspaceFx {
            shell: root.shell
            source: grid
            style: MinimapState.animStyle
        }
    }

    WorkspacePopup {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled
        minimap: root.minimap; numerals: root.numerals; numeralSets: root.numeralSets
    }
}
