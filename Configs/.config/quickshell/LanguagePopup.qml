pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "LanguageModel.js" as Model
import "Ui" as Ui

PopupCard {
    id: root
    popupName: "language"
    contentWidth: Style.px(390)
    contentHeight: panelColumn.implicitHeight + padding * 2

    property var report: ({})
    property var catalog: ({layouts: [], shortcuts: []})
    property string view: "main"
    property string query: ""
    property int optionIndex: 0
    property int pendingDeleteIndex: -1
    property bool busy: false
    property string statusText: ""
    property bool statusError: false

    readonly property var configured: Model.normalizeLayouts(report.configured)
    readonly property int activeIndex: Math.max(0, Math.min(Number(report.activeIndex || 0), configured.length - 1))
    readonly property var activeLayout: configured.length > 0 ? configured[activeIndex] : null
    readonly property string switchOption: String(report.switchOption || "")
    readonly property var pickerOptions: view === "add"
        ? Model.unusedLayoutOptions(catalog, configured)
        : view === "shortcut" ? Model.shortcutOptions(catalog) : []
    readonly property var filteredOptions: Model.filterOptions(pickerOptions, query)
    readonly property int pickerHeight: Math.min(Style.px(300), Math.max(Style.popupRowHeight, filteredOptions.length * (Style.px(45) + Style.xxs)))

    function acceptReport(text) {
        try {
            const parsed = JSON.parse(String(text || "").trim()) || ({})
            if (!Array.isArray(parsed.configured) || parsed.configured.length === 0) return false
            report = parsed
            return true
        } catch (error) {
            return false
        }
    }

    function refresh() {
        if (!reportProc.running && !actionProc.running) reportProc.running = true
    }

    function ensureCatalog() {
        if (catalog.layouts.length === 0 && !catalogProc.running) catalogProc.running = true
    }

    function showMain(message) {
        view = "main"
        query = ""
        optionIndex = 0
        cursorIndex = -1
        if (message !== undefined) {
            statusError = false
            statusText = message
        }
    }

    function showPicker(nextView) {
        view = nextView
        query = ""
        optionIndex = 0
        cursorIndex = -1
        statusError = false
        statusText = ""
        ensureCatalog()
        Qt.callLater(searchField.forceActiveFocus)
    }

    function runAction(args, successMessage) {
        if (busy || actionProc.running) return
        busy = true
        statusError = false
        statusText = "Applying keyboard settings…"
        actionProc.successMessage = successMessage
        actionProc.command = ["hyprshell", "util/keyboard-layout"].concat(args)
        actionProc.running = true
    }

    function chooseOption(index) {
        if (index < 0 || index >= filteredOptions.length) return
        const option = filteredOptions[index]
        if (view === "add")
            runAction(["--add", option.layout, option.variant], "Keyboard layout added.")
        else if (view === "shortcut")
            runAction(["--shortcut", option.value || "none"], "Switching shortcut updated.")
    }

    function requestDelete(index) {
        if (configured.length <= 1) {
            statusError = true
            statusText = "Keep at least one keyboard layout."
            return
        }
        pendingDeleteIndex = index
        deleteDialog.selectedIndex = 0
        deleteDialog.opened = true
    }

    function handleKey(event) {
        if (deleteDialog.opened) return deleteDialog.handleKey(event)
        if (view === "main") return defaultKey(event)
        if (event.key === Qt.Key_Escape) { showMain(); return true }
        if (event.key === Qt.Key_Down) {
            optionIndex = Math.min(filteredOptions.length - 1, optionIndex + 1)
            pickerList.positionViewAtIndex(optionIndex, ListView.Contain)
            return true
        }
        if (event.key === Qt.Key_Up) {
            optionIndex = Math.max(0, optionIndex - 1)
            pickerList.positionViewAtIndex(optionIndex, ListView.Contain)
            return true
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            chooseOption(optionIndex)
            return true
        }
        if (event.key === Qt.Key_Backspace) {
            query = query.slice(0, -1)
            return true
        }
        if (event.text && event.text.length === 1 && event.text >= " "
                && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
            query += event.text
            return true
        }
        return true
    }

    onFilteredOptionsChanged: optionIndex = Math.max(0, Math.min(optionIndex, filteredOptions.length - 1))
    onOpenChanged: {
        if (!open) {
            view = "main"
            query = ""
            statusText = ""
            deleteDialog.opened = false
            return
        }
        showMain()
        refresh()
        ensureCatalog()
    }

    property Process reportProc: Process {
        command: ["hyprshell", "util/keyboard-layout"]
        stdout: StdioCollector {
            id: reportStdout
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: reportStderr
            waitForEnd: true
        }
        onExited: code => {
            if (code === 0 && root.acceptReport(reportStdout.text)) return
            if (!root.open) return
            root.statusError = true
            root.statusText = String(reportStderr.text || "Keyboard settings could not be read.").trim()
        }
    }

    property Process catalogProc: Process {
        command: ["hyprshell", "util/keyboard-layout", "--available"]
        stdout: StdioCollector {
            id: catalogStdout
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: catalogStderr
            waitForEnd: true
        }
        onExited: code => {
            if (code === 0) {
                root.catalog = Model.parseCatalog(catalogStdout.text)
                return
            }
            if (!root.open) return
            root.statusError = true
            root.statusText = String(catalogStderr.text || "The installed XKB catalog could not be read.").trim()
        }
    }

    property Process actionProc: Process {
        property string successMessage: ""
        stdout: StdioCollector {
            id: actionStdout
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: actionStderr
            waitForEnd: true
        }
        onExited: code => {
            root.busy = false
            if (code === 0 && root.acceptReport(actionStdout.text)) {
                root.showMain(successMessage)
                if (root.anchorItem && root.anchorItem.refresh) root.anchorItem.refresh()
                return
            }
            root.statusError = true
            root.statusText = String(actionStderr.text || "Keyboard settings could not be applied.").trim()
        }
    }

    Column {
        id: panelColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.sm

        PopupHero {
            shell: root.shell
            title: root.view === "main" ? "Keyboard languages"
                : root.view === "add" ? "Add a layout" : "Switch shortcut"
            status: root.view === "main" && root.activeLayout
                ? Model.descriptionFor(root.catalog, root.activeLayout.layout, root.activeLayout.variant)
                : root.view === "add" ? "Installed XKB layouts and variants" : "Supported XKB group options"
        }

        PopupSeparator { shell: root.shell }

        Column {
            visible: root.view === "main"
            width: parent.width
            spacing: Style.sm

            PopupSection {
                shell: root.shell
                text: "LAYOUTS"
                value: root.configured.length
            }

            Flickable {
                id: configuredScroll
                width: parent.width
                height: Math.min(configuredColumn.implicitHeight, Style.popupRowHeight * 4 + Style.rowGap * 3)
                contentWidth: width
                contentHeight: configuredColumn.implicitHeight
                interactive: contentHeight > height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: configuredScroll.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

                Column {
                    id: configuredColumn
                    width: configuredScroll.width
                    spacing: Style.xxs

                    Repeater {
                        model: root.configured

                        Item {
                            id: configuredItem
                            required property var modelData
                            required property int index
                            width: configuredColumn.width
                            implicitHeight: layoutRow.implicitHeight

                            PopupRow {
                                id: layoutRow
                                anchors.left: parent.left
                                anchors.right: parent.right
                                shell: root.shell
                                title: Model.descriptionFor(root.catalog, configuredItem.modelData.layout, configuredItem.modelData.variant)
                                detail: configuredItem.modelData.layout.toUpperCase() + (configuredItem.modelData.variant ? " · " + configuredItem.modelData.variant : " · default")
                                value: Model.labelFor(root.catalog, configuredItem.modelData.layout, configuredItem.modelData.variant)
                                active: configuredItem.index === root.activeIndex
                                rightInset: removeButton.width + Style.sm
                                onClicked: if (configuredItem.index !== root.activeIndex) root.runAction(["--use", String(configuredItem.index)], "Keyboard layout switched.")
                            }

                            Ui.PanelActionButton {
                                id: removeButton
                                anchors.right: parent.right
                                anchors.rightMargin: Style.controlPaddingX
                                anchors.verticalCenter: parent.verticalCenter
                                iconText: "󰅖"
                                enabled: !root.busy && root.configured.length > 1
                                foreground: root.shell.foreground
                                hoverColor: root.shell.role("error", root.shell.foreground)
                                fontFamily: root.shell.fontFamily
                                onClicked: root.requestDelete(configuredItem.index)
                            }
                        }
                    }
                }
            }

            PopupSeparator { shell: root.shell }

            PopupRow {
                width: parent.width
                shell: root.shell
                icon: "󰐕"
                title: "Add layout or variant"
                detail: root.catalog.layouts.length > 0 ? "Search installed XKB definitions" : "Loading XKB catalog…"
                onClicked: root.showPicker("add")
            }

            PopupRow {
                width: parent.width
                shell: root.shell
                icon: "󰁔"
                title: "Switch shortcut"
                detail: Model.shortcutLabel(root.catalog, root.switchOption)
                onClicked: root.showPicker("shortcut")
            }
        }

        Column {
            visible: root.view !== "main"
            width: parent.width
            spacing: Style.sm

            Rectangle {
                width: parent.width
                height: Style.px(34)
                radius: root.shell.rounding
                color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .25)
                border.width: 1
                border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), searchField.activeFocus ? .55 : .3)

                Text {
                    id: searchGlyph
                    anchors.left: parent.left
                    anchors.leftMargin: Style.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    color: root.shell.alpha(root.shell.foreground, .55)
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.bodySmall
                }

                TextField {
                    id: searchField
                    anchors.left: searchGlyph.right
                    anchors.leftMargin: Style.xs
                    anchors.right: resultCount.left
                    anchors.rightMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    height: Style.px(24)
                    text: root.query
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    placeholderText: root.view === "add" ? "Search layouts and variants…" : "Search shortcuts…"
                    color: root.shell.foreground
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.bodySmall
                    background: null
                    onTextChanged: if (root.query !== text) root.query = text
                    Keys.onDownPressed: event => event.accepted = root.handleKey(event)
                    Keys.onUpPressed: event => event.accepted = root.handleKey(event)
                    Keys.onReturnPressed: event => event.accepted = root.handleKey(event)
                    Keys.onEnterPressed: event => event.accepted = root.handleKey(event)
                    Keys.onEscapePressed: event => event.accepted = root.handleKey(event)
                }

                Text {
                    id: resultCount
                    anchors.right: parent.right
                    anchors.rightMargin: Style.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.filteredOptions.length
                    color: root.shell.alpha(root.shell.foreground, .45)
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.caption
                }
            }

            Text {
                visible: root.filteredOptions.length === 0
                width: parent.width
                text: root.catalog.layouts.length === 0 ? "Loading XKB catalog…" : "No matching options"
                color: root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily
                font.pixelSize: Style.bodySmall
            }

            ListView {
                id: pickerList
                width: parent.width
                height: root.pickerHeight
                spacing: Style.xxs
                clip: true
                model: root.filteredOptions
                currentIndex: root.optionIndex
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: pickerList.contentHeight > pickerList.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

                delegate: PopupRow {
                    id: pickerRow
                    required property var modelData
                    required property int index
                    width: pickerList.width
                    shell: root.shell
                    title: pickerRow.modelData.label
                    detail: pickerRow.modelData.description
                    active: root.view === "shortcut" && String(pickerRow.modelData.value || "") === root.switchOption
                    cursored: pickerRow.index === root.optionIndex
                    onClicked: root.chooseOption(pickerRow.index)
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: root.optionIndex = pickerRow.index
                        onClicked: root.chooseOption(pickerRow.index)
                    }
                }
            }

            PopupRow {
                width: parent.width
                shell: root.shell
                icon: "󰁍"
                title: "Back"
                detail: "Keep the current keyboard settings"
                onClicked: root.showMain()
            }
        }

        Text {
            visible: root.statusText !== ""
            width: parent.width
            text: root.statusText
            color: root.statusError ? root.shell.role("error", root.shell.foreground)
                : root.shell.alpha(root.shell.foreground, .6)
            font.family: root.shell.fontFamily
            font.pixelSize: Style.caption
            wrapMode: Text.WordWrap
        }
    }

    Ui.ConfirmDialog {
        id: deleteDialog
        anchors.fill: parent
        z: 10
        message: root.pendingDeleteIndex >= 0 && root.pendingDeleteIndex < root.configured.length
            ? "Remove " + Model.descriptionFor(root.catalog,
                root.configured[root.pendingDeleteIndex].layout,
                root.configured[root.pendingDeleteIndex].variant) + "?"
            : "Remove this keyboard layout?"
        cancelText: "Keep"
        confirmText: "Remove"
        background: root.background
        foreground: root.shell.foreground
        fontFamily: root.shell.fontFamily
        onCanceled: {
            opened = false
            root.pendingDeleteIndex = -1
        }
        onConfirmed: {
            const index = root.pendingDeleteIndex
            opened = false
            root.pendingDeleteIndex = -1
            root.runAction(["--remove", String(index)], "Keyboard layout removed.")
        }
    }
}
