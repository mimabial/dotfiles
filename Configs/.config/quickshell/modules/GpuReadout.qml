import QtQuick
import ".."

StackedReadout {
    id: root
    property bool popupsAllowed: true
    css: "gpuinfo"
    tooltip: ""
    command: ["hyprshell", "gpuinfo"]; interval: 60000
    textColor: root.box.content !== undefined ? root.styleColor("content")
        : root.shell.role("c7", root.shell.foreground)
    onClicked: button => {
        if (button !== Qt.RightButton) return root.shell.togglePopup("gpu")
        root.shell.run(["hyprshell", "gpuinfo", "--toggle"], root.refresh)
    }
    SysinfoPopup { popupName: "gpu"; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; command: ["hyprshell", "gpuinfo"]; switchCommand: ["hyprshell", "gpuinfo", "--use"] }
}
