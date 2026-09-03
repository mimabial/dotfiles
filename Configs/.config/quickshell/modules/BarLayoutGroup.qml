pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    shell: root.shell; css: "barlayout"; Layout.fillWidth: true
    holdOpen: ["barlayout", "desktop"].includes(root.shell.popupName)
    primary: Component { BarButton {
        id: barButton; Layout.fillWidth: true; shell: root.shell; css: "barlayout-button"; text: root.shell.barLayoutIcon(root.shell.layoutName)
        textColor: root.shell.store.barTransparent ? root.shell.accent : root.shell.foreground
        tooltip: "Bar: " + root.shell.layoutName + " · " + (root.shell.store.barTransparent ? "transparent" : "themed") + "\nLeft: layouts · Middle: next · Right: transparency"
        onClicked: button => button === Qt.LeftButton ? root.shell.togglePopup("barlayout") : button === Qt.RightButton ? root.shell.toggleBarTransparency() : root.shell.run(["hyprshell", "quickshell/layout", "next"])
        BarLayoutPopup { anchorItem: barButton; shell: root.shell; popupEnabled: root.popupsAllowed }
    } }
    secondary: Component { Rectangle {
        implicitWidth: tools.implicitWidth + 2; implicitHeight: tools.implicitHeight + 2
        radius: root.shell.moduleRadius; color: "transparent"; border.width: 1; border.color: root.outline
        ColumnLayout { id: tools; anchors.fill: parent; anchors.margins: 1; spacing: 0
            ScriptButton { Layout.fillWidth: true; shell: root.shell; css: "workflows"; command: ["hyprshell", "util/workflows", "--bar"]; interval: 86400000; refreshKey: root.shell.workflow; onClicked: root.shell.togglePopup("desktop") }
            WindowLayoutButton { Layout.fillWidth: true; shell: root.shell; popupsAllowed: root.popupsAllowed }
        }
    } }
}
