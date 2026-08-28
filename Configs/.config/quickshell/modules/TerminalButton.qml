import QtQuick
import ".."

// showUpdates makes the glyph double as the update indicator for a bar with no
// updates module: red when packages are pending, left opens the report, right
// launches the terminal. Off, it is a plain launcher and polls nothing visible.
UpdatesButton {
    id: root
    property bool popupsAllowed: true
    property bool showUpdates: false
    hideWhenCurrent: false
    css: "terminal"; text: ""
    popupEnabled: root.showUpdates && root.popupsAllowed
    textColor: !root.showUpdates ? root.shell.role("c9", root.shell.foreground)
        : root.pending > 0 ? root.shell.role("error", root.shell.foreground)
        : root.shell.foreground
    tooltip: "Launch " + root.shell.terminal
    primaryAction: root.showUpdates ? null : () => root.shell.run([root.shell.terminal])
    rightAction: root.showUpdates ? () => root.shell.run([root.shell.terminal]) : null
}
