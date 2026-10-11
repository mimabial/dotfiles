pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower
import "Opacity.js" as Opacity

PopupCard {
    id: root
    popupName: "desktop"
    contentWidth: Style.px(340)
    contentHeight: viewport.height + padding * 2
    readonly property string helperDir: root.shell.home + "/.local/lib/hypr/"
    property var barLayouts: []
    property var layouts: []
    property var workflows: []
    property var allowedBarLayouts: []
    property bool windowLayoutLocked: false
    // mirrors workflow_locked() in util/workflows.sh: while one of these owns the
    // workflow, --set refuses, so the rows must not offer a click that no-ops
    readonly property string workflowOwner: root.shell.workflow === "gaming" ? "gamemode"
        : PowerProfiles.profile === PowerProfile.PowerSaver ? "power saver" : ""

    function rows(raw, labels) { return String(raw).trim().split("\n").filter(Boolean).map(line => { const fields = line.split("\t"), name = fields[0]; return {name:name, icon:fields[1] || "", label:fields[2] || labels(name), detail:fields[3] || ""} }) }
    function title(name) { return name.charAt(0).toUpperCase() + name.slice(1).replace(/-/g, " ") }
    function refresh() { for (const process of [barLayoutRead, layoutRead, workflowRead]) if (!process.running) process.running = true }
    onOpenChanged: if (open) refresh()

    property Process barLayoutRead: Process { command: [root.helperDir + "quickshell/layout.sh", "list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.barLayouts = String(text).trim().split("\n").filter(Boolean) } }
    property Process layoutRead: Process { command: [root.helperDir + "util/window-layout.sh", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.layouts = root.rows(text, root.title) } }
    property Process workflowRead: Process { command: [root.helperDir + "util/workflows.sh", "--list"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.workflows = root.rows(text, root.title) } }
    property FileView stateFile: FileView {
        path: root.shell.home + "/.local/state/hypr/staterc"; watchChanges: true; printErrors: false; onFileChanged: reload()
        onLoaded: {
            const state = String(text())
            root.allowedBarLayouts = (state.match(/(?:^|\n)WORKFLOW_QUICKSHELL_LAYOUT=["']?([^"'\n]*)/)?.[1] ?? "").trim().split(/\s+/).filter(Boolean)
            root.windowLayoutLocked = (state.match(/(?:^|\n)WORKFLOW_WINDOW_LAYOUT=["']?([^"'\n]*)/)?.[1] ?? "").trim() !== ""
        }
    }

    Flickable {
        id: viewport
        anchors.left: parent.left; anchors.right: parent.right
        height: Math.min(contentHeight, Math.max(0, root.maxHeight - root.keyboardHintHeight - root.padding * 2))
        contentWidth: width; contentHeight: desktopColumn.implicitHeight
        interactive: contentHeight > height
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: PopupScrollBar { shell: root.shell }
        Column {
            id: desktopColumn
            width: viewport.width - Style.sm - Style.xs; spacing: Style.sectionGap
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "BAR" }
                PopupRow { width: parent.width; shell: root.shell; icon: "󰽙"; title: "Background blur"; detail: active ? "Enabled" : "Disabled"; active: root.shell.prefs.barBlur; onClicked: root.shell.toggleBarBlur() }
                PopupRow {
                    width: parent.width; shell: root.shell; icon: "󰃟"; title: "Opacity"; interactive: false; rightInset: opacitySelect.width + Style.sm
                    PopupSelect {
                        id: opacitySelect
                        anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                        width: Style.px(172); shell: root.shell
                        choices: [{ label: "Auto (Workflow)", value: -1 }].concat(Opacity.presets.map(preset => ({ label: Opacity.label(preset), value: preset.value })))
                        selectedIndex: root.shell.prefs.barOpacity < 0 ? 0 : 1 + Opacity.presets.indexOf(Opacity.nearest(root.shell.prefs.barOpacity))
                        onActivated: index => root.shell.prefs.barOpacity = opacitySelect.choices[index].value
                    }
                }
                PopupRow { width: parent.width; shell: root.shell; icon: "󰹞"; title: "Floating bar"; detail: active ? root.shell.barFloatGap + " px gap" : "Disabled"; active: root.shell.prefs.barFloating; onClicked: root.shell.toggleBarFloating() }
            }
            PopupSeparator { shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "BAR LAYOUT" }
                Repeater {
                    model: root.barLayouts
                    PopupRow {
                        required property string modelData
                        width: desktopColumn.width; shell: root.shell; icon: ""; title: root.title(modelData)
                        detail: active ? "Active" : interactive ? "Switch to this layout" : "Managed by " + root.title(root.shell.workflow)
                        active: root.shell.layoutName === modelData
                        interactive: root.allowedBarLayouts.length === 0 || root.allowedBarLayouts.includes(modelData)
                        opacity: interactive ? 1 : Style.mutedTextAlpha
                        onClicked: { root.shell.closePopup(); root.shell.run([root.helperDir + "quickshell/layout.sh", "set", modelData]) }
                    }
                }
            }
            PopupSeparator { shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "WINDOW LAYOUT"; value: root.windowLayoutLocked ? "Managed by " + root.title(root.shell.workflow) : "" }
                GridLayout {
                    width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
                    opacity: root.windowLayoutLocked ? Style.mutedTextAlpha : 1
                    Repeater { model: root.layouts; PopupRow { required property var modelData; Layout.fillWidth: true; shell: root.shell; icon: modelData.icon; title: modelData.label; interactive: !root.windowLayoutLocked; active: root.shell.windowLayout === modelData.name; onClicked: root.shell.run([root.helperDir + "util/window-layout.sh", "--set", modelData.name]) } }
                }
            }
            PopupSeparator { shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: root.workflowOwner ? "WORKFLOW · LOCKED BY " + root.workflowOwner.toUpperCase() : "WORKFLOW" }
                GridLayout {
                    width: parent.width; columns: 2; rowSpacing: Style.xs; columnSpacing: Style.xs
                    opacity: root.workflowOwner ? .45 : 1
                    Repeater { model: root.workflows; PopupRow { required property var modelData; Layout.fillWidth: true; shell: root.shell; icon: modelData.icon; title: root.title(modelData.name); detail: modelData.label; interactive: !root.workflowOwner; active: root.shell.workflow === modelData.name; onClicked: root.shell.run([root.helperDir + "util/workflows.sh", "--set", modelData.name]) } }
                }
            }
        }
    }
}
