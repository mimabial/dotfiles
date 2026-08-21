import QtQuick

ScriptButton {
    id: root
    css: "custom-updates"
    command: ["hyprshell", "system/system.update.sh"]
    interval: 86400000
    fallback: "󰮯"
    textColor: shell.role("c9", shell.foreground)
    property bool popupEnabled: true
    // the vertical bars have room to stack the total under the glyph
    property bool showCount: false
    readonly property int pending: {
        const groups = output.packages || ({})
        let total = 0
        for (const key in groups) total += (groups[key] || []).length
        return total
    }
    readonly property bool stacked: showCount && pending > 0
    text: stacked
        ? "\u{f0baf}<br><span style='color:" + shell.foreground + "'>" + pending + "</span>"
        : "\u{f0baf}"
    textFormat: stacked ? Text.RichText : Text.PlainText
    onClicked: shell.togglePopup("updates")

    UpdatesPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; report: root.output }
}
