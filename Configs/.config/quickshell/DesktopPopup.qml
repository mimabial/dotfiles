import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower

PopupCard {
    id: root
    popupName: "desktop"
    contentWidth: Style.px(340)
    contentHeight: desktopColumn.implicitHeight + padding * 2
    property var layouts: []
    property var workflows: []
    // mirrors workflow_locked() in util/workflows.sh: while one of these owns the
    // workflow, --set refuses, so the rows must not offer a click that no-ops
    readonly property string workflowOwner: shell.workflow === "gaming" ? "gamemode"
        : PowerProfiles.profile === PowerProfile.PowerSaver ? "power saver"
        : PowerProfiles.profile === PowerProfile.Performance ? "performance" : ""

    function rows(raw, labels) { return String(raw).trim().split("\n").filter(Boolean).map(line => { const fields = line.split("\t"), name = fields[0]; return {name:name, icon:fields[1] || "", label:fields[2] || labels(name), detail:fields[3] || ""} }) }
    function title(name) { return name.charAt(0).toUpperCase() + name.slice(1).replace(/-/g, " ") }
    function refresh() { for (const process of [layoutRead, workflowRead]) if (!process.running) process.running = true }
    onOpenChanged: if (open) refresh()

    property Process layoutRead: Process { command: ["hyprshell", "util/window-layout", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.layouts = root.rows(text, root.title) } }
    property Process workflowRead: Process { command: ["hyprshell", "util/workflows", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.workflows = root.rows(text, root.title) } }

    Column {
        id: desktopColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "WINDOW LAYOUT" }
            GridLayout {
                width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
                Repeater { model: root.layouts; PopupRow { required property var modelData; Layout.fillWidth: true; shell: root.shell; icon: modelData.icon; title: modelData.label; active: root.shell.windowLayout === modelData.name; onClicked: root.shell.run(["hyprshell", "util/window-layout", "--set", modelData.name]) } }
            }
        }
        PopupSeparator { shell: root.shell }
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: root.workflowOwner ? "WORKFLOW · LOCKED BY " + root.workflowOwner.toUpperCase() : "WORKFLOW" }
            GridLayout {
                width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
                opacity: root.workflowOwner ? .45 : 1
                Repeater { model: root.workflows; PopupRow { required property var modelData; Layout.fillWidth: true; shell: root.shell; icon: modelData.icon; title: root.title(modelData.name); detail: modelData.label; interactive: !root.workflowOwner; active: root.shell.workflow === modelData.name; onClicked: root.shell.run(["hyprshell", "util/workflows", "--set", modelData.name]) } }
            }
        }
    }
}
