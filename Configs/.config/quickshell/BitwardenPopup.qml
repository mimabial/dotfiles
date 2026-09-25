pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "BitwardenModel.js" as Model

PopupCard {
    id: root
    popupName: "bitwarden"
    contentWidth: Style.px(430)
    wantsKeyboard: true

    readonly property var vault: shell.bitwarden
    readonly property var settings: vault.settings
    readonly property color dim: shell.alpha(shell.foreground, .55)
    // "list" | "item" | "form" | "generator" | "send" | "settings" while unlocked
    property string view: "list"
    readonly property string page: vault.status === "unlocked" ? view : vault.status || "checking"
    property var current: null
    property var draft: null
    property bool confirming: false
    property string query: ""
    property int typeFilter: 0
    property int selected: 0
    property var revealed: ({})
    property string totpCode: ""
    property int totpLeft: 0
    property string windowTitle: ""
    property string windowClass: ""
    property var generator: ({ passphrase: false, length: 20, upper: true, lower: true, number: true, special: false, words: 4, separator: "-", capitalize: true })
    property string generated: ""
    property bool generatorForForm: false
    readonly property point capturePosition: {
        if (!anchorItem || !anchorWindow || !anchorWindow.screen) return Qt.point(0, 0)
        const screen = anchorWindow.screen, anchors = anchorWindow.anchors
        const originX = anchors.left ? 0 : anchors.right ? screen.width - anchorWindow.width : (screen.width - anchorWindow.width) / 2
        const originY = anchors.top ? 0 : anchors.bottom ? screen.height - anchorWindow.height : (screen.height - anchorWindow.height) / 2
        if (centered) return Qt.point((screen.width - width) / 2, (screen.height - height) / 2)
        let x = anchorItem.width / 2 - width / 2, y = anchorItem.height + margin
        if (position === "bottom") y = -height - margin
        else if (position === "left") { x = anchorItem.width + margin; y = anchorItem.height / 2 - height / 2 }
        const point = anchorWindow.contentItem.mapFromItem(anchorItem, x, y)
        return Qt.point(Math.max(0, Math.min(screen.width - width, originX + point.x)),
            Math.max(0, Math.min(screen.height - height, originY + point.y)))
    }

    readonly property var suggested: settings.suggest && query === "" && !typeFilter
        ? Model.suggestions(vault.items, windowTitle, windowClass) : []
    readonly property var rows: suggested.concat(Model.filter(vault.items, query, typeFilter, vault.folderNames)
        .filter(item => !suggested.includes(item)))
    readonly property var pages: ({ checking: checkingPage, missing: missingPage, unauthenticated: loginPage, locked: unlockPage,
        list: listPage, item: itemPage, form: formPage, generator: generatorPage, send: sendPage, settings: settingsPage })
    readonly property var backAction: ({ glyph: "\u{f004d}", hint: "Back", run: () => root.back() })
    readonly property var actions: page === "list" ? [
            { glyph: "\u{f0415}", hint: "New item", run: () => root.edit(Model.blank(Model.LOGIN_TYPE)) },
            { glyph: "\u{f076e}", hint: "Generator", run: () => root.openGenerator(false) },
            { glyph: "\u{f048a}", hint: "Send", run: () => root.go("send") },
            { glyph: "\u{f0450}", hint: "Sync", run: () => root.vault.sync() },
            { glyph: "\u{f0493}", hint: "Settings", run: () => root.go("settings") },
            { glyph: "\u{f033e}", hint: "Lock", run: () => root.vault.lock() }]
        : page === "item" ? [backAction].concat(Model.editable(current) ? [
            { glyph: "\u{f03eb}", hint: "Edit", run: () => root.edit(JSON.parse(JSON.stringify(root.current))) },
            { glyph: "\u{f01b4}", hint: confirming ? "Click again to delete" : "Delete", alert: confirming,
              run: () => { if (root.confirming) root.remove(); else root.confirming = true } }] : [])
        : vault.status === "unlocked" ? [backAction] : []

    function go(next) { vault.error = ""; vault.notice = ""; confirming = false; view = next }
    function back() {
        if (page === "form") go(draft.id ? "item" : "list")
        else if (page === "generator" && generatorForForm) go("form")
        else if (page !== "list" && vault.status === "unlocked") go("list")
        else shell.closePopup()
    }
    function show(item) { current = item; revealed = ({}); totpCode = ""; totpLeft = 0; go("item") }
    function edit(item) { draft = item; go("form") }
    function remove() { vault.remove(current); go("list") }
    function activate(item) {
        if (!Model.read(item, "login.password")) return show(item)
        vault.copyPassword(item)
        if (settings.closeOnCopy) shell.closePopup()
    }
    function saveDraft() {
        if (!String(draft.name || "").trim()) { vault.error = "Name is required"; return }
        vault.save(draft, saved => root.show(saved))
    }
    function setFields(fields) { draft = Object.assign({}, draft, { fields: fields }) }
    function openGenerator(forForm) { generatorForForm = forForm; go("generator") }
    function setOption(key, value) { generator = Object.assign({}, generator, { [key]: value }); regenerate() }
    function regenerate() { vault.generate(generator, value => root.generated = value) }
    function listKey(event) {
        const row = rows[selected]
        switch (event.key) {
        case Qt.Key_Down: selected = Math.min(rows.length - 1, selected + 1); return true
        case Qt.Key_Up: selected = Math.max(0, selected - 1); return true
        case Qt.Key_Tab: case Qt.Key_Backtab: typeFilter = (typeFilter + (event.key === Qt.Key_Tab ? 1 : 5)) % 6; return true
        case Qt.Key_Return: case Qt.Key_Enter:
            if (row) { if (event.modifiers & Qt.ShiftModifier) show(row); else activate(row) }
            return true
        }
        return false
    }
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) { back(); return true }
        return page === "list" && listKey(event)
    }

    onQueryChanged: selected = 0
    onTypeFilterChanged: selected = 0
    onOpenChanged: {
        if (!open) { vault.release(); return }
        const window = Hyprland.activeToplevel
        windowTitle = window ? String(window.title || "") : ""
        windowClass = window && window.lastIpcObject ? String(window.lastIpcObject.class || "") : ""
        go("list")
        query = ""; typeFilter = 0; current = null; draft = null
        vault.prepare()
    }

    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root.open && root.page === "item" && Model.read(root.current, "login.totp") !== ""
        onTriggered: {
            const period = Model.totpPeriod(Model.read(root.current, "login.totp"))
            const left = period - Math.floor(Date.now() / 1000) % period
            if (left > root.totpLeft) root.vault.totp(root.current, code => root.totpCode = code)
            root.totpLeft = left
        }
    }

    PanelWindow {
        screen: root.anchorWindow ? root.anchorWindow.screen : null
        visible: root.visible
        implicitWidth: root.width; implicitHeight: root.cardHeight
        color: "transparent"; exclusionMode: ExclusionMode.Ignore
        mask: Region {}
        WlrLayershell.namespace: "hypr-shell-bitwarden"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.anchors.top: true
        WlrLayershell.anchors.left: true
        WlrLayershell.margins.left: Math.round(root.capturePosition.x)
        WlrLayershell.margins.top: Math.round(root.capturePosition.y + root.cardY)
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    }

    component HeaderAction: Rectangle {
        id: headerAction
        required property var action
        width: Style.px(26); height: Style.px(26); radius: root.shell.rounding
        color: actionArea.containsMouse ? root.shell.hoverFill(3) : "transparent"
        Text {
            anchors.centerIn: parent; text: headerAction.action.glyph
            color: headerAction.action.alert ? root.shell.urgent : root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Style.title
        }
        MouseArea { id: actionArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: headerAction.action.run() }
        BarTooltip { shell: root.shell; anchorItem: headerAction; text: headerAction.action.hint; hovered: actionArea.containsMouse }
    }
    component Tab: Rectangle {
        id: tab
        required property string label
        required property bool selected
        signal picked
        implicitWidth: tabText.implicitWidth + Style.controlPaddingX * 2; implicitHeight: Style.px(24)
        radius: root.shell.rounding
        color: selected ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .25) : tabArea.containsMouse ? root.shell.hoverFill() : "transparent"
        Text {
            id: tabText; anchors.centerIn: parent; text: tab.label.toUpperCase()
            color: tab.selected ? root.shell.foreground : root.dim
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: tab.selected; font.letterSpacing: 1
        }
        MouseArea { id: tabArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tab.picked() }
    }
    component Note: Text {
        width: parent ? parent.width : 0; wrapMode: Text.Wrap; color: root.dim
        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
    }
    component Setting: Item {
        id: setting
        required property string label
        default property alias control: slot.data
        width: parent ? parent.width : 0; implicitHeight: Math.max(Style.popupRowHeight, slot.childrenRect.height)
        Text {
            anchors.left: parent.left; anchors.right: slot.left; anchors.verticalCenter: parent.verticalCenter
            text: setting.label; elide: Text.ElideRight; color: root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        Item { id: slot; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: childrenRect.width; height: childrenRect.height }
    }
    component Count: PopupField {
        id: count
        required property int amount
        signal committed(int amount)
        shell: root.shell; width: Style.px(64); horizontalAlignment: TextInput.AlignHCenter
        validator: IntValidator { bottom: 0; top: 9999 }
        text: String(amount)
        onEditingFinished: count.committed(Number(count.text) || 0)
    }
    component Toggle: ToggleSwitch { shell: root.shell }
    component Secret: PopupField { shell: root.shell; width: parent ? parent.width : 0; echoMode: TextInput.Password }
    component Box: Rectangle {
        id: box
        property alias text: area.text
        property alias placeholder: area.placeholderText
        signal edited(string text)
        width: parent ? parent.width : 0; implicitHeight: Math.max(Style.px(56), area.implicitHeight)
        radius: root.shell.rounding; color: root.shell.alpha(root.shell.foreground, .06)
        border.width: 1; border.color: root.shell.alpha(root.shell.foreground, area.activeFocus ? .45 : .18)
        TextArea {
            id: area
            anchors.fill: parent; wrapMode: TextArea.Wrap; background: null
            leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
            color: root.shell.foreground; placeholderTextColor: root.shell.alpha(root.shell.foreground, .28)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            onTextChanged: if (activeFocus) box.edited(text)
        }
    }
    component Scroll: Flickable {
        default property alias body: scrollColumn.data
        implicitHeight: scrollColumn.implicitHeight; contentHeight: scrollColumn.implicitHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: PopupScrollBar { shell: root.shell }
        Column { id: scrollColumn; width: parent.width - Style.md; spacing: Style.sm }
    }
    component Field: Rectangle {
        id: field
        required property var entry
        readonly property bool masked: entry.secret && !root.revealed[entry.label]
        readonly property string value: entry.totp ? root.totpCode : entry.value
        width: parent ? parent.width : 0
        implicitHeight: valueText.y + valueText.implicitHeight + Style.controlPaddingY
        radius: root.shell.rounding
        color: fieldArea.containsMouse ? root.shell.hoverFill() : "transparent"
        MouseArea { id: fieldArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.vault.copy(field.value, field.entry.label) }
        Text {
            id: labelText; x: Style.controlPaddingX; y: Style.controlPaddingY
            text: (field.entry.totp ? "TOTP · " + root.totpLeft + "s" : field.entry.label).toUpperCase()
            color: root.dim; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
        }
        Text {
            id: valueText
            anchors.left: labelText.left; anchors.right: eye.left; anchors.top: labelText.bottom; anchors.topMargin: 2
            text: field.masked ? "••••••••••••" : field.value || "…"
            wrapMode: field.entry.multiline && !field.masked ? Text.WrapAnywhere : Text.NoWrap; elide: Text.ElideRight
            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        Text {
            id: eye
            anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
            width: field.entry.secret ? implicitWidth : 0; visible: field.entry.secret
            text: field.masked ? "\u{f0208}" : "\u{f0209}"; color: root.dim
            font.family: root.shell.fontFamily; font.pixelSize: Style.title
            MouseArea {
                anchors.fill: parent; anchors.margins: -Style.xs; cursorShape: Qt.PointingHandCursor
                onClicked: root.revealed = Object.assign({}, root.revealed, { [field.entry.label]: field.masked })
            }
        }
    }

    Column {
        width: parent.width; spacing: Style.sm

        Item {
            width: parent.width; implicitHeight: Math.max(hero.implicitHeight, headerActions.implicitHeight)
            PopupHero {
                id: hero
                anchors.left: parent.left; anchors.right: headerActions.left; anchors.rightMargin: Style.xs
                shell: root.shell
                title: root.page === "item" && root.current ? root.current.name
                    : root.page === "form" ? (root.draft && root.draft.id ? "Edit item" : "New item") : "Bitwarden"
                status: root.vault.busy ? "working…"
                    : root.page === "item" && root.current ? [Model.type(root.current).label, root.vault.folderNames[root.current.folderId]].filter(Boolean).join(" · ")
                    : root.page === "list" ? [root.vault.email, root.vault.items.length + " items"].filter(Boolean).join(" · ")
                    : root.vault.status === "unlocked" ? root.page : root.page === "checking" ? "" : root.vault.status
            }
            Row {
                id: headerActions
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                Repeater { model: root.actions; delegate: HeaderAction { required property var modelData; action: modelData } }
            }
        }
        PopupSeparator { shell: root.shell }
        Loader {
            width: parent.width; height: Math.min(implicitHeight, Style.px(480))
            active: root.visible
            sourceComponent: root.pages[root.page]
        }
        Text {
            width: parent.width; visible: text !== ""; wrapMode: Text.Wrap
            text: root.vault.error || root.vault.notice
            color: root.vault.error ? root.shell.urgent : root.dim
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
    }

    Component { id: checkingPage; Note { text: "Checking vault…" } }
    Component {
        id: missingPage
        Column {
            spacing: Style.sm
            Note { text: "The Bitwarden CLI (bw) is not installed." }
            PopupRow { width: parent.width; shell: root.shell; icon: "\u{f01da}"; title: "Install bitwarden-cli"; detail: "Runs in a terminal"; onClicked: root.vault.install() }
        }
    }
    Component {
        id: loginPage
        Column {
            spacing: Style.sm
            Note { text: "Logging in runs bw in a terminal, so two-step login, SSO and new-device checks all work there." }
            PopupField { id: server; width: parent.width; shell: root.shell; placeholderText: "Server URL (blank for bitwarden.com)"; onAccepted: root.vault.authenticate("login", text) }
            PopupRow { width: parent.width; shell: root.shell; icon: "\u{f0342}"; title: "Log in"; onClicked: root.vault.authenticate("login", server.text) }
        }
    }
    Component {
        id: unlockPage
        Column {
            id: unlock
            readonly property string method: root.settings.quickUnlock
            spacing: Style.sm
            Component.onCompleted: (pin.visible ? pin : password).forceActiveFocus()
            Secret {
                id: pin
                visible: unlock.method === "pin"; placeholderText: "PIN"; inputMethodHints: Qt.ImhDigitsOnly
                onAccepted: if (!root.vault.busy) root.vault.unlock({ PIN: text }, true)
            }
            Secret {
                id: password
                placeholderText: pin.visible ? "Master password (arms the PIN above)" : "Master password"
                onAccepted: if (!root.vault.busy) root.vault.unlock({ BW_PASSWORD: text, PIN: pin.text }, false,
                    unlock.method === "pin" ? (pin.text ? "pin" : "") : unlock.method)
            }
            PopupRow {
                width: parent.width; shell: root.shell
                visible: ["fingerprint", "fido2"].includes(unlock.method)
                icon: unlock.method === "fido2" ? "\u{f129e}" : "\u{f0237}"
                title: root.vault.prompt || "Scan again"; onClicked: root.vault.scan()
            }
            PopupRow { width: parent.width; shell: root.shell; icon: "\u{f018d}"; title: "Unlock in a terminal"; detail: "For SSO and key-connector accounts"; onClicked: root.vault.authenticate("unlock", "") }
        }
    }
    Component {
        id: listPage
        Column {
            spacing: Style.sm
            Row {
                spacing: Style.xs
                Repeater {
                    model: ["All"].concat([1, 2, 3, 4, 5].map(type => Model.TYPES[type].label))
                    delegate: Tab { required property string modelData; required property int index; label: modelData; selected: root.typeFilter === index; onPicked: root.typeFilter = index }
                }
            }
            PopupField {
                width: parent.width; shell: root.shell
                placeholderText: "Search · Enter copies · Shift+Enter opens · Tab filters"
                text: root.query; onTextEdited: root.query = text
                Keys.onPressed: event => event.accepted = root.listKey(event)
                Component.onCompleted: forceActiveFocus()
            }
            Note { visible: root.rows.length === 0; text: root.vault.busy ? "Loading…" : root.vault.items.length ? "No match" : "Vault is empty" }
            ListView {
                width: parent.width; height: Style.px(380)
                clip: true; spacing: 2; model: root.rows; currentIndex: root.selected
                ScrollBar.vertical: PopupScrollBar { shell: root.shell }
                delegate: PopupRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width - Style.md; shell: root.shell
                    icon: Model.type(modelData).icon
                    title: modelData.name
                    detail: [Model.subtitle(modelData), root.vault.folderNames[modelData.folderId]].filter(Boolean).join(" · ")
                    value: modelData.favorite ? "\u{f04ce}" : ""
                    active: root.suggested.includes(modelData)
                    cursored: index === root.selected
                    onClicked: button => button === Qt.RightButton ? root.show(modelData) : root.activate(modelData)
                }
            }
        }
    }
    Component {
        id: itemPage
        Scroll {
            Repeater { model: root.current ? Model.details(root.current) : []; delegate: Field { required property var modelData; entry: modelData } }
            PopupSection { visible: attachments.count > 0; shell: root.shell; text: "ATTACHMENTS" }
            Repeater {
                id: attachments
                model: root.current ? root.current.attachments || [] : []
                delegate: PopupRow {
                    required property var modelData
                    width: parent.width; shell: root.shell; icon: "\u{f03e2}"
                    title: modelData.fileName; value: modelData.sizeName || ""
                    onClicked: root.vault.download(root.current, modelData)
                }
            }
        }
    }
    Component {
        id: formPage
        Scroll {
            Row {
                visible: !root.draft.id; spacing: Style.xs
                Repeater {
                    model: [1, 2, 3, 4]
                    delegate: Tab {
                        required property int modelData
                        label: Model.TYPES[modelData].label; selected: root.draft.type === modelData
                        onPicked: root.draft = Object.assign(Model.blank(modelData), { name: root.draft.name })
                    }
                }
            }
            Note { text: "NAME"; font.bold: true }
            PopupField {
                width: parent.width; shell: root.shell
                text: root.draft.name; onTextEdited: root.draft.name = text; onAccepted: root.saveDraft()
                Component.onCompleted: forceActiveFocus()
            }
            Repeater {
                model: Model.schema(root.draft.type)
                delegate: Column {
                    id: input
                    required property var modelData
                    readonly property bool generates: modelData.path === "login.password"
                    width: parent.width; spacing: 2
                    Note { text: input.modelData.label.toUpperCase(); font.bold: true }
                    Row {
                        width: parent.width; spacing: Style.xs
                        PopupField {
                            visible: !input.modelData.multiline; shell: root.shell
                            width: parent.width - (input.generates ? generate.width + parent.spacing : 0)
                            echoMode: input.modelData.secret ? TextInput.PasswordEchoOnEdit : TextInput.Normal
                            text: Model.read(root.draft, input.modelData.path)
                            onTextEdited: Model.write(root.draft, input.modelData.path, text)
                            onAccepted: root.saveDraft()
                        }
                        Box {
                            visible: input.modelData.multiline
                            text: Model.read(root.draft, input.modelData.path)
                            onEdited: text => Model.write(root.draft, input.modelData.path, text)
                        }
                        PopupRow { id: generate; visible: input.generates; width: Style.px(40); shell: root.shell; icon: "\u{f076e}"; onClicked: root.openGenerator(true) }
                    }
                }
            }
            PopupSelect {
                width: parent.width; shell: root.shell
                choices: [{ label: "No folder", id: null }].concat(root.vault.folders.map(folder => ({ label: folder.name, id: folder.id })))
                selectedIndex: Math.max(0, choices.findIndex(choice => choice.id === (root.draft.folderId || null)))
                onActivated: index => root.draft.folderId = choices[index].id
            }
            PopupSection { shell: root.shell; text: "CUSTOM FIELDS" }
            Repeater {
                model: root.draft.fields || []
                delegate: Row {
                    id: custom
                    required property var modelData
                    required property int index
                    readonly property var target: root.draft.fields[index]
                    readonly property bool hidden: modelData.type === Model.CUSTOM_FIELD_TYPE.hidden
                    width: parent.width; spacing: Style.xs
                    PopupField {
                        width: (parent.width - Style.px(80)) * .4; shell: root.shell; placeholderText: "Name"
                        text: custom.modelData.name || ""; onTextEdited: custom.target.name = text
                    }
                    PopupField {
                        width: (parent.width - Style.px(80)) * .6; shell: root.shell; placeholderText: "Value"
                        echoMode: custom.hidden ? TextInput.PasswordEchoOnEdit : TextInput.Normal
                        text: custom.modelData.value || ""; onTextEdited: custom.target.value = text
                    }
                    PopupRow {
                        width: Style.px(36); shell: root.shell; icon: custom.hidden ? "\u{f0209}" : "\u{f0208}"
                        onClicked: { custom.target.type = custom.hidden ? Model.CUSTOM_FIELD_TYPE.text : Model.CUSTOM_FIELD_TYPE.hidden; root.setFields(root.draft.fields.slice()) }
                    }
                    PopupRow {
                        width: Style.px(36); shell: root.shell; icon: "\u{f01b4}"
                        onClicked: root.setFields(root.draft.fields.filter((field, index) => index !== custom.index))
                    }
                }
            }
            PopupRow {
                width: parent.width; shell: root.shell; icon: "\u{f0415}"; title: "Add field"
                onClicked: root.setFields((root.draft.fields || []).concat([{ name: "", value: "", type: Model.CUSTOM_FIELD_TYPE.text, linkedId: null }]))
            }
            PopupRow { width: parent.width; shell: root.shell; icon: "\u{f012c}"; title: "Save"; detail: "Enter in any field"; onClicked: root.saveDraft() }
        }
    }
    Component {
        id: generatorPage
        Scroll {
            Component.onCompleted: root.regenerate()
            Row {
                spacing: Style.xs
                Tab { label: "Password"; selected: !root.generator.passphrase; onPicked: root.setOption("passphrase", false) }
                Tab { label: "Passphrase"; selected: root.generator.passphrase; onPicked: root.setOption("passphrase", true) }
            }
            Text {
                width: parent.width; wrapMode: Text.WrapAnywhere; horizontalAlignment: Text.AlignHCenter
                text: root.generated || "…"; color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.title
            }
            PopupRow { width: parent.width; shell: root.shell; icon: "\u{f0450}"; title: "Regenerate"; onClicked: root.regenerate() }
            PopupRow { width: parent.width; shell: root.shell; icon: "\u{f018f}"; title: "Copy"; onClicked: root.vault.copy(root.generated, "Password") }
            PopupRow {
                visible: root.generatorForForm; width: parent.width; shell: root.shell; icon: "\u{f012c}"; title: "Use in item"
                onClicked: { Model.write(root.draft, "login.password", root.generated); root.go("form") }
            }
            Setting { label: root.generator.passphrase ? "Words" : "Length"; Count {
                amount: root.generator.passphrase ? root.generator.words : root.generator.length
                onCommitted: amount => root.setOption(root.generator.passphrase ? "words" : "length", amount)
            } }
            Setting { visible: root.generator.passphrase; label: "Separator"; PopupField {
                width: Style.px(64); shell: root.shell; horizontalAlignment: TextInput.AlignHCenter
                text: root.generator.separator; onEditingFinished: root.setOption("separator", text)
            } }
            Setting { visible: root.generator.passphrase; label: "Capitalize"; Toggle { checked: root.generator.capitalize; onToggled: root.setOption("capitalize", !checked) } }
            Repeater {
                model: [["upper", "A–Z"], ["lower", "a–z"], ["number", "0–9"], ["special", "!@#$%^&*"]]
                delegate: Setting {
                    id: option
                    required property var modelData
                    visible: !root.generator.passphrase || modelData[0] === "number"
                    label: root.generator.passphrase ? "Include a number" : modelData[1]
                    Toggle { checked: root.generator[option.modelData[0]]; onToggled: root.setOption(option.modelData[0], !checked) }
                }
            }
        }
    }
    Component {
        id: sendPage
        Scroll {
            id: send
            property int days: 7
            property int views: 0
            PopupField { id: sendName; width: parent.width; shell: root.shell; placeholderText: "Name"; Component.onCompleted: forceActiveFocus() }
            Box { id: sendText; placeholder: "Text to share" }
            Setting { label: "Delete after (days)"; Count { amount: send.days; onCommitted: amount => send.days = amount } }
            Setting { label: "Maximum views (0 = unlimited)"; Count { amount: send.views; onCommitted: amount => send.views = amount } }
            Secret { id: sendPassword; placeholderText: "Password (optional)" }
            PopupRow {
                width: parent.width; shell: root.shell; icon: "\u{f048a}"; title: "Create and copy link"
                onClicked: root.vault.createSend(Model.send(sendName.text, sendText.text, send.days, send.views, sendPassword.text))
            }
        }
    }
    Component {
        id: settingsPage
        Scroll {
            id: prefs
            property string arming: ""
            Component.onCompleted: root.vault.detectUnlockMethods()
            PopupSection { shell: root.shell; text: "SECURITY" }
            Setting { label: "Auto-lock after minutes (0 = never)"; Count { amount: root.settings.autoLockMinutes; onCommitted: amount => { root.settings.autoLockMinutes = amount; root.vault.touch() } } }
            Setting { label: "Clear clipboard after seconds"; Count { amount: root.settings.clearClipboardSeconds; onCommitted: amount => root.settings.clearClipboardSeconds = amount } }
            Setting { label: "Copy TOTP after the password (seconds)"; Count { amount: root.settings.autoCopyTotpSeconds; onCommitted: amount => root.settings.autoCopyTotpSeconds = amount } }
            Setting { label: "Lock with the screen"; Toggle { checked: root.settings.lockWithScreen; onToggled: root.settings.lockWithScreen = !checked } }
            Setting { label: "Close after Enter copies"; Toggle { checked: root.settings.closeOnCopy; onToggled: root.settings.closeOnCopy = !checked } }
            Setting { label: "Suggest items for the focused window"; Toggle { checked: root.settings.suggest; onToggled: root.settings.suggest = !checked } }
            PopupSection { shell: root.shell; text: "QUICK UNLOCK" }
            Row {
                spacing: Style.xs
                Repeater {
                    model: [["", "Off"], ["pin", "PIN"], ["fingerprint", "Fingerprint"], ["fido2", "FIDO2"]]
                        .filter(method => !method[0] || root.vault.unlockMethods.includes(method[0]))
                    delegate: Tab {
                        required property var modelData
                        label: modelData[1]; selected: (prefs.arming || root.settings.quickUnlock) === modelData[0]
                        onPicked: { prefs.arming = modelData[0]; if (!modelData[0]) root.vault.disarm() }
                    }
                }
            }
            Note { text: "Kept only in memory-backed runtime storage: after a reboot, unlock once with your master password to re-arm it." }
            Secret { id: armPin; visible: prefs.arming === "pin"; placeholderText: "New PIN"; inputMethodHints: Qt.ImhDigitsOnly }
            Secret {
                visible: prefs.arming !== "" && prefs.arming !== root.settings.quickUnlock
                placeholderText: "Master password to enable"
                onAccepted: {
                    if (prefs.arming === "pin" && armPin.text.length < 4) root.vault.error = "Use a PIN of at least four digits"
                    else root.vault.unlock({ BW_PASSWORD: text, PIN: armPin.text }, false, prefs.arming)
                }
            }
            PopupSection { shell: root.shell; text: "ACCOUNT" }
            PopupRow {
                width: parent.width; shell: root.shell; icon: "\u{f0343}"
                title: root.confirming ? "Click again to log out" : "Log out"; detail: root.vault.email
                onClicked: { if (root.confirming) root.vault.logout(); else root.confirming = true }
            }
        }
    }
}
