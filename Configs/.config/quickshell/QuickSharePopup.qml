pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs as Bar
import qs.monitor.Ui as Ui
import qs.Commons as Commons
import "Units.js" as Units

Bar.PopupCard {
    id: root
    readonly property var service: shell.quickshare
    readonly property color foreground: shell.foreground
    readonly property color accent: shell.accent
    readonly property color dim: shell.mutedText
    readonly property color urgent: shell.role("error", foreground)
    readonly property string fontFamily: shell.fontFamily
    readonly property bool enabledActions: service.online && !service.busy
    readonly property string errorText: service.error || (service.snapshot.errors || []).join("\n")
    readonly property int panelHeightLimit: Commons.Style.space(720)
    property bool settingsOpen: false
    property bool selectionExpanded: true
    property string dismissedError: ""
    popupName: "quickshare"
    contentWidth: Commons.Style.space(520)
    contentHeight: scroll.height + padding * 2
    onOpenChanged: if (open) { service.effectsAnchorWindow = root; service.effectsAnchorItem = anchorItem }

    component BodyText: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.body
        wrapMode: Text.Wrap
    }
    component ActionButton: Ui.Button {
        id: action
        property string hint: ""
        property alias cursored: action.hasCursor
        readonly property bool navigable: enabled
        function activateKeyboard() { clicked() }
        foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
        radius: root.shell.rounding
        color: activeFocus || hot ? root.shell.hoverFill() : selected || active ? root.shell.selectedFill() : "transparent"
        borderSpec: Commons.Border.flat(activeFocus || hasCursor ? root.shell.hoverEdge(.85)
            : selected || active ? root.shell.selectedEdge()
            : bordered ? root.shell.alpha(root.foreground, root.borderOpacity) : "transparent", root.shell.borderWidth)
        focusable: true; bordered: true
        opacity: enabled ? 1 : .5
        Accessible.role: Accessible.Button
        Accessible.name: text || hint
        Bar.BarTooltip { shell: root.shell; anchorItem: action; text: action.hint; hovered: action.hot }
        Bar.PopupPointer { shell: root.shell; row: action }
    }
    component SectionCard: Ui.BorderSurface {
        id: card
        default property alias content: body.data
        Layout.fillWidth: true
        implicitHeight: body.implicitHeight + body.anchors.topMargin * 2
        color: "transparent"
        borderSpec: Commons.Border.flat(root.shell.alpha(root.borderColor, root.borderOpacity), root.shell.borderWidth)
        radius: root.shell.rounding
        ColumnLayout {
            id: body
            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
            anchors.margins: Commons.Style.space(14)
            spacing: Commons.Style.space(10)
        }
    }
    component StatusBadge: Ui.BorderSurface {
        id: badge
        property string caption: ""
        property bool emphasized: false
        property bool muted: false
        implicitWidth: label.implicitWidth + Commons.Style.space(14)
        implicitHeight: label.implicitHeight + Commons.Style.space(8)
        color: emphasized ? root.shell.selectedFill() : "transparent"
        borderSpec: Commons.Border.flat(emphasized ? root.shell.selectedEdge() : root.shell.alpha(root.borderColor, root.borderOpacity), root.shell.borderWidth)
        radius: root.shell.rounding
        opacity: muted ? .5 : 1
        Text {
            id: label
            anchors.centerIn: parent; text: badge.caption; textFormat: Text.PlainText
            color: badge.emphasized ? root.accent : root.dim
            font.family: root.fontFamily; font.pixelSize: Commons.Style.font.caption; font.bold: true
        }
    }
    component EmptyState: RowLayout {
        id: empty
        property string icon: ""
        property string title: ""
        property string description: ""
        Layout.fillWidth: true; spacing: Commons.Style.space(14)
        BodyText { Layout.fillWidth: false; text: empty.icon; color: root.accent; font.pixelSize: Commons.Style.font.display; Accessible.ignored: true }
        ColumnLayout {
            Layout.fillWidth: true; spacing: Commons.Style.space(4)
            BodyText { text: empty.title; font.bold: true }
            BodyText { text: empty.description; color: root.dim; font.pixelSize: Commons.Style.font.bodySmall }
        }
    }
    component SectionHeader: Ui.PanelSectionHeader {
        Layout.fillWidth: true; foreground: root.foreground; color: root.dim; fontFamily: root.fontFamily
    }

    Flickable {
        id: scroll
        width: parent.width
        height: Math.min(column.implicitHeight, root.panelHeightLimit, root.maxHeight - root.padding * 2 - root.keyboardHintHeight)
        contentWidth: width; contentHeight: column.implicitHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: Bar.PopupScrollBar { shell: root.shell }
        ColumnLayout {
            id: column
            width: scroll.width; spacing: Commons.Style.space(16)
            RowLayout {
                Layout.fillWidth: true; spacing: Commons.Style.space(14)
                Rectangle {
                    Layout.preferredWidth: Commons.Style.space(48); Layout.preferredHeight: width
                    radius: root.shell.rounding; color: root.shell.selectedFill()
                    Text {
                        anchors.centerIn: parent; text: "󰒗"; color: root.accent
                        font.family: root.fontFamily; font.pixelSize: Commons.Style.font.heading; Accessible.ignored: true
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: Commons.Style.space(4)
                    BodyText { text: "Quick Share"; font.pixelSize: Commons.Style.font.title; font.bold: true }
                    BodyText {
                        text: "Android file sharing".toUpperCase()
                        color: root.dim; font.pixelSize: Commons.Style.font.caption; font.letterSpacing: Commons.Style.space(1)
                    }
                }
                StatusBadge {
                    Layout.alignment: Qt.AlignTop; muted: !root.service.online
                    caption: root.service.online ? "Ready" : "Unavailable"
                }
                ActionButton {
                    bordered: false; iconText: "󰅖"; onClicked: root.shell.closePopup()
                    hint: "Close panel · transfers keep running"
                }
            }
            BodyText {
                text: "Powered by Jhonny Suarez - PuroDelphi"; color: root.dim; font.pixelSize: Commons.Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter; Layout.topMargin: Commons.Style.spacing.controlGap
            }
            RowLayout {
                Layout.fillWidth: true; spacing: Commons.Style.spacing.controlGap
                ActionButton {
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    iconText: root.service.discoverable ? "󰈈" : "󰈉"
                    text: root.service.discoverable ? "Hide · " + root.service.remainingSeconds + " s"
                        : "Receive for " + root.service.receiveSeconds + " s"
                    hint: "Make this computer visible to nearby devices temporarily"
                    active: root.service.discoverable; enabled: root.enabledActions; onClicked: root.service.visibility()
                }
                ActionButton {
                    iconText: "󰑐"; hint: "Refresh status and devices"
                    onClicked: root.service.online
                        ? root.service.run(["status"], "", output => root.service.acceptSnapshot(JSON.parse(output))) : root.service.reconnect()
                }
            }
            Flow {
                Layout.fillWidth: true; spacing: Commons.Style.space(6)
                Repeater {
                    model: [{key: "lan", name: "LAN"}, {key: "bluetooth", name: "Bluetooth"},
                        {key: "hotspot", name: "Hotspot"}]
                    StatusBadge {
                        required property var modelData
                        readonly property bool available: root.service.online && !!root.service.snapshot.capabilities?.[modelData.key]
                        caption: modelData.name + (available ? " 󰄬" : " —"); muted: !available
                    }
                }
            }
            SectionCard {
                visible: root.errorText !== "" && root.errorText !== root.dismissedError
                borderSpec: Commons.Border.flat(root.shell.alpha(root.urgent, root.borderOpacity), root.shell.borderWidth)
                BodyText { text: "Attention required"; color: root.urgent; font.bold: true }
                BodyText { text: root.errorText; font.pixelSize: Commons.Style.font.bodySmall; wrapMode: Text.WrapAnywhere }
                ActionButton { text: "Dismiss"; onClicked: root.dismissedError = root.errorText }
            }
            SectionCard {
                ActionButton {
                    Layout.fillWidth: true; bordered: false; leftAlign: true
                    iconText: root.selectionExpanded ? "󰅀" : "󰅂"
                    text: "Send files"
                        + (root.service.selectedFiles.length ? " · " + root.service.selectedFiles.length : "")
                    fontSize: Commons.Style.font.subtitle
                    onClicked: root.selectionExpanded = !root.selectionExpanded
                }
                ColumnLayout {
                    visible: root.selectionExpanded; Layout.fillWidth: true; spacing: Commons.Style.space(10)
                    SectionHeader { text: "NEARBY DEVICES" }
                    EmptyState {
                        visible: !root.service.devices.length; icon: "󰄜"
                        title: "Find your Android"
                        description: "Open Quick Share → Receive on your phone and keep Bluetooth on."
                    }
                    Repeater {
                        model: root.service.devices
                        ActionButton {
                            required property var modelData
                            Layout.fillWidth: true; leftAlign: true
                            selected: root.service.selectedPeer === modelData.id
                            iconText: selected ? "󰄬" : "󰄜"
                            text: modelData.name + " · " + root.service.medium(modelData.transport)
                            enabled: root.service.online; onClicked: root.service.selectedPeer = modelData.id
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Commons.Style.spacing.controlGap
                        ActionButton {
                            Layout.fillWidth: true; iconText: "󰉋"; enabled: root.enabledActions; onClicked: root.service.pickFiles()
                            text: root.service.picking ? "Choosing…" : "Choose files…"
                        }
                        ActionButton {
                            iconText: "󰆴"; text: "Clear"
                            enabled: root.service.selectedFiles.length > 0 && !root.service.busy; onClicked: root.service.selectedFiles = []
                        }
                    }
                    EmptyState {
                        visible: !root.service.selectedFiles.length; icon: "󰈙"
                        title: "Your next transfer"
                        description: "Choose one or more files, or use “Send via Quick Share” in your file manager."
                    }
                    Repeater {
                        model: root.service.selectedFiles
                        ColumnLayout {
                            id: selectedFile
                            required property string modelData
                            Layout.fillWidth: true; spacing: Commons.Style.space(2)
                            BodyText { text: selectedFile.modelData.slice(selectedFile.modelData.lastIndexOf("/") + 1); font.bold: true }
                            BodyText { text: selectedFile.modelData; font.pixelSize: Commons.Style.font.caption; color: root.dim; wrapMode: Text.WrapAnywhere }
                        }
                    }
                    ActionButton {
                        Layout.fillWidth: true; iconText: "󰒗"
                        text: "Send" + (root.service.selectedFiles.length ? " · " + root.service.selectedFiles.length
                            + (root.service.selectedFiles.length === 1 ? " file" : " files") : "")
                        active: enabled
                        enabled: root.enabledActions && root.service.selectedFiles.length > 0
                            && root.service.devices.some(device => device.id === root.service.selectedPeer)
                        onClicked: root.service.send()
                    }
                    BodyText {
                        text: "Compare the PIN on both devices before confirming."
                        color: root.dim; font.pixelSize: Commons.Style.font.bodySmall
                    }
                }
            }
            Bar.PopupSeparator { Layout.fillWidth: true; shell: root.shell }
            RowLayout {
                Layout.fillWidth: true
                SectionHeader { text: "TRANSFERS" }
                StatusBadge { caption: String(root.service.transfers.length) }
            }
            SectionCard {
                visible: !root.service.transfers.length
                EmptyState {
                    icon: "󰁯"; title: "No transfers yet"
                    description: "Progress and incoming requests will appear here."
                }
            }
            Repeater {
                model: root.service.transferModel
                SectionCard {
                    id: transfer
                    required property string transferId
                    required property var transferData
                    borderSpec: Commons.Border.flat(transferId === root.service.highlightedTransfer ? root.shell.selectedEdge()
                        : root.shell.alpha(root.borderColor, root.borderOpacity), root.shell.borderWidth)
                    RowLayout {
                        Layout.fillWidth: true
                        BodyText {
                            Layout.fillWidth: false; font.pixelSize: Commons.Style.font.heading; Accessible.ignored: true
                            text: transfer.transferData.state === "completed" ? "󰄬" : transfer.transferData.direction === "inbound" ? "󰇚" : "󰇘"
                            color: transfer.transferData.state === "failed" ? root.urgent : root.accent
                        }
                        BodyText {
                            text: (transfer.transferData.direction === "inbound" ? "From: " : "To: ")
                                + transfer.transferData.device_name
                            font.bold: true
                        }
                    }
                    Flow {
                        Layout.fillWidth: true; spacing: Commons.Style.space(6)
                        StatusBadge {
                            caption: root.service.stateLabel(transfer.transferData.state)
                            emphasized: transfer.transferData.state === "waiting_acceptance" || transfer.transferData.state === "completed"
                        }
                        StatusBadge { caption: root.service.medium(transfer.transferData.transport) }
                    }
                    Rectangle {
                        Layout.fillWidth: true; implicitHeight: pinColumn.implicitHeight + pinColumn.anchors.topMargin * 2
                        visible: !!transfer.transferData.pin_code && !root.service.terminal(transfer.transferData.state)
                        color: root.shell.selectedFill(); radius: root.shell.rounding
                        ColumnLayout {
                            id: pinColumn
                            anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                            anchors.margins: Commons.Style.space(8); spacing: Commons.Style.space(4)
                            SectionHeader { text: "VERIFY PIN" }
                            BodyText {
                                text: transfer.transferData.pin_code || ""; font.pixelSize: Commons.Style.font.title; color: root.accent
                                font.letterSpacing: Commons.Style.space(3); font.bold: true; Accessible.name: "PIN: " + text
                            }
                            BodyText {
                                text: "Check that this PIN matches the one on Android. If it does not match, reject the request."
                                font.pixelSize: Commons.Style.font.bodySmall
                            }
                        }
                    }
                    Repeater {
                        model: transfer.transferData.files
                        BodyText {
                            required property string modelData
                            text: modelData; font.pixelSize: Commons.Style.font.bodySmall; wrapMode: Text.WrapAnywhere
                        }
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        visible: transfer.transferData.state === "transferring" || transfer.transferData.state === "completed"
                            || Number(transfer.transferData.transferred_bytes) > 0
                        from: 0; to: Math.max(1, Number(transfer.transferData.total_bytes)); value: Number(transfer.transferData.transferred_bytes)
                        background: Rectangle { implicitHeight: Commons.Style.space(6); color: root.shell.hoverFill(); radius: root.shell.rounding }
                        contentItem: Item {
                            implicitHeight: Commons.Style.space(6)
                            Rectangle {
                                width: parent.width
                                    * Math.min(1, Number(transfer.transferData.transferred_bytes) / Math.max(1, Number(transfer.transferData.total_bytes)))
                                height: parent.height; radius: root.shell.rounding; color: root.accent
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        BodyText {
                            text: Units.bytesText(transfer.transferData.transferred_bytes) + " / " + Units.bytesText(transfer.transferData.total_bytes)
                            color: root.dim; font.pixelSize: Commons.Style.font.caption
                        }
                        BodyText {
                            Layout.fillWidth: false; color: root.accent; font.pixelSize: Commons.Style.font.caption
                            visible: Number(transfer.transferData.total_bytes) > 0
                                && (transfer.transferData.state === "transferring" || transfer.transferData.state === "completed")
                            text: Math.min(100, Math.floor(Number(transfer.transferData.transferred_bytes) * 100
                                / Math.max(1, Number(transfer.transferData.total_bytes)))) + "%"
                        }
                    }
                    BodyText { visible: !!transfer.transferData.error; text: transfer.transferData.error || ""; color: root.urgent }
                    ColumnLayout {
                        visible: !root.service.terminal(transfer.transferData.state); Layout.fillWidth: true; spacing: Commons.Style.spacing.controlGap
                        ActionButton {
                            Layout.fillWidth: true; active: enabled; visible: transfer.transferData.state === "waiting_acceptance"
                            text: transfer.transferData.direction === "outbound" ? "Confirm matching PIN"
                                : "PIN matches · accept"
                            enabled: root.enabledActions && !!transfer.transferData.pin_code; onClicked: root.service.run(["accept", transfer.transferId])
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: Commons.Style.spacing.controlGap
                            ActionButton {
                                Layout.fillWidth: true; text: "Reject"
                                visible: transfer.transferData.state === "waiting_acceptance"
                                enabled: root.enabledActions; onClicked: root.service.run(["reject", transfer.transferId])
                            }
                            ActionButton {
                                Layout.fillWidth: true; text: "Cancel"
                                enabled: root.enabledActions; onClicked: root.service.run(["cancel", transfer.transferId])
                            }
                        }
                    }
                }
            }
            Bar.PopupSeparator { Layout.fillWidth: true; shell: root.shell }
            ActionButton {
                Layout.fillWidth: true; bordered: false; leftAlign: true; iconText: "󰒓"; text: "Settings"
                fontSize: Commons.Style.font.subtitle; onClicked: root.settingsOpen = !root.settingsOpen
            }
            ColumnLayout {
                visible: root.settingsOpen; Layout.fillWidth: true; spacing: Commons.Style.space(10)
                SectionCard {
                    SectionHeader { text: "TRANSFER EFFECTS" }
                    Bar.PopupToggleRow {
                        Layout.fillWidth: true; shell: root.shell
                        title: "Animated transfer companion"
                        detail: "Optional click-through effects · off by default"
                        checked: root.service.effectsEnabled; onToggled: root.service.setEffects(!checked)
                    }
                    BodyText {
                        text: root.service.activeTransfers
                            ? "Live transfers take priority; preview is paused."
                            : "UI preview only · 8 seconds · no files sent, PIN or network actions."
                        color: root.dim; font.pixelSize: Commons.Style.font.bodySmall
                    }
                    ActionButton {
                        Layout.fillWidth: true; text: "Preview · " + root.service.previewSeconds + " s"
                        enabled: root.service.effectsEnabled && !root.service.activeTransfers; onClicked: root.service.previewEffects()
                    }
                }
                Bar.PopupToggleRow {
                    Layout.fillWidth: true; shell: root.shell
                    title: "Allow interrupting my Wi-Fi"
                    detail: "Allow direct transfers to change the connection"
                    checked: root.service.snapshot.network_consent === true; enabled: root.enabledActions
                    onToggled: root.service.run(["network-consent", checked ? "off" : "on"])
                }
                SectionHeader { text: "DOWNLOAD FOLDER" }
                BodyText {
                    text: root.service.snapshot.download_directory || "No data"
                    color: root.dim; font.pixelSize: Commons.Style.font.bodySmall; wrapMode: Text.WrapAnywhere
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: Commons.Style.spacing.controlGap
                    Bar.PopupField {
                        id: directory; Layout.fillWidth: true; shell: root.shell; font.pixelSize: Commons.Style.font.body
                        placeholderText: "/absolute/path/to/downloads"
                        Accessible.name: "Download folder"
                        enabled: root.enabledActions && !root.service.activeTransfers; onAccepted: if (enabled && text) root.service.directory(text)
                    }
                    ActionButton {
                        text: "Save"; onClicked: root.service.directory(directory.text)
                        enabled: root.enabledActions && !root.service.activeTransfers && directory.text.length > 0
                    }
                }
            }
        }
    }
}
