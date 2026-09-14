pragma ComponentBehavior: Bound

import QtQuick
import "RemovableModel.js" as Model

PopupCard {
    id: root
    popupName: "disks"
    contentWidth: Style.px(410)
    contentHeight: contentColumn.implicitHeight + padding * 2

    property string editingKey: ""
    property string nicknameDraft: ""

    function beginNickname(device) {
        editingKey = device.key
        nicknameDraft = String(device.nickname || "")
    }

    function finishNickname(save) {
        if (save) {
            const device = Removable.devices.find(candidate => candidate.key === editingKey)
            if (device) Removable.setNickname(device, nicknameDraft)
        }
        editingKey = ""
        nicknameDraft = ""
    }

    function activateVolume(volume) {
        Removable.activateVolume(volume)
        if (volume.mounted || Model.isMountable(volume) || volume.encrypted) shell.closePopup()
    }

    function handleKey(event) {
        if (!editingKey) return defaultKey(event)
        if (event.key === Qt.Key_Escape) { finishNickname(false); return true }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { finishNickname(true); return true }
        if (event.key === Qt.Key_Backspace) { nicknameDraft = nicknameDraft.slice(0, -1); return true }
        if (event.key === Qt.Key_U && event.modifiers & Qt.ControlModifier) { nicknameDraft = ""; return true }
        if (event.text && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            nicknameDraft = (nicknameDraft + event.text).slice(0, 48)
            return true
        }
        return true
    }

    onOpenChanged: {
        Removable.watchClosely = open
        if (open) Removable.rescan()
        else finishNickname(false)
    }

    Flickable {
        id: scroll
        width: parent.width
        height: Math.min(contentColumn.implicitHeight, Math.max(Style.px(150), root.maxHeight - root.padding * 2))
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentColumn
            width: scroll.width
            spacing: Style.sm

            PopupSection { shell: root.shell; text: "REMOVABLE"; value: Removable.devices.length || "" }
            Text {
                visible: Removable.loaded && !Removable.present
                width: parent.width; text: "Nothing plugged in"
                horizontalAlignment: Text.AlignHCenter
                color: root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            Text {
                visible: !Removable.loaded
                width: parent.width; text: "Looking for drives…"
                horizontalAlignment: Text.AlignHCenter
                color: root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }

            Row {
                width: parent.width
                spacing: Style.sm
                PopupRow {
                    width: (parent.width - parent.spacing) / 2
                    shell: root.shell; icon: Model.GLYPH_REFRESH
                    title: "Rescan"
                    centerTitle: true
                    onClicked: Removable.rescan()
                }
                PopupRow {
                    width: (parent.width - parent.spacing) / 2
                    shell: root.shell; icon: Model.GLYPH_EJECT
                    title: Removable.pendingEjectPath ? "Cancel eject" : "Eject all"
                    centerTitle: true; enabled: Removable.devices.length > 0 && !Removable.busy
                    onClicked: Removable.pendingEjectPath ? Removable.cancelPendingEject() : Removable.ejectAll()
                }
            }

            Text {
                visible: text !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: Removable.lastError || Removable.actionStatus
                color: Removable.lastError ? root.shell.role("error", root.shell.foreground)
                    : root.shell.alpha(root.shell.foreground, .6)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                wrapMode: Text.WordWrap
            }

            PopupRow {
                visible: Removable.pendingEjectPath !== ""
                width: parent.width; shell: root.shell
                icon: Model.GLYPH_ALERT; title: "Waiting for writes to finish"
                detail: "The drive will eject after two quiet samples"
                active: true
                onClicked: Removable.cancelPendingEject()
            }

            PopupRow {
                visible: Removable.blockers.length > 0
                width: parent.width; shell: root.shell
                icon: Model.GLYPH_UNMOUNT; title: "Held by " + Model.plain(Model.describeBlockers(Removable.blockers))
                detail: "Click to force-unmount explicitly"
                titleColor: root.shell.role("warning", root.shell.foreground)
                onClicked: Removable.forceUnmountBlocked()
            }

            Repeater {
                model: Removable.devices
                DeviceCard {
                    required property var modelData
                    width: contentColumn.width
                    device: modelData
                }
            }

            Column {
                visible: Removable.portables.length > 0 || Removable.supportHint !== ""
                width: parent.width; spacing: Style.xxs
                PopupSeparator { shell: root.shell }
                PopupSection { shell: root.shell; text: "PHONES & CAMERAS"; value: Removable.portables.length || "" }
                Text {
                    visible: Removable.supportHint !== ""
                    width: parent.width; textFormat: Text.PlainText
                    text: Model.plain(Removable.supportHint)
                    color: root.shell.role("warning", root.shell.foreground)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: Removable.portables
                    PortableRow {
                        required property var modelData
                        width: parent.width
                        entry: modelData
                    }
                }
            }

            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "UDISKIE" }
            SettingRow {
                width: parent.width
                label: "Automount"; detail: "Mount removable media on plug-in"
                checked: Removable.automount
                onToggled: Removable.toggleAutomount()
            }
            SettingRow {
                width: parent.width
                label: "Notifications"; detail: "Announce mounts and removals"
                checked: Removable.notificationsEnabled
                onToggled: Removable.setNotifications(!Removable.notificationsEnabled)
            }
        }
    }

    component DeviceCard: Column {
        id: deviceCard
        required property var device
        spacing: Style.xxs
        readonly property string activity: Removable.activityLabel(device)
        readonly property bool ejectPending: Removable.pendingEjectPath === device.path || Removable.pendingEjectPath === "*"

        Item {
            width: parent.width; height: header.implicitHeight
            PopupRow {
                id: header
                anchors.fill: parent; shell: root.shell; interactive: false
                icon: deviceCard.device.glyph
                iconColor: deviceCard.activity ? root.shell.role("warning", root.shell.foreground) : root.shell.foreground
                title: Model.plain(deviceCard.device.title)
                detail: Model.plain((deviceCard.device.nickname ? deviceCard.device.deviceName + " · " : "")
                    + deviceCard.device.sizeText + (deviceCard.activity ? " · " + deviceCard.activity : ""))
                active: deviceCard.activity !== ""
                rightInset: deviceActions.implicitWidth + Style.sm
            }
            Row {
                id: deviceActions
                anchors.right: parent.right; anchors.rightMargin: Style.xs
                anchors.verticalCenter: parent.verticalCenter
                DiskAction {
                    glyph: Model.GLYPH_PENCIL; hint: "Nickname this drive"
                    onTriggered: root.beginNickname(deviceCard.device)
                }
                DiskAction {
                    glyph: deviceCard.ejectPending ? Model.GLYPH_ALERT : Model.GLYPH_EJECT
                    hint: deviceCard.ejectPending ? "Cancel pending eject" : "Safely eject this drive"
                    danger: true; enabled: !Removable.busy
                    onTriggered: deviceCard.ejectPending ? Removable.cancelPendingEject() : Removable.eject(deviceCard.device)
                }
            }
        }

        Rectangle {
            visible: root.editingKey === deviceCard.device.key
            width: parent.width; height: Style.controlHeight
            radius: root.shell.rounding
            color: root.shell.hoverFill()
            border.color: root.shell.hoverEdge()
            Text {
                anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: (root.nicknameDraft || "Type a nickname") + "  ▏"
                color: root.nicknameDraft ? root.shell.foreground : root.shell.alpha(root.shell.foreground, .45)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                elide: Text.ElideRight
            }
        }

        Repeater {
            model: deviceCard.device.volumes
            VolumeRow {
                required property var modelData
                width: deviceCard.width
                volume: modelData
            }
        }
    }

    component VolumeRow: Item {
        id: volumeRow
        required property var volume
        readonly property bool readOnly: Removable.readOnlyFor(volume)
        readonly property bool working: Removable.busyPath === volume.fsPath
        height: row.implicitHeight

        PopupRow {
            id: row
            anchors.fill: parent; shell: root.shell
            icon: volumeRow.volume.encrypted && !volumeRow.volume.unlocked ? Model.GLYPH_LOCKED : Model.GLYPH_DISK
            title: Model.plain(volumeRow.volume.title)
            detail: volumeRow.working ? "Working…" : Model.plain(Removable.volumeMeta(volumeRow.volume))
            active: volumeRow.readOnly
            rightInset: volumeActions.implicitWidth + Style.sm
            enabled: !Removable.busy
            onClicked: button => {
                if (button === Qt.MiddleButton) Removable.copyPath(volumeRow.volume)
                else if (button === Qt.LeftButton) root.activateVolume(volumeRow.volume)
            }
        }
        Row {
            id: volumeActions
            anchors.right: parent.right; anchors.rightMargin: Style.xs
            anchors.verticalCenter: parent.verticalCenter
            DiskAction {
                visible: volumeRow.volume.mounted && !volumeRow.readOnly || !volumeRow.volume.mounted && Model.isMountable(volumeRow.volume)
                glyph: Model.GLYPH_READONLY; hint: "Mount read-only"
                enabled: !Removable.busy
                onTriggered: {
                    const result = Removable.mountReadOnly(volumeRow.volume)
                    if (result !== "ok" && result !== "unchanged") Removable.lastError = result
                }
            }
            DiskAction {
                visible: volumeRow.volume.mounted || Model.isMountable(volumeRow.volume)
                glyph: Model.GLYPH_FOLDER; hint: "Open in file manager"
                enabled: volumeRow.volume.mounted || !Removable.busy
                onTriggered: root.activateVolume(volumeRow.volume)
            }
            DiskAction {
                visible: volumeRow.volume.mounted || Model.isMountable(volumeRow.volume) || volumeRow.volume.encrypted
                glyph: volumeRow.volume.mounted ? Model.GLYPH_UNMOUNT
                    : volumeRow.volume.encrypted && !volumeRow.volume.unlocked ? Model.GLYPH_LOCKED : Model.GLYPH_MOUNT
                hint: volumeRow.volume.mounted ? "Unmount"
                    : volumeRow.volume.encrypted && !volumeRow.volume.unlocked ? "Unlock in terminal" : "Mount"
                enabled: !Removable.busy
                onTriggered: Removable.toggleMount(volumeRow.volume)
            }
        }
    }

    component PortableRow: Item {
        id: portableRow
        required property var entry
        height: row.implicitHeight
        PopupRow {
            id: row
            anchors.fill: parent; shell: root.shell
            icon: Model.portableGlyph(portableRow.entry)
            title: Model.plain(portableRow.entry.name)
            detail: Model.portableMeta(portableRow.entry)
            rightInset: portableAction.width + Style.sm
            enabled: !Removable.busy
            onClicked: { Removable.openPortable(portableRow.entry); root.shell.closePopup() }
        }
        DiskAction {
            id: portableAction
            anchors.right: parent.right; anchors.rightMargin: Style.xs
            anchors.verticalCenter: parent.verticalCenter
            glyph: portableRow.entry.mounted ? Model.GLYPH_UNMOUNT : Model.GLYPH_MOUNT
            hint: portableRow.entry.mounted ? "Unmount" : "Mount"
            enabled: !Removable.busy
            onTriggered: Removable.togglePortable(portableRow.entry)
        }
    }

    component SettingRow: Item {
        id: settingRow
        required property string label
        required property string detail
        required property bool checked
        signal toggled
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
        id: action
        required property string glyph
        required property string hint
        property bool danger: false
        signal triggered
        width: Style.px(27); height: Style.px(27); radius: root.shell.rounding
        opacity: enabled ? 1 : .35
        color: actionMouse.containsMouse ? root.shell.hoverFill(1.3) : "transparent"
        Text {
            anchors.centerIn: parent; text: action.glyph
            color: action.danger && actionMouse.containsMouse ? root.shell.role("error", root.shell.foreground)
                : root.shell.alpha(root.shell.foreground, actionMouse.containsMouse ? 1 : .65)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        MouseArea {
            id: actionMouse; anchors.fill: parent; enabled: action.enabled
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: action.triggered()
        }
        BarTooltip { shell: root.shell; anchorItem: action; text: action.hint; hovered: actionMouse.containsMouse }
    }
}
