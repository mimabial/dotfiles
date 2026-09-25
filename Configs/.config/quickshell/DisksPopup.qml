pragma ComponentBehavior: Bound

import QtQuick
import "RemovableModel.js" as Model

PopupCard {
    id: root
    popupName: "disks"
    contentWidth: Style.px(410)
    contentHeight: scroll.height + padding * 2

    property string toolsPath: ""
    property string toolsIdentity: ""
    property string toolsMode: ""
    property bool zeroBeforeFormat: false
    property string activeTab: "local"
    property string expandedDevicePath: ""
    property string settingsDevicePath: ""
    property string expandedNetworkPath: ""
    property string unlockPath: ""
    property string expandedVolumePath: ""
    property bool settingsOpen: false
    property real tabHeight: 0
    readonly property var toolsVolume: Removable.filesystemTarget(toolsPath)

    function showTools(volume, mode) {
        if (mode && toolsPath === volume.fsPath && toolsMode === mode) { closeTools(); return }
        const device = Removable.deviceOfVolume(volume)
        toolsPath = volume.fsPath
        if (device) expandedDevicePath = device.path
        toolsIdentity = Removable.identityOf(Removable.filesystemTarget(volume.fsPath) || volume)
        toolsMode = mode || ""
        zeroBeforeFormat = false
    }

    function closeTools() {
        toolsPath = ""
        toolsIdentity = ""
        toolsMode = ""
        zeroBeforeFormat = false
    }

    function toggleDevice(path) {
        expandedDevicePath = expandedDevicePath === path ? "" : path
        settingsDevicePath = ""
    }

    function toggleSettings(path) {
        settingsDevicePath = settingsDevicePath === path ? "" : path
        expandedDevicePath = path
    }

    function guardBadge(label) { return {text: Model.GLYPH_LOCKED + " " + label, color: shell.role("error", shell.foreground)} }

    function pickTab(tab) {
        tabHeight = Math.max(tabHeight, contentColumn.implicitHeight)
        activeTab = tab
    }

    function checkVolume(volume) {
        showTools(volume)
        Removable.filesystemAction("check", volume, "", "", toolsIdentity)
    }

    function activateVolume(volume, openAfter) {
        if (volume.encrypted && !volume.unlocked) { unlockPath = volume.path; return }
        if (openAfter === false) { Removable.toggleMount(volume); return }
        Removable.activateVolume(volume)
        if (volume.mounted || Model.isMountable(volume)) shell.closePopup()
    }

    function letterKey(text) {
        const row = navigableRows[cursorIndex] || {}, volume = row.volume || null
        const device = row.device || Removable.deviceOfVolume(volume) || Removable.devices[0] || null
        const actions = {
            j: () => moveCursor(1), k: () => moveCursor(-1), " ": () => activateCursor(),
            m: () => volume && activateVolume(volume, false), o: () => Removable.openVolume(volume), y: () => Removable.copyPath(volume),
            t: () => volume && Removable.openTerminal(volume.mountpoint, false), d: () => volume && Removable.openTerminal(volume.mountpoint, true),
            l: () => volume && showTools(volume, "label"), f: () => volume && showTools(volume, "format"),
            c: () => volume && checkVolume(volume),
            e: () => Removable.eject(device), x: () => Removable.eject(device), E: () => Removable.ejectAll(),
            r: () => Removable.rescan(), s: () => Removable.setOption("showSystem", !Removable.store.showSystem)
        }
        if (!actions[text]) return false
        actions[text]()
        return true
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape && (toolsPath || unlockPath)) { closeTools(); unlockPath = ""; resumeKeyboard(); return true }
        return !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && letterKey(event.text) || defaultKey(event)
    }

    onOpenChanged: {
        Removable.watchClosely = open
        if (open) {
            Removable.rescan()
            if (Removable.devices.length) expandedDevicePath = Removable.devices[0].path
        }
        else { closeTools(); expandedDevicePath = ""; settingsDevicePath = ""; expandedVolumePath = ""; expandedNetworkPath = ""; unlockPath = ""; settingsOpen = false; tabHeight = 0 }
    }

    Connections { target: Removable; function onUiRequest(name, value) { if (name === "activeTab") root.pickTab(value); else root[name] = value } }

    Flickable {
        id: scroll
        width: parent.width
        height: Math.min(Math.max(contentColumn.implicitHeight, root.tabHeight), Math.max(Style.px(150), root.maxHeight - root.padding * 2))
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentColumn
            width: scroll.width
            spacing: Style.sm

            Row {
                width: parent.width; spacing: Style.xxs
                StorageTab { width: (parent.width - parent.spacing) / 2; label: "LOCAL"; glyph: Model.GLYPH_DISK
                    count: Removable.devices.length + Removable.portables.length; selected: root.activeTab === "local"
                    onPicked: root.pickTab("local") }
                StorageTab { width: (parent.width - parent.spacing) / 2; label: "NETWORK"; glyph: Model.GLYPH_SERVER
                    count: Removable.networkShares.length; selected: root.activeTab === "network"
                    onPicked: root.pickTab("network") }
            }

            SystemToggle { visible: root.activeTab === "local" && root.position === "top" }
            PopupSection { visible: root.activeTab === "local"; shell: root.shell; text: "REMOVABLE"; value: Removable.devices.length || "" }
            Text {
                visible: root.activeTab === "local" && Removable.loaded && Removable.devices.length === 0
                width: parent.width; text: "No removable drives"
                horizontalAlignment: Text.AlignHCenter
                color: root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            Text {
                visible: root.activeTab === "local" && !Removable.loaded
                width: parent.width; text: "Looking for drives…"
                horizontalAlignment: Text.AlignHCenter
                color: root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
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
                visible: root.activeTab === "local" && Removable.pendingEjectPath !== ""
                width: parent.width; shell: root.shell
                icon: Model.GLYPH_ALERT; title: "Waiting for writes to finish"
                detail: "The drive will eject after two quiet samples"
                active: true
                onClicked: Removable.cancelPendingEject()
            }

            PopupRow {
                visible: root.activeTab === "local" && Removable.blockers.length > 0
                width: parent.width; shell: root.shell
                icon: Model.GLYPH_UNMOUNT; title: "Held by " + Model.plain(Model.describeBlockers(Removable.blockers))
                detail: "Click to force-unmount explicitly"
                titleColor: root.shell.role("warning", root.shell.foreground)
                onClicked: Removable.forceUnmountBlocked()
            }

            Repeater {
                model: root.activeTab === "local" ? Removable.devices : []
                DeviceCard {
                    required property var modelData
                    width: contentColumn.width
                    device: modelData
                }
            }

            Column {
                visible: root.activeTab === "local" && Removable.store.showSystem === true && Removable.systemDevices.length > 0
                width: parent.width; spacing: Style.xxs
                PopupSeparator { shell: root.shell }
                PopupSection { shell: root.shell; text: "SYSTEM STORAGE"; value: Removable.systemDevices.length }
                Repeater {
                    model: root.activeTab === "local" && Removable.store.showSystem === true ? Removable.systemDevices : []
                    DeviceCard { required property var modelData; width: parent.width; device: modelData }
                }
            }

            Column {
                visible: root.activeTab === "network"
                width: parent.width; spacing: Style.xxs
                PopupSection { shell: root.shell; text: "NETWORK"; value: Removable.networkShares.length }
                Text {
                    visible: Removable.networkShares.length === 0
                    width: parent.width; text: "No network or cloud shares mounted"
                    horizontalAlignment: Text.AlignHCenter
                    color: root.shell.alpha(root.shell.foreground, .5)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                Repeater {
                    model: root.activeTab === "network" ? Removable.networkShares : []
                    Rectangle {
                        id: networkItem
                        required property var modelData
                        readonly property bool expanded: root.expandedNetworkPath === modelData.mountpoint
                        width: parent.width; height: networkContent.implicitHeight + Style.sm * 2
                        radius: root.shell.rounding
                        color: root.shell.alpha(root.shell.foreground, .035)
                        border.width: 1; border.color: root.shell.alpha(root.shell.foreground, .09)
                        Column {
                            id: networkContent
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: Style.sm; spacing: Style.xxs
                            PopupRow {
                                width: parent.width; shell: root.shell; icon: Model.GLYPH_SERVER
                                title: Model.plain(networkItem.modelData.source)
                                detail: Model.plain(networkItem.modelData.fstype.toUpperCase() + " · " + networkItem.modelData.mountpoint + (networkItem.modelData.readOnly ? " · Read-only" : ""))
                                value: networkItem.expanded ? Model.GLYPH_CHEVRON_UP : Model.GLYPH_CHEVRON_DOWN
                                onClicked: root.expandedNetworkPath = networkItem.expanded ? "" : networkItem.modelData.mountpoint
                            }
                            Flow {
                                visible: networkItem.expanded
                                width: parent.width; spacing: Style.xxs
                                ActionTile { glyph: Model.GLYPH_FOLDER; label: "Open"; onTriggered: Removable.openPath(networkItem.modelData.mountpoint) }
                                ActionTile { glyph: Model.GLYPH_PIE; label: "Disk usage"; onTriggered: Removable.openTerminal(networkItem.modelData.mountpoint, true) }
                                ActionTile { glyph: Model.GLYPH_TERMINAL; label: "Terminal"; onTriggered: Removable.openTerminal(networkItem.modelData.mountpoint, false) }
                                ActionTile { glyph: Model.GLYPH_UNMOUNT; label: "Unmount"; onTriggered: Removable.unmountNetwork(networkItem.modelData) }
                            }
                        }
                    }
                }
            }

            Column {
                visible: root.activeTab === "local" && (Removable.portables.length > 0 || Removable.supportHint !== "")
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
                    model: root.activeTab === "local" ? Removable.portables : []
                    PortableRow {
                        required property var modelData
                        width: parent.width
                        entry: modelData
                    }
                }
            }

            Column {
                visible: root.activeTab === "local"
                width: parent.width; spacing: Style.xxs
                PopupSeparator { shell: root.shell }
                Rectangle {
                    width: parent.width; height: settingsCard.implicitHeight + Style.sm * 2
                    radius: root.shell.rounding
                    color: root.shell.alpha(root.shell.foreground, .035)
                    border.width: 1; border.color: root.shell.alpha(root.shell.foreground, .09)
                    Column {
                        id: settingsCard
                        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                        anchors.margins: Style.sm; spacing: Style.xxs
                        PopupRow {
                            width: parent.width; shell: root.shell; icon: Model.GLYPH_COG; title: "Settings"
                            value: root.settingsOpen ? Model.GLYPH_CHEVRON_UP : Model.GLYPH_CHEVRON_DOWN; active: root.settingsOpen
                            onClicked: root.settingsOpen = !root.settingsOpen
                        }
                        Column {
                            id: settingRows
                            visible: root.settingsOpen
                            width: parent.width; spacing: Style.xxs
                            padding: Style.controlPaddingX; topPadding: padding - settingsCard.spacing
                            Repeater {
                                model: root.settingsOpen ? [{key: "automount", label: "Automount", detail: "Mount removable media on plug-in", on: true},
                                    {key: "openOnMount", label: "Open on mount", detail: "Open volumes mounted on plug-in", on: false},
                                    {key: "notify", label: "Notifications", detail: "Announce mounts and removals", on: true},
                                    {key: "cleanTrashOnEject", label: "Empty trash on eject", detail: "Delete the drive's .Trash before ejecting", on: false},
                                    {key: "unmountOnSuspend", label: "Unmount before sleep", detail: "Cancel suspend if a drive refuses", on: true},
                                    {key: "alwaysShow", label: "Always show icon", detail: "Keep the bar icon with nothing attached", on: true}] : []
                                SettingRow {
                                    required property var modelData
                                    width: settingRows.width - settingRows.leftPadding - settingRows.rightPadding; label: modelData.label; detail: modelData.detail
                                    checked: Removable.store[modelData.key] ?? modelData.on
                                    onToggled: Removable.setOption(modelData.key, !checked)
                                }
                            }
                        }
                    }
                }
            }

            SystemToggle { visible: root.activeTab === "local" && root.position !== "top" }

            Row {
                visible: root.activeTab === "local"
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
        }
    }

    component ToolsPanel: Column {
        id: panel
        required property string path
        readonly property real inner: width - leftPadding
        readonly property string mode: root.toolsMode
        visible: root.toolsPath === path
        spacing: Style.xxs; leftPadding: Style.controlPaddingX
        function reset() {
            labelField.text = mode === "label" && root.toolsVolume ? root.toolsVolume.label : ""
            confirmField.text = ""
            if (mode === "label") labelField.forceActiveFocus()
        }
        function commit() {
            const type = mode === "format" ? formatSelect.choices[Math.max(0, formatSelect.currentIndex)].value : ""
            if (Removable.filesystemAction(mode, root.toolsVolume, type, labelField.text.trim(), root.toolsIdentity, root.zeroBeforeFormat) === "ok") root.closeTools()
            root.resumeKeyboard()
        }
        onVisibleChanged: if (visible) reset()
        onModeChanged: if (visible) reset()
        PopupRow {
            visible: !!Removable.checkedVolume && !!root.toolsVolume && Removable.checkedVolume.path === root.toolsVolume.fsPath
                && Removable.checkedVolume.uuid === root.toolsVolume.uuid && Removable.checkedVolume.verdict === false
            width: panel.inner; shell: root.shell; icon: Model.GLYPH_WRENCH
            title: "Repair filesystem"; detail: "This writes to the volume"
            enabled: !Removable.busy
            onClicked: Removable.filesystemAction("repair", root.toolsVolume, "", "", root.toolsIdentity)
        }
        PopupRow {
            visible: root.toolsMode === "" && !!root.toolsVolume && root.toolsVolume.fstype === "ntfs" && !root.toolsVolume.mounted
            width: panel.inner; shell: root.shell; icon: Model.GLYPH_WRENCH
            title: "Check, repair if needed, and mount NTFS"
            enabled: !Removable.busy
            onClicked: Removable.filesystemAction("ntfsfix", root.toolsVolume, "", "", root.toolsIdentity)
        }
        PopupRow {
            visible: (root.toolsMode === "" || root.toolsMode === "trash") && !!root.toolsVolume && root.toolsVolume.mounted
            width: panel.inner; shell: root.shell; centerTitle: true
            title: root.toolsMode === "trash" ? "Confirm empty drive trash" : "Empty drive trash"
            enabled: !Removable.busy
            onClicked: {
                if (root.toolsMode !== "trash") { root.toolsMode = "trash"; return }
                if (Removable.filesystemAction("trash", root.toolsVolume, "", "", root.toolsIdentity) === "ok") root.toolsMode = ""
            }
        }
        PopupSelect {
            id: formatSelect
            visible: root.toolsMode === "format"; width: panel.inner; shell: root.shell
            choices: [{label: "exFAT", value: "exfat"}, {label: "FAT32", value: "vfat"},
                {label: "NTFS", value: "ntfs"}, {label: "ext4", value: "ext4"}, {label: "Btrfs", value: "btrfs"}]
        }
        PopupField {
            id: labelField
            visible: root.toolsMode === "label" || root.toolsMode === "format"
            width: panel.inner; shell: root.shell; placeholderText: "Filesystem label (optional for format)"
            onAccepted: if (root.toolsMode === "label") panel.commit()
        }
        PopupRow {
            visible: root.toolsMode === "format"; width: panel.inner; shell: root.shell
            title: "Zero entire target first"; detail: "May take hours"; value: root.zeroBeforeFormat ? "On" : "Off"
            onClicked: root.zeroBeforeFormat = !root.zeroBeforeFormat
        }
        Text {
            visible: root.toolsMode === "format" && !!root.toolsVolume
            width: panel.inner; textFormat: Text.PlainText
            text: root.toolsVolume ? "Erases " + Model.plain(root.toolsVolume.title) + " (" + Model.formatBytes(root.toolsVolume.sizeBytes) + "). Type " + root.toolsVolume.name + " to confirm." : ""
            wrapMode: Text.WordWrap; color: root.shell.role("warning", root.shell.foreground)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
        PopupField {
            id: confirmField
            visible: root.toolsMode === "format"; width: panel.inner; shell: root.shell
            placeholderText: root.toolsVolume ? root.toolsVolume.name : "Device name"
        }
        PopupRow {
            visible: root.toolsMode === "label" || root.toolsMode === "format"
            width: panel.inner; shell: root.shell; centerTitle: true
            title: root.toolsMode === "format" ? "Erase and format" : "Save label"
            enabled: !Removable.busy && !!root.toolsVolume && (root.toolsMode !== "format" || confirmField.text.trim() === root.toolsVolume.name)
            onClicked: panel.commit()
        }
    }

    component SystemToggle: PopupRow {
        width: parent.width; shell: root.shell
        icon: Model.GLYPH_DISK; title: Removable.store.showSystem ? "Hide OS drives and swap" : "Show OS drives and swap"
        detail: Removable.store.showSystem ? Removable.systemDevices.length + " system drives" : "Inspect protected storage"
        onClicked: Removable.setOption("showSystem", !Removable.store.showSystem)
    }

    component DeviceCard: Rectangle {
        id: deviceCard
        required property var device
        readonly property string activity: Removable.activityLabel(device)
        readonly property bool ejectPending: Removable.pendingEjectPath === device.path || Removable.pendingEjectPath === "*"
        readonly property bool expanded: root.expandedDevicePath === device.path
        readonly property bool ejectable: device.removable && !device.isSystem
        readonly property var hook: Removable.hookFor(device) || ({})
        readonly property var health: Removable.healthFor(device) || ({state: "unavailable", text: "", temperature: ""})
        height: cardContent.implicitHeight + Style.sm * 2
        radius: root.shell.rounding
        color: root.shell.alpha(root.shell.foreground, .035)
        border.width: 1; border.color: root.shell.alpha(root.shell.foreground, .09)

        Column {
            id: cardContent
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Style.sm; spacing: Style.xxs

            Item {
                width: parent.width; height: header.implicitHeight
                PopupRow {
                    id: header
                    property var device: deviceCard.device
                    anchors.fill: parent; shell: root.shell
                    icon: deviceCard.device.glyph
                    iconColor: deviceCard.device.isSystem ? root.shell.role("error", root.shell.foreground)
                        : deviceCard.activity ? root.shell.role("warning", root.shell.foreground) : root.shell.foreground
                    title: Model.plain(deviceCard.device.title)
                    detail: Model.plain(deviceCard.device.sizeText + " · " + deviceCard.device.volumes.length
                        + (deviceCard.device.volumes.length === 1 ? " volume" : " volumes")
                        + (deviceCard.activity ? " · " + deviceCard.activity : "")
                        + (deviceCard.hook.active ? " · " + Model.hookLabel(deviceCard.hook) : ""))
                    active: deviceCard.expanded || deviceCard.activity !== ""
                    badges: deviceCard.device.isSystem ? [root.guardBadge(/^zram/.test(deviceCard.device.name) ? "SWAP" : "OS DRIVE")] : []
                    rightInset: deviceActions.implicitWidth + Style.sm
                    onClicked: root.toggleDevice(deviceCard.device.path)
                }
                Row {
                    id: deviceActions
                    anchors.right: parent.right; anchors.rightMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    DiskAction {
                        glyph: deviceCard.expanded ? Model.GLYPH_CHEVRON_UP : Model.GLYPH_CHEVRON_DOWN
                        hint: deviceCard.expanded ? "Collapse drive" : "Expand drive"
                        onTriggered: root.toggleDevice(deviceCard.device.path)
                    }
                    DiskAction {
                        visible: deviceCard.ejectable
                        glyph: Model.GLYPH_COG
                        hint: root.settingsDevicePath === deviceCard.device.path ? "Hide drive settings" : "Drive settings and tools"
                        onTriggered: root.toggleSettings(deviceCard.device.path)
                    }
                    DiskAction {
                        visible: deviceCard.ejectable
                        glyph: deviceCard.ejectPending ? Model.GLYPH_ALERT : Model.GLYPH_EJECT
                        hint: deviceCard.ejectPending ? "Cancel pending eject" : "Safely eject this drive"
                        danger: true; enabled: !Removable.busy
                        onTriggered: deviceCard.ejectPending ? Removable.cancelPendingEject() : Removable.eject(deviceCard.device)
                    }
                }
            }

            Rectangle {
                visible: deviceCard.hook.active === true && deviceCard.hook.percent >= 0
                width: parent.width; height: Style.px(3)
                radius: height / 2; color: root.shell.alpha(root.shell.foreground, .12)
                Rectangle { width: parent.width * deviceCard.hook.percent / 100; height: parent.height; radius: parent.radius; color: root.shell.accent }
            }

            Column {
                id: settingsContent
                visible: deviceCard.expanded && root.settingsDevicePath === deviceCard.device.path
                width: parent.width; spacing: Style.xs; leftPadding: Style.controlPaddingX
                Text {
                    text: "DRIVE SETTINGS"; color: root.shell.alpha(root.shell.foreground, .6)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
                }
                Flow {
                    width: parent.width - parent.leftPadding; spacing: Style.px(6)
                    ActionTile {
                        glyph: Model.GLYPH_READONLY
                        label: Model.driveSetting(Removable.store, deviceCard.device, "readOnly") ? "Read-only: On" : "Read-only: Off"
                        onTriggered: Removable.setDriveSetting(deviceCard.device, "readOnly", !Model.driveSetting(Removable.store, deviceCard.device, "readOnly"))
                    }
                    ActionTile {
                        glyph: Model.GLYPH_FOLDER
                        readonly property var autoOpen: Model.driveSetting(Removable.store, deviceCard.device, "autoOpen")
                        label: "Auto-open: " + (autoOpen === true ? "On" : autoOpen === false ? "Off" : "Default")
                        onTriggered: Removable.setDriveSetting(deviceCard.device, "autoOpen", autoOpen === undefined ? true : autoOpen === true ? false : null)
                    }
                    ActionTile {
                        glyph: Model.GLYPH_WRENCH; label: "Format drive"; danger: true
                        onTriggered: root.showTools({fsPath: deviceCard.device.path, uuid: "", label: ""}, "format")
                    }
                }
            }
            ToolsPanel {
                path: deviceCard.device.path; width: parent.width
                visible: root.toolsPath === path && !deviceCard.device.volumes.some(volume => volume.fsPath === path)
            }
            Item {
                id: healthStrip
                visible: deviceCard.expanded && deviceCard.health.state !== "unavailable"
                width: parent.width; height: Style.px(28)
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.shell.alpha(root.shell.foreground, .1) }
                readonly property color statusColor: deviceCard.health.state === "healthy" ? root.shell.accent
                    : deviceCard.health.state === "failing" ? root.shell.role("error", root.shell.foreground)
                    : root.shell.role("warning", root.shell.foreground)
                Text {
                    id: healthIcon
                    anchors.left: parent.left; anchors.leftMargin: Style.sm; anchors.verticalCenter: parent.verticalCenter
                    text: deviceCard.health.state === "healthy" ? Model.GLYPH_HEALTHY : Model.GLYPH_ALERT
                    color: healthStrip.statusColor; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                Text {
                    id: healthLabel
                    anchors.left: healthIcon.right; anchors.leftMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, telemetryPill.x - x - healthRefresh.width - Style.xxs * 2)
                    text: deviceCard.health.text
                    color: healthStrip.statusColor; elide: Text.ElideRight
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                }
                DiskAction {
                    id: healthRefresh
                    anchors.left: healthLabel.right; anchors.leftMargin: Style.xxs
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.px(18); height: Style.px(18)
                    glyph: Model.GLYPH_REFRESH; hint: "Refresh SMART health"
                    onTriggered: Removable.probeHealth(deviceCard.device)
                }
                Rectangle {
                    id: telemetryPill
                    anchors.right: parent.right; anchors.rightMargin: Style.sm
                    anchors.verticalCenter: parent.verticalCenter
                    width: pillContent.implicitWidth + Style.sm; height: Style.px(20); radius: Style.xs
                    color: root.shell.alpha(healthStrip.statusColor, .12)
                    Row {
                        id: pillContent
                        anchors.centerIn: parent; spacing: Style.xxs
                        Text {
                            text: telemetryGraph.temperature ? Model.GLYPH_THERMOMETER + " " + deviceCard.health.temperature : "I/O"
                            color: healthStrip.statusColor; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
                        }
                        Canvas {
                            id: telemetryGraph
                            width: Style.px(32); height: Style.px(10)
                            anchors.verticalCenter: parent.verticalCenter
                            antialiasing: true
                            readonly property var temperatures: Removable.temperatureHistory[Removable.healthKey(deviceCard.device)] || []
                            readonly property bool temperature: !!deviceCard.health.temperature && temperatures.length > 0
                            readonly property var samples: temperature ? temperatures : Removable.activityHistory[Removable.healthKey(deviceCard.device)] || []
                            onSamplesChanged: requestPaint()
                            onVisibleChanged: if (visible) requestPaint()
                            onPaint: {
                                const ctx = getContext("2d"), values = samples.length ? samples : [0, 0]
                                ctx.clearRect(0, 0, width, height)
                                const low = Math.min(...values), span = Math.max(...values) - low
                                ctx.strokeStyle = healthStrip.statusColor; ctx.lineWidth = 1.5; ctx.beginPath()
                                for (let i = 0; i < Math.max(2, values.length); ++i) {
                                    const x = i * width / Math.max(1, values.length - 1)
                                    const y = height / 2 - (span ? (values[Math.min(i, values.length - 1)] - low) / span - .5 : 0) * (height - 2)
                                    if (i) ctx.lineTo(x, y); else ctx.moveTo(x, y)
                                }
                                ctx.stroke()
                            }
                        }
                    }
                }
            }
            Repeater {
                model: deviceCard.expanded ? deviceCard.device.volumes : []
                VolumeRow {
                    required property var modelData
                    width: cardContent.width
                    volume: modelData
                    system: deviceCard.device.isSystem || !deviceCard.device.removable
                }
            }
        }
    }

    component VolumeRow: Column {
        id: volumeRow
        required property var volume
        required property bool system
        readonly property bool readOnly: Removable.readOnlyFor(volume)
        readonly property bool working: Removable.busyPath === volume.fsPath
        readonly property bool expanded: root.expandedVolumePath === volume.fsPath
        height: implicitHeight; spacing: Style.xxs

        Item {
            width: parent.width; height: row.implicitHeight
            PopupRow {
                id: row
                property var volume: volumeRow.volume
                width: parent.width; height: implicitHeight; shell: root.shell
                icon: volumeRow.volume.encrypted && !volumeRow.volume.unlocked ? Model.GLYPH_LOCKED : Model.GLYPH_DISK
                title: Model.plain(volumeRow.volume.title)
                badges: (volumeRow.volume.fstypeLabel && volumeRow.volume.fstype !== "swap" ? [{text: volumeRow.volume.fstypeLabel,
                    color: volumeRow.volume.fstype === "ntfs" && !volumeRow.volume.mounted ? root.shell.role("error", root.shell.foreground)
                        : root.shell.alpha(root.shell.foreground, .6)}] : [])
                    .concat(volumeRow.volume.isSystem ? [root.guardBadge(volumeRow.volume.fstype === "swap" ? "SWAP"
                        : volumeRow.volume.mountpoint === "/" ? "OS ROOT" : /^\/(boot|efi)/.test(volumeRow.volume.mountpoint) ? "BOOT" : "SYSTEM")] : [])
                detail: volumeRow.working ? "Working…" : Model.plain(Removable.volumeMeta(volumeRow.volume))
                rightInset: volumeActions.implicitWidth + Style.sm
                enabled: volumeRow.system ? volumeRow.volume.mounted && volumeRow.volume.fstype !== "swap" : !Removable.busy
                onClicked: button => {
                    if (button === Qt.MiddleButton) Removable.copyPath(volumeRow.volume)
                    else if (button === Qt.LeftButton) {
                        if (volumeRow.system) Removable.openVolume(volumeRow.volume)
                        else root.activateVolume(volumeRow.volume)
                    }
                }
            }
            Row {
                id: volumeActions
                anchors.right: parent.right; anchors.rightMargin: Style.xs
                anchors.verticalCenter: parent.verticalCenter
                DiskAction {
                    visible: volumeRow.volume.fstype !== "swap" && (volumeRow.volume.mounted || !volumeRow.system && (Model.isMountable(volumeRow.volume) || volumeRow.volume.encrypted))
                    glyph: volumeRow.volume.mounted ? Model.GLYPH_FOLDER
                        : volumeRow.volume.encrypted && !volumeRow.volume.unlocked ? Model.GLYPH_LOCKED : Model.GLYPH_MOUNT
                    hint: volumeRow.volume.mounted ? "Open in file manager"
                        : volumeRow.volume.encrypted && !volumeRow.volume.unlocked ? "Unlock" : "Mount"
                    enabled: !Removable.busy
                    onTriggered: volumeRow.volume.mounted ? Removable.openVolume(volumeRow.volume) : root.activateVolume(volumeRow.volume, false)
                }
                DiskAction {
                    visible: volumeRow.volume.fstype !== "swap"
                    glyph: volumeRow.expanded ? Model.GLYPH_CHEVRON_UP : Model.GLYPH_DOTS
                    hint: volumeRow.expanded ? "Hide volume actions" : "Show volume actions"
                    onTriggered: root.expandedVolumePath = volumeRow.expanded ? "" : volumeRow.volume.fsPath
                }
            }
        }
        PopupField {
            visible: root.unlockPath === volumeRow.volume.path
            width: parent.width; shell: root.shell
            echoMode: TextInput.Password; placeholderText: "Passphrase for " + Model.plain(volumeRow.volume.title)
            onVisibleChanged: if (visible) forceActiveFocus()
            onAccepted: {
                const result = Removable.unlock(volumeRow.volume, text)
                text = ""
                if (result !== "ok") Removable.lastError = result
                root.unlockPath = ""; root.resumeKeyboard()
            }
        }
        Rectangle {
            visible: volumeRow.volume.mounted && volumeRow.volume.fssize > 0
            width: parent.width; height: Style.px(3)
            radius: height / 2; color: root.shell.alpha(root.shell.foreground, .12)
            Rectangle { width: parent.width * Model.usedFraction(volumeRow.volume); height: parent.height; radius: parent.radius; color: root.shell.accent }
        }
        Row {
            visible: volumeRow.expanded
            spacing: Style.xxs; leftPadding: Style.controlPaddingX
            DiskAction {
                visible: !volumeRow.system && (volumeRow.volume.mounted && !volumeRow.readOnly || !volumeRow.volume.mounted && Model.isMountable(volumeRow.volume))
                glyph: Model.GLYPH_READONLY; hint: "Mount read-only"; enabled: !Removable.busy
                onTriggered: {
                    const result = Removable.mountReadOnly(volumeRow.volume)
                    if (result !== "ok" && result !== "unchanged") Removable.lastError = result
                }
            }
            DiskAction {
                visible: !volumeRow.system && volumeRow.volume.fstype !== ""; glyph: Model.GLYPH_STETHOSCOPE; hint: "Check for errors"
                enabled: !Removable.busy; onTriggered: root.checkVolume(volumeRow.volume)
            }
            DiskAction {
                visible: !volumeRow.system && volumeRow.volume.fstype !== ""; glyph: Model.GLYPH_TAG; hint: "Rename the volume label"
                onTriggered: root.showTools(volumeRow.volume, "label")
            }
            DiskAction {
                visible: !volumeRow.system && !volumeRow.volume.mounted; glyph: Model.GLYPH_ERASER; hint: "Format"; danger: true
                onTriggered: root.showTools(volumeRow.volume, "format")
            }
            DiskAction {
                visible: volumeRow.volume.mounted; glyph: Model.GLYPH_PIE; hint: "Disk usage"
                onTriggered: Removable.openTerminal(volumeRow.volume.mountpoint, true)
            }
            DiskAction {
                visible: volumeRow.volume.mounted; glyph: Model.GLYPH_TERMINAL; hint: "Terminal at the mount point"
                onTriggered: Removable.openTerminal(volumeRow.volume.mountpoint, false)
            }
            DiskAction {
                visible: volumeRow.volume.encrypted && volumeRow.volume.unlocked; glyph: Model.GLYPH_LOCKED
                hint: "Unmount and close the encrypted container"; enabled: !Removable.busy
                onTriggered: { const result = Removable.lock(volumeRow.volume); if (result !== "ok") Removable.lastError = result }
            }
            DiskAction {
                visible: !volumeRow.system && volumeRow.volume.mounted; glyph: Model.GLYPH_UNMOUNT; hint: "Unmount"
                enabled: !Removable.busy
                onTriggered: Removable.unmount(volumeRow.volume, false)
            }
        }
        ToolsPanel { path: volumeRow.volume.fsPath; width: parent.width }
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
            anchors.left: parent.left
            anchors.right: settingSwitch.left; anchors.rightMargin: Style.sm
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

    component StorageTab: Rectangle {
        id: tab
        required property string label
        required property string glyph
        required property int count
        required property bool selected
        signal picked
        height: Style.px(32); radius: root.shell.rounding
        color: selected ? root.shell.alpha(root.shell.accent, .18) : tabArea.containsMouse ? root.shell.hoverFill() : root.shell.alpha(root.shell.foreground, .04)
        border.width: 1; border.color: root.shell.alpha(root.shell.foreground, selected ? .22 : .08)
        Text {
            anchors.centerIn: parent
            text: tab.glyph + "  " + tab.label + " (" + tab.count + ")"
            color: tab.selected ? root.shell.foreground : root.shell.alpha(root.shell.foreground, .6)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: tab.selected
        }
        MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.picked() }
    }

    component ActionTile: Rectangle {
        id: tile
        required property string glyph
        required property string label
        property string hint: ""
        property bool danger: false
        readonly property color tint: danger ? root.shell.role("error", root.shell.foreground) : root.shell.foreground
        signal triggered
        width: tileContent.implicitWidth + Style.px(18); height: Style.px(28)
        radius: root.shell.rounding; opacity: enabled ? 1 : .35
        color: root.shell.alpha(tint, tileArea.containsMouse ? (danger ? .18 : .12) : .04)
        border.width: 1
        border.color: root.shell.alpha(tint, tileArea.containsMouse ? (danger ? .45 : .22) : danger ? .25 : .08)
        Behavior on color { ColorAnimation { duration: 60 } }
        Row {
            id: tileContent; anchors.centerIn: parent; spacing: Style.px(6)
            Text {
                anchors.verticalCenter: parent.verticalCenter; text: tile.glyph; color: tile.tint
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter; text: tile.label; color: tile.tint
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
            }
        }
        MouseArea { id: tileArea; anchors.fill: parent; enabled: tile.enabled; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.triggered() }
        BarTooltip { shell: root.shell; anchorItem: tile; text: tile.hint; hovered: tileArea.containsMouse && tile.hint !== "" }
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
