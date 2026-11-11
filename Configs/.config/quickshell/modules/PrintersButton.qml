import QtQuick
import ".."

ScriptButton {
    id: root
    property bool popupEnabled: true
    readonly property string script: root.shell.home + "/.local/lib/hypr/system/printers.sh"
    css: "printers"
    command: ["bash", root.script, "--bar"]
    refreshKey: PrinterEvents.revision
    onRefreshKeyChanged: if (popup.open) popup.refresh()
    onClicked: root.shell.togglePopup("printers")
    Component.onCompleted: { PrinterEvents.consumers++; refresh() }
    Component.onDestruction: PrinterEvents.consumers--
    PrintersPopup { id: popup; anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}
