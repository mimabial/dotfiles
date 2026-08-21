import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "github"
    contentWidth: 340

    property var report: ({})
    readonly property var inbox: report.inbox || ({})
    readonly property var security: report.security || ({})
    readonly property var kinds: security.kinds || []
    readonly property var issues: [inbox.issue, security.issue, security.note].filter(entry => !!entry)

    function refresh() { if (!reportProc.running) reportProc.running = true }
    function open(url) { shell.run(["xdg-open", url]); shell.closePopup() }

    onOpenChanged: if (open) refresh()

    property Process reportProc: Process {
        command: ["hyprshell", "github-notifications", "--report"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    property Timer poll: Timer { interval: 300000; running: root.open; repeat: true; onTriggered: root.refresh() }

    Column {
        id: githubColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: "GITHUB" }

        PopupRow {
            width: parent.width; shell: root.shell
            icon: "󰚩"
            title: "Inbox"
            detail: root.inbox.available === false ? "Unavailable"
                : root.inbox.count > 0 ? "Unread notifications" : "All caught up"
            value: root.inbox.available === false ? "—" : String(root.inbox.count || 0)
            active: root.inbox.count > 0
            onClicked: root.open("https://github.com/notifications")
        }

        PopupSeparator { shell: root.shell }
        PopupSection {
            shell: root.shell
            text: root.security.available === false ? "SECURITY · UNAVAILABLE"
                : "SECURITY · " + (root.security.count || 0)
        }

        Column {
            width: parent.width; spacing: 2
            Repeater {
                model: root.kinds
                PopupRow {
                    required property var modelData
                    width: githubColumn.width; shell: root.shell
                    icon: modelData.key === "dependabot" ? "󰇚"
                        : modelData.key === "code-scanning" ? "󰅩" : "󰌾"
                    title: modelData.label
                    detail: (modelData.repos || []).length > 0
                        ? (modelData.repos || []).map(entry => entry.repo + " " + entry.count).join(", ")
                        : ""
                    value: String(modelData.count || 0)
                    active: modelData.count > 0
                    onClicked: root.open("https://github.com/settings/security_analysis")
                }
            }
        }

        PopupSeparator { visible: root.issues.length > 0; shell: root.shell }
        PopupSection { visible: root.issues.length > 0; shell: root.shell; text: "ISSUES" }

        Column {
            visible: root.issues.length > 0
            width: parent.width; spacing: 2
            Repeater {
                model: root.issues
                Text {
                    required property var modelData
                    width: githubColumn.width
                    text: modelData
                    wrapMode: Text.Wrap
                    color: root.shell.role("warning", root.shell.foreground)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
        }

        PopupSeparator { shell: root.shell }
        PopupRow {
            width: parent.width; shell: root.shell
            icon: "󰑐"; title: "Refresh"
            onClicked: root.refresh()
        }
    }
}
