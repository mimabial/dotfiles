import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupEnabled: true
    property string popupName: "vpn"
    property string settingsPopupName: popupName
    css: "vpn"
    output: VpnStatus.output
    function refresh() { VpnStatus.refresh() }
    onClicked: button => button === Qt.RightButton
        ? root.shell.run(["hyprshell", "quickshell/vpn-toggle"])
        : root.shell.togglePopup(root.popupName)
    VpnPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; popupName: root.settingsPopupName }
}
