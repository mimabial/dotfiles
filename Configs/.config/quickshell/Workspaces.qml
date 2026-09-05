pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

Item {
    id: root
    required property var shell
    readonly property var box: shell.style.box("workspaces")
    property bool vertical: false
    property bool activeOnly: false
    property bool hideActive: false
    property bool popupEnabled: false
    // Fixed-width numeric pills with a dot on the focused one, as opposed to
    // the symbol sets `numerals` selects.
    property bool compactStyle: false
    property string numerals: vertical ? "hindi" : "kanji"
    readonly property real trailingGap: compactStyle && !vertical ? 1.5 : 0
    // no frame is painted here, so box.border reserves nothing
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3]
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2]

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
    implicitWidth: grid.implicitWidth + spanX + trailingGap
    implicitHeight: grid.implicitHeight + spanY

    function workspace(id) {
        const values = Hyprland.workspaces.values
        for (let i = 0; i < values.length; ++i)
            if (values[i].id === id) return values[i]
        return null
    }
    function symbol(id) {
        const hindi = ["१", "२", "३", "४", "५", "६", "७", "८", "९", "१०", "११", "१२", "१३", "१४", "१५", "१६", "१७", "१८", "१९", "२०"]
        const kanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十"]
        const roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX"]
        return ({ hindi, kanji, roman }[numerals] || kanji)[id - 1]
    }

    GridLayout {
        id: grid
        anchors.fill: parent
        anchors.topMargin: root.box.margin[0] + root.box.padding[0]
        anchors.rightMargin: root.box.margin[1] + root.box.padding[1] + root.trailingGap
        anchors.bottomMargin: root.box.margin[2] + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.box.padding[3]
        columns: root.vertical ? 1 : 20
        rows: root.vertical ? 20 : 1
        columnSpacing: root.compactStyle && !root.vertical ? Style.px(1) : 0
        rowSpacing: 0

        Repeater {
            model: 20
            delegate: BarButton {
                required property int index
                property var ws: root.workspace(index + 1)
                readonly property bool focused: ws !== null && ws.focused
                readonly property bool occupied: ws !== null && ws.toplevels.values.length > 0
                property bool shown: root.compactStyle
                    ? index < 5 || index < 10 && ws !== null
                    : ws !== null && (!root.activeOnly || ws.focused) && (!root.hideActive || !ws.focused)
                shell: root.shell
                css: focused ? "#workspaces button.active" : "#workspaces button"
                Layout.fillWidth: root.vertical
                Layout.fillHeight: !root.vertical
                fixedWidth: root.compactStyle && !root.vertical ? Style.px(20) : 0
                text: root.compactStyle ? focused ? "󱓻" : index === 9 ? "0" : String(index + 1) : root.symbol(index + 1)
                active: root.vertical && focused
                fontSize: Style.fontPx(box.fontSize)
                fontWeight: !root.compactStyle && ((ws && ws.urgent) || (root.activeOnly && root.numerals !== "roman")) ? Font.Bold : Font.Normal
                textColor: root.compactStyle ? root.shell.foreground : ws && ws.urgent ? root.shell.role("warning", root.shell.foreground) : box.content !== undefined ? boxColor("content") : root.vertical ? (active ? root.shell.role("act_fg", root.shell.foreground) : root.shell.foreground) : root.shell.alpha(root.shell.role(hovered || root.activeOnly && root.numerals === "roman" ? "hvr_br" : root.activeOnly ? "act_br" : "br", root.shell.foreground), root.activeOnly && root.numerals === "roman" ? .7 : root.activeOnly || hovered ? .8 : .2)
                opacity: root.compactStyle && !occupied && !focused ? .5 : 1
                visible: shown
                onClicked: button => {
                    if (button === Qt.RightButton) return root.shell.togglePopup("workspaces")
                    if (ws) return ws.activate()
                    root.gotoWorkspace(index + 1)
                }
                onWheeled: delta => root.gotoWorkspace(delta > 0 ? "r-1" : "r+1")
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
        }
    }

    ModuleEdge { shell: root.shell }
    WorkspacePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}
