import QtQuick
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    css: "gpu"
    tooltip: ""
    command: ["hyprshell", "gpu"]; interval: 60000
    textColor: root.box.content !== undefined ? root.styleColor("content")
        : root.shell.role("c7", root.shell.foreground)
    onClicked: button => {
        if (button !== Qt.RightButton) return root.shell.togglePopup("gpu")
        root.shell.run(["hyprshell", "gpu", "--toggle"], root.refresh)
    }
    SysinfoPopup { popupName: "gpu"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "gpu"]; switchCommand: ["hyprshell", "gpu", "--use"]; onModuleRefreshRequested: root.refresh() }
}
