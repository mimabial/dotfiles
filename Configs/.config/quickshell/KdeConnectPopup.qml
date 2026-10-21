pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.monitor.Ui as Ui
import qs.Commons as Commons
import "StartMenuModel.js" as StartMenuModel

PopupCard {
    id: root
    readonly property var service: shell.kdeconnect
    readonly property int deviceCount: service.reachableDevices.count
    readonly property int fileCount: service.selectedFiles.length
    readonly property color foreground: shell.foreground
    readonly property color accent: shell.accent
    readonly property color dim: shell.mutedText
    readonly property string fontFamily: shell.fontFamily
    readonly property var restingEdge: Commons.Border.flat(shell.alpha(borderColor, borderOpacity), shell.borderWidth)
    property bool sendExpanded: true
    popupName: "kdeconnect"
    contentHeight: column.implicitHeight + padding * 2

    component BodyText: Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.body
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
        borderSpec: Commons.Border.flat(activeFocus || hasCursor ? root.shell.hoverEdge()
            : selected || active ? root.shell.selectedEdge()
            : bordered ? root.shell.alpha(root.foreground, root.borderOpacity) : "transparent", root.shell.borderWidth)
        focusable: true; bordered: true
        opacity: enabled ? 1 : Style.mutedTextAlpha
        Accessible.role: Accessible.Button
        Accessible.name: text || hint
        BarTooltip { shell: root.shell; anchorItem: action; text: action.hint; hovered: action.hot }
        PopupPointer { shell: root.shell; row: action }
    }
    component EmptyState: RowLayout {
        id: empty
        property string icon: ""
        property string title: ""
        property string description: ""
        Layout.fillWidth: true; spacing: Style.xxxl
        BodyText { Layout.fillWidth: false; text: empty.icon; color: root.accent; font.pixelSize: Style.heroIcon; Accessible.ignored: true }
        ColumnLayout {
            Layout.fillWidth: true; spacing: Style.sm
            BodyText { text: empty.title; font.bold: true }
            BodyText { text: empty.description; color: root.dim; font.pixelSize: Style.bodySmall }
        }
    }

    ColumnLayout {
        id: column
        width: parent.width; spacing: Style.sectionGap
        RowLayout {
            Layout.fillWidth: true; spacing: Style.sectionGap
            Rectangle {
                Layout.preferredWidth: tileGlyph.implicitWidth + Style.popupPadding * 2; Layout.preferredHeight: width
                radius: root.shell.rounding; color: root.shell.selectedFill()
                Text {
                    id: tileGlyph
                    anchors.centerIn: parent; text: "󰒗"; color: root.accent
                    font.family: root.fontFamily; font.pixelSize: Style.heroIcon; Accessible.ignored: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: Style.xs
                BodyText { text: "KDE Connect"; font.bold: true }
                BodyText {
                    text: "Phone file sharing"; color: root.dim; font.pixelSize: Style.caption
                    font.capitalization: Font.AllUppercase; font.letterSpacing: Style.xxs
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true; spacing: Style.controlGap
            ActionButton {
                Layout.fillWidth: true; Layout.minimumWidth: 0
                iconText: "󰒓"; text: "Devices and pairing"; hint: "Open KDE Connect"
                onClicked: root.service.openDevices()
            }
            ActionButton { iconText: "󰑐"; hint: "Look for devices again"; onClicked: root.service.refresh() }
        }
        Ui.BorderSurface {
            Layout.fillWidth: true
            implicitHeight: sendColumn.implicitHeight + sendColumn.anchors.margins * 2
            color: "transparent"; borderSpec: root.restingEdge; radius: root.shell.rounding
            ColumnLayout {
                id: sendColumn
                anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
                anchors.margins: Style.xxxl; spacing: Style.xl
                ActionButton {
                    Layout.fillWidth: true; bordered: false; leftAlign: true
                    iconText: root.sendExpanded ? "󰅀" : "󰅂"
                    text: "Send files" + (root.fileCount ? " · " + root.fileCount : "")
                    onClicked: root.sendExpanded = !root.sendExpanded
                }
                ColumnLayout {
                    visible: root.sendExpanded; Layout.fillWidth: true; spacing: Style.xl
                    Ui.PanelSectionHeader {
                        Layout.fillWidth: true; text: "CONNECTED DEVICES"
                        foreground: root.foreground; color: root.dim; fontFamily: root.fontFamily
                    }
                    EmptyState {
                        visible: !root.deviceCount; icon: "󰄜"; title: "Find your phone"
                        description: "Open KDE Connect on your phone and join the same Wi-Fi."
                    }
                    Repeater {
                        model: root.service.reachableDevices
                        ActionButton {
                            required property string name
                            required property string deviceId
                            Layout.fillWidth: true; leftAlign: true
                            selected: root.service.recipient === deviceId
                            iconText: selected ? "󰄬" : "󰄜"; text: name
                            onClicked: root.service.selectedDevice = deviceId
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true; spacing: Style.controlGap
                        ActionButton {
                            Layout.fillWidth: true; iconText: "󰉋"; text: "Choose files…"
                            onClicked: root.service.pickFiles()
                        }
                        ActionButton {
                            iconText: "󰅚"; text: "Clear"; enabled: root.fileCount > 0
                            onClicked: root.service.selectedFiles = []
                        }
                    }
                    EmptyState {
                        visible: !root.fileCount; icon: "󰈙"; title: "Your next transfer"
                        description: "Choose one or more files, or send them from Dolphin's right-click menu."
                    }
                    Repeater {
                        model: root.service.selectedFiles
                        ColumnLayout {
                            id: selectedFile
                            required property string modelData
                            readonly property string path: StartMenuModel.filePath(modelData)
                            Layout.fillWidth: true; spacing: Style.xxs
                            BodyText { text: selectedFile.path.slice(selectedFile.path.lastIndexOf("/") + 1); font.bold: true }
                            BodyText { text: selectedFile.path; color: root.dim; font.pixelSize: Style.caption; wrapMode: Text.WrapAnywhere }
                        }
                    }
                    ActionButton {
                        Layout.fillWidth: true; iconText: "󰒗"; active: enabled
                        text: "Send" + (root.fileCount ? " · " + root.fileCount + (root.fileCount === 1 ? " file" : " files") : "")
                        enabled: root.fileCount > 0 && root.service.recipient !== ""
                        onClicked: root.service.send()
                    }
                }
            }
        }
    }
}
