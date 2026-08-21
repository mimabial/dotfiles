import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    css: "custom-language"
    command: ["hyprshell", "util/keyboard-layout"]; interval: 5000
    onClicked: button => {
        if (button !== Qt.RightButton) return root.shell.togglePopup("language")
        root.shell.run(["hyprshell", "util/keyboard-switch.sh"])
        root.refresh(300)
    }
    LanguagePopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}
