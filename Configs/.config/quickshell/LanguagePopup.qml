import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "language"
    contentWidth: 260

    property var report: ({})
    readonly property string active: String(report.text || "")
    readonly property var layouts: String(report.layouts || "").split(",").filter(entry => entry !== "")

    function refresh() { if (!layoutProc.running) layoutProc.running = true }
    onOpenChanged: if (open) refresh()

    property Process layoutProc: Process {
        command: ["hyprshell", "util/keyboard-layout"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    property Timer settle: Timer { interval: 400; onTriggered: root.refresh() }

    Column {
        id: langColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: "KEYBOARD LAYOUT" }

        Repeater {
            model: root.layouts
            PopupRow {
                required property var modelData
                required property int index
                width: langColumn.width; shell: root.shell
                title: modelData
                detail: modelData === root.active ? String(root.report.alt || "") : "Switch to this"
                active: modelData === root.active
                onClicked: {
                    if (modelData === root.active) return
                    root.shell.run(["hyprshell", "util/keyboard-layout", "--use", String(index)])
                    root.settle.restart()
                    if (anchorItem && anchorItem.refresh) anchorItem.refresh(600)
                }
            }
        }
    }
}
