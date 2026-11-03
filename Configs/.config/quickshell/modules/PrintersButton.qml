import QtQuick
import Quickshell.Io
import ".."

ScriptButton {
    id: root
    property bool popupsAllowed: true
    readonly property string script: root.shell.home + "/.local/lib/hypr/system/printers.sh"
    css: "printers"
    command: ["bash", root.script, "--bar"]; polling: false
    onClicked: root.shell.togglePopup("printers")
    Process {
        command: ["bash", root.script, "--watch"]
        running: true
        onStarted: root.refresh()
        stdout: SplitParser { onRead: line => {
            if (line.indexOf("org.cups.cupsd.Notifier") < 0) return
            root.refresh()
            if (popup.open) popup.refresh()
        } }
    }
    PrintersPopup { id: popup; anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}
