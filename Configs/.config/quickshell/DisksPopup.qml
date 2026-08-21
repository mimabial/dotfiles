import QtQuick
import Quickshell.Io

// Removable media, the job udiskie's tray icon does: mount, unmount, and power
// a drive down so it is safe to unplug.
PopupCard {
    id: root
    popupName: "disks"
    contentWidth: 360

    property var report: ({})
    readonly property var devices: report.devices || []
    readonly property bool automount: report.automount === true
    readonly property bool notify: report.notify === true

    function refresh() { if (!listProc.running) listProc.running = true }
    function act(flag, path) {
        actProc.running = false
        actProc.command = ["hyprshell", "system/removable", flag, String(path)]
        actProc.running = true
    }

    onOpenChanged: if (open) refresh()

    property Process listProc: Process {
        command: ["hyprshell", "system/removable", "--report"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.report = JSON.parse(text) || ({}) } catch (error) { root.report = ({}) }
        } }
    }
    // udisks needs a moment to settle before the new state shows up
    property Process actProc: Process { onExited: settle.restart() }
    property Timer settle: Timer { interval: 600; onTriggered: root.refresh() }
    property Timer poll: Timer { interval: 5000; running: root.open; repeat: true; onTriggered: root.refresh() }

    Column {
        id: disksColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection {
            shell: root.shell
            text: root.devices.length > 0 ? "REMOVABLE · " + root.devices.length : "REMOVABLE"
        }

        Text {
            visible: root.devices.length === 0
            width: parent.width; text: "Nothing plugged in"
            color: root.shell.alpha(root.shell.foreground, .5)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        Repeater {
            model: root.devices
            Item {
                required property var modelData
                width: disksColumn.width
                height: deviceRow.implicitHeight + Style.controlPaddingY * 2

                HoverHandler { id: deviceHover }
                Rectangle {
                    anchors.fill: parent
                    radius: root.shell.rounding
                    color: deviceHover.hovered ? root.shell.alpha(root.shell.foreground, .08) : "transparent"
                }

                Row {
                    id: deviceRow
                    anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                    anchors.right: parent.right; anchors.rightMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.sm

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f129e}"
                        color: root.shell.alpha(root.shell.foreground, parent.parent.modelData.mounted ? .9 : .45)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.title
                    }
                    Column {
                        readonly property var device: parent.parent.modelData
                        width: parent.width - 22 - 82 - Style.sm * 3
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            text: parent.device.title + "  " + parent.device.size
                            elide: Text.ElideRight
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Text {
                            width: parent.width
                            text: parent.device.mounted ? parent.device.mountpoint
                                : parent.device.fstype + " — not mounted"
                            elide: Text.ElideRight
                            color: root.shell.alpha(root.shell.foreground, .45)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        DiskAction {
                            glyph: parent.parent.parent.modelData.mounted ? "\u{f19f9}" : "\u{f0dcf}"
                            hint: parent.parent.parent.modelData.mounted ? "Unmount" : "Mount"
                            onTriggered: root.act(parent.parent.parent.modelData.mounted ? "--unmount" : "--mount",
                                                 parent.parent.parent.modelData.path)
                        }
                        DiskAction {
                            glyph: "\u{f0256}"
                            hint: "Open in file manager"
                            onTriggered: {
                                root.act("--browse", parent.parent.parent.modelData.path)
                                root.shell.closePopup()
                            }
                        }
                        DiskAction {
                            glyph: "\u{f0b91}"
                            hint: "Unmount and power off"
                            onTriggered: root.act("--eject", parent.parent.parent.modelData.path)
                        }
                    }
                }
            }
        }

        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "UDISKIE" }

        SettingRow {
            label: "Automount"
            detail: "Mount removable media on plug-in"
            checked: root.automount
            onToggled: root.act("--automount", root.automount ? "off" : "on")
        }
        SettingRow {
            label: "Notifications"
            detail: "Announce mounts and removals"
            checked: root.notify
            onToggled: root.act("--notify", root.notify ? "off" : "on")
        }
    }

    component SettingRow: Item {
        id: settingRow
        required property string label
        required property string detail
        required property bool checked
        signal toggled
        width: disksColumn.width
        height: Math.max(settingText.implicitHeight, settingSwitch.implicitHeight)
        Column {
            id: settingText
            anchors.left: parent.left; anchors.right: settingSwitch.left
            anchors.rightMargin: Style.sm
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width; text: settingRow.label
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            Text {
                width: parent.width; text: settingRow.detail; elide: Text.ElideRight
                color: root.shell.alpha(root.shell.foreground, .45)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
        }
        ToggleSwitch {
            id: settingSwitch
            shell: root.shell
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            checked: settingRow.checked
            onToggled: settingRow.toggled()
        }
    }

    component DiskAction: Rectangle {
        id: diskAction
        required property string glyph
        required property string hint
        signal triggered
        width: 26; height: 26; radius: root.shell.rounding
        color: actionArea.containsMouse ? root.shell.alpha(root.shell.foreground, .14) : "transparent"
        Text {
            anchors.centerIn: parent
            text: diskAction.glyph
            color: root.shell.alpha(root.shell.foreground, actionArea.containsMouse ? 1 : .6)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        MouseArea {
            id: actionArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: diskAction.triggered()
        }
        BarTooltip { shell: root.shell; anchorItem: diskAction; text: diskAction.hint; hovered: actionArea.containsMouse }
    }
}
