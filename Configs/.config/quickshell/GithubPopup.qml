pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "Ui" as Ui

PopupCard {
    id: root
    popupName: "github"
    contentWidth: Style.px(340)
    signal moduleRefreshRequested()

    property var report: ({})
    readonly property var inbox: report.inbox || ({})
    readonly property var reviews: report.reviews || ({})
    readonly property var security: report.security || ({})
    readonly property var kinds: security.kinds || []
    readonly property var issues: [inbox.issue, reviews.issue, security.issue, security.note].filter(entry => !!entry)
    // a report started before a mark-read landed still lists the thread, so
    // marked ids stay hidden until a report finishes with nothing pending
    property var dismissed: []
    property var queued: []
    property bool refreshAgain: false
    readonly property var notifications: (inbox.items || []).filter(item => !dismissed.includes(item.id))
    readonly property var reviewItems: reviews.items || []

    function refresh() { if (reportProc.running) refreshAgain = true; else reportProc.running = true }
    function openUrl(url) { shell.run(["xdg-open", url]); shell.closePopup() }
    function markRead(id) { dismissed = dismissed.concat(id); queued = queued.concat(id); sendMarks() }
    function sendMarks() {
        if (markProc.running || queued.length === 0) return
        markProc.command = ["hyprshell", "github-notifications", "--mark-read"].concat(queued)
        queued = []
        markProc.running = true
    }

    onOpenChanged: if (open) refresh()

    property Process reportProc: Process {
        command: ["hyprshell", "github-notifications", "--report"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
            if (root.refreshAgain) { root.refreshAgain = false; root.refresh() }
            else if (!root.markProc.running && root.queued.length === 0) root.dismissed = []
        } }
    }
    property Process markProc: Process {
        onExited: {
            if (root.queued.length > 0) root.sendMarks()
            else {
                root.moduleRefreshRequested()
                root.refresh()
            }
        }
    }
    property Timer poll: Timer { interval: 300000; running: root.open; repeat: true; onTriggered: root.refresh() }

    component CappedList: Flickable {
        id: list
        property alias model: rows.model
        property alias delegate: rows.delegate
        readonly property int maxRows: 5
        visible: rows.count > 0
        height: rows.count > maxRows ? listColumn.implicitHeight / rows.count * maxRows : listColumn.implicitHeight
        contentWidth: width; contentHeight: listColumn.implicitHeight
        interactive: contentHeight > height; clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: list.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        Column { id: listColumn; width: list.width; spacing: 2; Repeater { id: rows } }
    }

    Column {
        id: githubColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupHero { shell: root.shell; title: "GitHub"; status: root.inbox.available === false ? "unavailable" : root.notifications.length > 0 ? root.notifications.length + " unread" : "all caught up" }

        PopupRow {
            width: parent.width; shell: root.shell
            icon: "󰚩"
            title: "Inbox"
            detail: root.inbox.available === false ? "Unavailable"
                : root.notifications.length > 0 ? "Unread notifications" : "All caught up"
            value: root.inbox.available === false ? "—" : String(root.notifications.length)
            active: root.notifications.length > 0
            onClicked: root.openUrl("https://github.com/notifications")
        }

        CappedList {
            id: inboxList
            width: parent.width
            model: root.notifications
            delegate: Item {
                id: notification
                required property var modelData
                width: inboxList.width; implicitHeight: notificationRow.implicitHeight
                PopupRow {
                    id: notificationRow
                    anchors.left: parent.left; anchors.right: parent.right; shell: root.shell
                    icon: notification.modelData.type === "PullRequest" ? "" : "󰍩"
                    title: notification.modelData.title
                    detail: notification.modelData.repo + " · " + notification.modelData.reason
                    rightInset: markButton.width + Style.sm
                    onClicked: { const item = notification.modelData; root.openUrl(item.url); root.markRead(item.id) }
                }
                Ui.PanelActionButton {
                    id: markButton
                    anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰄬"; tooltipText: "Mark read"
                    foreground: root.shell.foreground; hoverColor: root.shell.role("success", root.shell.foreground); fontFamily: root.shell.fontFamily
                    onClicked: root.markRead(notification.modelData.id)
                }
            }
        }

        PopupSeparator { visible: reviewList.visible; shell: root.shell }
        PopupSection { visible: reviewList.visible; shell: root.shell; text: "REVIEW REQUESTS"; value: String(root.reviewItems.length) }
        CappedList {
            id: reviewList
            width: parent.width
            model: root.reviewItems
            delegate: PopupRow {
                required property var modelData
                width: reviewList.width; shell: root.shell
                icon: ""; title: modelData.title; detail: modelData.repo
                onClicked: root.openUrl(modelData.url)
            }
        }

        PopupSeparator { shell: root.shell }
        PopupSection {
            shell: root.shell
            text: "SECURITY"; value: root.security.available === false ? "unavailable" : String(root.security.count || 0)
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
                    onClicked: root.openUrl("https://github.com/settings/security_analysis")
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
