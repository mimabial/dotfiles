import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PopupCard {
    id: root
    popupName: "desktop"
    contentWidth: 340
    contentHeight: desktopColumn.implicitHeight + padding * 2
    property var layouts: []
    property var workflows: []
    property string windowLayout: ""

    function rows(raw, labels) { return String(raw).trim().split("\n").filter(Boolean).map(line => { const p = line.split("\t"), name = p[0]; return {name:name, icon:p[1] || "", label:p[2] || labels(name), detail:p[3] || ""} }) }
    function title(name) { return name.charAt(0).toUpperCase() + name.slice(1).replace(/-/g, " ") }
    function refresh() { for (const process of [layoutRead, workflowRead]) if (!process.running) process.running = true }
    function loadWindow(raw) { const match = String(raw).match(/layout\s*=\s*["']([^"']+)/); windowLayout = match ? match[1] : "" }
    onOpenChanged: if (open) refresh()

    property FileView windowState: FileView { path: root.shell.home + "/.local/state/hypr/window-layout.lua"; watchChanges: true; printErrors: false; onLoaded: root.loadWindow(text()); onFileChanged: reload() }
    property Process layoutRead: Process { command: ["hyprshell", "util/window-layout", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.layouts = root.rows(text, root.title) } }
    property Process workflowRead: Process { command: ["hyprshell", "util/workflows", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.workflows = root.rows(text, root.title) } }

    Column {
        id: desktopColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm
        PopupSection { shell: root.shell; text: "WINDOW LAYOUT" }
        GridLayout {
            width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
            Repeater { model: root.layouts; PopupRow { required property var modelData; Layout.fillWidth: true; shell: root.shell; icon: modelData.icon; title: modelData.label; active: root.windowLayout === modelData.name; onClicked: root.shell.run(["hyprshell", "util/window-layout", "--set", modelData.name]) } }
        }
        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "WORKFLOW" }
        GridLayout {
            width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
            Repeater { model: root.workflows; PopupRow { required property var modelData; Layout.fillWidth: true; shell: root.shell; icon: modelData.icon; title: root.title(modelData.name); detail: modelData.label; active: root.shell.workflow === modelData.name; onClicked: root.shell.run(["hyprshell", "util/workflows", "--set", modelData.name]) } }
        }
    }
}
