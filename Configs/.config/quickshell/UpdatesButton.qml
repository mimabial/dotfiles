import QtQuick
import "Units.js" as Units

ScriptButton {
    id: root
    css: "updates"
    tooltip: ""
    command: ["hyprshell", "system/package-updates.sh"]
    indicator: "updates"
    interval: Units.MS_PER_DAY
    fallback: ""
    property bool popupEnabled: true
    property bool hideWhenCurrent: true
    property bool showCount: false
    readonly property int pending: {
        const groups = output.packages || ({})
        let total = 0
        for (const key in groups) total += (groups[key] || []).length
        return total
    }
    readonly property bool hasErrors: (output.errors || []).length > 0
    readonly property bool shown: !hideWhenCurrent || pending > 0 || hasErrors
    visible: shown
    readonly property bool stacked: showCount && pending > 0
    text: stacked
        ? "<br><span style='color:" + shell.foreground + "'>" + pending + "</span>"
        : ""
    textFormat: stacked ? Text.RichText : Text.PlainText
    property var primaryAction: null
    property var rightAction: null
    onClicked: button => button === Qt.RightButton && root.rightAction ? root.rightAction()
        : root.primaryAction ? root.primaryAction()
        : root.shell.togglePopup("updates")
    refreshKey: shell.popupName === "updates"

    UpdatesPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled }
}
