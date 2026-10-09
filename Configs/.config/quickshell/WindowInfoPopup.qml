pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland

PopupCard {
    id: root
    popupName: "windowinfo"
    contentWidth: Style.px(440)
    contentHeight: details.implicitHeight + padding * 2

    property var window: null
    readonly property var ipc: window?.lastIpcObject ?? ({})
    readonly property string windowClass: String(ipc.class ?? "")
    readonly property string ruleMatch: windowClass
        ? '["match"] = { ["class"] = "^(' + windowClass.replace(/[.*+?^${}()|[\]\\]/g, "\\\\$&") + ')$" }' : ""
    function yesNo(flag) { return flag === undefined ? "" : flag ? "yes" : "no" }
    readonly property var rows: window ? [
        { label: "Class", value: ipc.class },
        { label: "Initial class", value: ipc.initialClass },
        { label: "Title", value: ipc.title },
        { label: "Initial title", value: ipc.initialTitle },
        { label: "Tags", value: (ipc.tags ?? []).join(", ") },
        { label: "Rule match", value: ruleMatch },
        { label: "XWayland", value: yesNo(ipc.xwayland) },
        { label: "Floating", value: yesNo(ipc.floating) },
        { label: "Pinned", value: yesNo(ipc.pinned) },
        { label: "Fullscreen", value: ipc.fullscreen >= 2 ? "fullscreen" : ipc.fullscreen === 1 ? "maximized" : "no" },
        { label: "Workspace", value: ipc.workspace?.name },
        { label: "Monitor", value: window.monitor?.name },
        { label: "Size", value: ipc.size ? ipc.size.join(" × ") : "" },
        { label: "Position", value: ipc.at ? ipc.at.join(", ") : "" },
        { label: "Process ID", value: ipc.pid },
        { label: "Address", value: ipc.address }
    ] : []

    onOpenChanged: if (open) {
        window = Hyprland.activeToplevel
        Hyprland.refreshToplevels()
    }

    Column {
        id: details
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero { shell: root.shell; title: root.windowClass || "No focused window"; status: String(root.ipc.title ?? "") }
        PopupSeparator { shell: root.shell }

        Column {
            width: parent.width; spacing: Style.xs
            Repeater {
                model: root.rows
                PopupInfoPair {
                    required property var modelData
                    width: parent.width; shell: root.shell
                    label: modelData.label; value: String(modelData.value ?? "")
                    interactive: value !== ""
                    onClicked: root.shell.run(["wl-copy", value])
                }
            }
        }
        PopupHint { width: parent.width; shell: root.shell; text: "Click a value to copy it" }
    }
}
