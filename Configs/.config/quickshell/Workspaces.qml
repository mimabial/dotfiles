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
    property string numerals: vertical ? "hindi" : "kanji"
    readonly property real spanX: box.margin[1] + box.margin[3] + box.padding[1] + box.padding[3] + 2 * box.border
    readonly property real spanY: box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2] + 2 * box.border
    implicitWidth: grid.implicitWidth + spanX
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
        anchors.rightMargin: root.box.margin[1] + root.box.padding[1]
        anchors.bottomMargin: root.box.margin[2] + root.box.padding[2]
        anchors.leftMargin: root.box.margin[3] + root.box.padding[3]
        columns: root.vertical ? 1 : 20
        rows: root.vertical ? 20 : 1
        columnSpacing: 0
        rowSpacing: 0

        Repeater {
            model: 20
            delegate: BarButton {
                required property int index
                property var ws: root.workspace(index + 1)
                property bool shown: ws !== null && (!root.activeOnly || ws.focused) && (!root.hideActive || !ws.focused)
                shell: root.shell
                css: ws && ws.focused ? "#workspaces button.active" : "#workspaces button"
                Layout.fillWidth: root.vertical
                Layout.fillHeight: !root.vertical
                text: root.symbol(index + 1)
                active: root.vertical && ws && ws.focused
                fontSize: (root.vertical ? 16 : box.fontSize) * Style.scale
                fontWeight: (ws && ws.urgent) || (root.activeOnly && root.numerals !== "roman") ? Font.Bold : Font.Normal
                textColor: ws && ws.urgent ? root.shell.role("warning", root.shell.foreground) : box.fg !== undefined ? boxColor("fg") : root.vertical ? (active ? root.shell.role("act_fg", root.shell.foreground) : root.shell.foreground) : root.shell.alpha(root.shell.role(hovered || root.activeOnly && root.numerals === "roman" ? "hvr_br" : root.activeOnly ? "act_br" : "br", root.shell.foreground), root.activeOnly && root.numerals === "roman" ? .7 : root.activeOnly || hovered ? .8 : .2)
                visible: shown
                onClicked: button => button === Qt.RightButton
                    ? root.shell.togglePopup("workspaces")
                    : ws.activate()
                onWheeled: delta => Hyprland.dispatch("workspace " + (delta > 0 ? "r-1" : "r+1"))
            }
        }
    }

    ModuleEdge { shell: root.shell }
    WorkspacePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}
