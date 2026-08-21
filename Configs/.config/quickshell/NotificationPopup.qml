import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "notifications"
    contentWidth: 380
    contentHeight: 430

    property var report: ({})
    readonly property var entries: report.entries || []
    readonly property bool paused: report.paused === true

    function refresh() { if (!historyProc.running) historyProc.running = true }
    function act(command) {
        shell.run(command)
        settle.restart()
    }
    // dunst reports monotonic microseconds; the producer turns that into seconds
    function ago(seconds) {
        if (seconds < 60) return "now"
        if (seconds < 3600) return Math.floor(seconds / 60) + "m"
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h"
        return Math.floor(seconds / 86400) + "d"
    }

    onOpenChanged: if (open) refresh()

    property Process historyProc: Process {
        command: ["hyprshell", "notify/history"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) }
            catch (error) { root.report = ({}) }
        } }
    }
    property Timer settle: Timer { interval: 350; onTriggered: root.refresh() }
    property Timer poll: Timer { interval: 4000; running: root.open; repeat: true; onTriggered: root.refresh() }

    Column {
        id: notifyColumn
        anchors.fill: parent; spacing: Style.sm

        PopupSection { shell: root.shell; text: "NOTIFICATIONS" }

        PopupRow {
            width: parent.width; shell: root.shell
            icon: root.paused ? "󱏧" : "󰂚"
            title: root.paused ? "Do not disturb" : "Notifications on"
            detail: root.paused ? "Incoming ones are held" : root.report.waiting > 0
                ? root.report.waiting + " waiting" : "Delivering normally"
            active: root.paused
            onClicked: root.act(["dunstctl", "set-paused", "toggle"])
        }

        PopupSeparator { shell: root.shell }
        PopupSection {
            shell: root.shell
            text: root.entries.length > 0 ? "HISTORY · " + root.entries.length : "HISTORY"
        }

        Text {
            visible: root.entries.length === 0
            width: parent.width; text: "Nothing yet"
            color: root.shell.alpha(root.shell.foreground, .5)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        ListView {
            width: parent.width
            height: Math.max(0, parent.height - y - 34)
            spacing: 4; clip: true
            model: root.entries
            delegate: Rectangle {
                required property var modelData
                width: ListView.view.width
                height: entryText.implicitHeight + Style.controlPaddingY * 2
                radius: root.shell.rounding
                color: entryMouse.containsMouse
                    ? root.shell.alpha(root.shell.role("hvr_bg", root.shell.accent), Style.hoverFillAlpha)
                    : "transparent"

                Column {
                    id: entryText
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Row {
                        width: parent.width; spacing: Style.xs
                        Text {
                            width: parent.width - age.implicitWidth - Style.xs
                            text: parent.parent.parent.modelData.summary || parent.parent.parent.modelData.app
                            elide: Text.ElideRight
                            color: parent.parent.parent.modelData.urgency === "CRITICAL"
                                ? root.shell.role("error", root.shell.foreground)
                                : root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Text {
                            id: age
                            text: root.ago(parent.parent.parent.modelData.age)
                            color: root.shell.alpha(root.shell.foreground, .45)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                    }
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: parent.parent.modelData.body
                        elide: Text.ElideRight
                        color: root.shell.alpha(root.shell.foreground, .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
                MouseArea { id: entryMouse; anchors.fill: parent; hoverEnabled: true }
            }
        }

        Row {
            width: parent.width; spacing: Style.xs
            PopupRow {
                width: (parent.width - Style.xs) / 2; shell: root.shell
                icon: "󰎟"; title: "Restore last"
                onClicked: root.act(["dunstctl", "history-pop"])
            }
            PopupRow {
                width: (parent.width - Style.xs) / 2; shell: root.shell
                icon: "󰎠"; title: "Clear all"
                onClicked: root.act(["sh", "-c", "dunstctl history-clear; dunstctl close-all"])
            }
        }
    }
}
