pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "Ui" as Ui

PopupCard {
    id: root
    popupName: "cliphist"
    keyboardHint: wipeDialog.opened ? "←→/Tab choose · Enter confirm · Esc cancel" : "Type to search · ↑↓ move · Enter copy · Del remove · Esc close"
    contentWidth: Style.px(430)
    contentHeight: Style.px(470)

    property var entries: []
    property var favorites: []
    property string filter: ""
    property string view: "history"
    readonly property int previewLines: 5
    readonly property int expandedPreviewLines: 16
    property bool previewExpanded: false

    // the preview pane shows the whole entry, so anything token-shaped is masked
    // in both places. the entry still copies normally — only the display is withheld
    readonly property var secretRules: [
        { re: /\bghp_[A-Za-z0-9]{20,}/, label: "GitHub token" },
        { re: /\bgh[ousr]_[A-Za-z0-9]{20,}/, label: "GitHub token" },
        { re: /\bgithub_pat_[A-Za-z0-9_]{20,}/, label: "GitHub fine-grained token" },
        { re: /\bglpat-[A-Za-z0-9_-]{15,}/, label: "GitLab token" },
        { re: /\bxox[abprs]-[A-Za-z0-9-]{10,}/, label: "Slack token" },
        { re: /\bsk-(ant-)?[A-Za-z0-9_-]{20,}/, label: "API key" },
        { re: /\bAKIA[0-9A-Z]{16}\b/, label: "AWS access key" },
        { re: /\bAIza[0-9A-Za-z_-]{35}/, label: "Google API key" },
        { re: /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\./, label: "JWT" },
        { re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/, label: "Private key" }
    ]
    function secretKind(text) {
        for (let i = 0; i < secretRules.length; ++i)
            if (secretRules[i].re.test(text)) return secretRules[i].label
        return ""
    }

    readonly property var rows: {
        const needle = filter.toLowerCase()
        const source = view === "favourites"
            ? favorites.map(entry => ({ key: entry.index, text: entry.text, favorite: true, image: false }))
            : entries.filter(entry => view !== "images" || entry.image === true)
                .map(entry => ({ key: entry.id, text: entry.preview, favorite: false, image: entry.image === true }))
        return needle === "" ? source : source.filter(entry => entry.text.toLowerCase().indexOf(needle) >= 0)
    }

    // mouse and keyboard drive the same cursor, so one row is ever focused
    readonly property var previewRow: {
        const index = Math.max(0, cursorIndex)
        return index < rows.length ? rows[index] : null
    }
    readonly property string previewText: {
        if (!previewRow) return ""
        const body = String(previewRow.text || "")
        return secretKind(body) || body
    }
    readonly property string previewImageKey: previewRow && previewRow.image ? String(previewRow.key) : ""
    property string previewImagePath: ""
    onPreviewImageKeyChanged: {
        previewImagePath = ""
        if (previewImageKey !== "")
            imageProc.exec([shell.home + "/.local/lib/hypr/clipboard/cliphist.sh", "--panel-image", previewImageKey])
    }

    // the search box can never hold focus (the bar owns it), so typing is routed
    // through the field's text, which stays the single source of truth
    function handleKey(event) {
        if (wipeDialog.opened) return wipeDialog.handleKey(event)
        if (event.key === Qt.Key_Delete && searchField.text === "" && rows.length > 0) {
            deleteRow(rows[Math.max(0, cursorIndex)]); return true
        }
        if (event.key === Qt.Key_E && (event.modifiers & Qt.ControlModifier)) {
            previewExpanded = !previewExpanded; return true
        }
        if (event.key === Qt.Key_Backspace) { searchField.text = searchField.text.slice(0, -1); return true }
        if (event.text && event.text.length === 1 && event.text >= " ") { searchField.text += event.text; return true }
        return defaultKey(event)
    }
    function refresh() { if (!listProc.running) listProc.running = true }
    function act(args, close) {
        if (close) shell.closePopup()
        shell.run(["hyprshell", "cliphist"].concat(args), root.refresh)
    }
    function copyRow(row) { act([row.favorite ? "--panel-fav-copy" : "--panel-copy", String(row.key)], true) }
    function deleteRow(row) {
        const key = String(row.key)
        if (row.favorite) favorites = favorites.filter(entry => String(entry.index) !== key)
        else entries = entries.filter(entry => String(entry.id) !== key)
        act([row.favorite ? "--panel-fav-remove" : "--panel-delete", key], false)
    }
    function pinRow(row) {
        if (row.favorite) return deleteRow(row)
        act(["--panel-fav-add", String(row.key)], false)
    }

    onOpenChanged: {
        if (!open) { filter = ""; view = "history"; previewExpanded = false; wipeDialog.opened = false; return }
        refresh()
        searchField.forceActiveFocus()
    }


    property Process listProc: Process {
        command: ["hyprshell", "cliphist", "--panel-json"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try {
                const payload = JSON.parse(text) || ({})
                root.entries = payload.entries || []
                root.favorites = payload.favorites || []
            } catch (error) { root.entries = []; root.favorites = [] }
        } }
    }
    property Process imageProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.previewImagePath = text.trim() }
    }

    Column {
        id: clipColumn
        anchors.fill: parent; spacing: Style.sectionGap

        Row {
            width: parent.width; spacing: Style.sm
            PopupTab { shell: root.shell; keyboardEnabled: false; text: "History"; selected: root.view === "history"; onClicked: root.view = "history" }
            PopupTab { shell: root.shell; keyboardEnabled: false; text: "Images"; selected: root.view === "images"; onClicked: root.view = "images" }
            PopupTab { shell: root.shell; keyboardEnabled: false; text: "Favourites  " + root.favorites.length; selected: root.view === "favourites"; onClicked: root.view = "favourites" }
        }

        Rectangle {
            width: parent.width; height: Style.controlHeight
            radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .25)
            border.width: 1
            border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), searchField.activeFocus ? .5 : .25)
            Text {
                id: searchGlyph
                anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0349}"
                color: root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            TextField {
                id: searchField
                anchors.left: searchGlyph.right; anchors.leftMargin: Style.xs
                anchors.right: countText.left; anchors.rightMargin: Style.xs
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                placeholderText: "Filter — Enter copy, Del remove, Ctrl+E expand"
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                background: null
                onTextChanged: root.filter = text
                Keys.onDownPressed: root.moveCursor(1)
                Keys.onUpPressed: root.moveCursor(-1)
                Keys.onReturnPressed: if (root.rows.length > 0) root.copyRow(root.rows[Math.max(0, root.cursorIndex)])
                Keys.onEnterPressed: if (root.rows.length > 0) root.copyRow(root.rows[Math.max(0, root.cursorIndex)])
                // Delete only reaches the list once the filter box is empty, so
                // backspacing a search never eats an entry by accident
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_E && (event.modifiers & Qt.ControlModifier)) {
                        root.previewExpanded = !root.previewExpanded
                        event.accepted = true
                    }
                }
                Keys.onDeletePressed: event => {
                    if (text !== "" || root.rows.length === 0) { event.accepted = false; return }
                    root.deleteRow(root.rows[Math.max(0, root.cursorIndex)])
                }
            }
            Text {
                id: countText
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: root.rows.length
                color: root.shell.faintText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
        }

        Text {
            visible: root.rows.length === 0
            width: parent.width
            text: root.filter !== "" ? "No match" : root.view === "favourites" ? "No favourites yet — pin one from History" : root.view === "images" ? "No images in history" : "History is empty"
            color: root.shell.mutedText
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        ListView {
            id: rowList
            width: parent.width
            height: Math.max(0, parent.height - y - previewBlock.height - footerBlock.height - clipColumn.spacing * 3)
            spacing: 2; clip: true
            model: root.rows
            currentIndex: root.cursorIndex

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                // modelData is briefly undefined while the view recycles rows,
                // so every binding reads these instead
                readonly property bool isFavorite: modelData ? modelData.favorite === true : false
                readonly property bool isImage: modelData ? modelData.image === true : false
                readonly property string bodyText: modelData ? String(modelData.text || "") : ""
                readonly property string secret: root.secretKind(bodyText)
                // keeps PopupCard's up/down cursor working over these rows
                readonly property bool navigable: true
                property bool cursored: false
                signal clicked(int button)

                width: ListView.view.width
                height: Style.popupRowHeight
                radius: root.shell.rounding
                color: cursored ? root.shell.hoverFill(2) : "transparent"
                border.width: cursored ? 1 : 0
                border.color: root.shell.hoverEdge(1)
                Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
                onClicked: root.copyRow(modelData)

                MouseArea {
                    id: rowArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyRow(row.modelData)
                    // movement, not entry: a list that re-filters or scrolls under a
                    // still pointer must not steal the cursor from the keyboard
                    onPositionChanged: root.cursorIndex = row.index
                }
                Text {
                    id: rowGlyph
                    visible: row.isFavorite || row.isImage || row.secret !== ""
                    anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.secret !== "" ? "\u{f0306}" : row.isFavorite ? "\u{f04ce}" : "\u{f021f}"
                    color: root.shell.mutedText
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                Text {
                    anchors.left: rowGlyph.visible ? rowGlyph.right : parent.left
                    anchors.leftMargin: Style.controlPaddingX
                    anchors.right: rowActions.left; anchors.rightMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.secret !== "" ? row.secret : row.bodyText
                    elide: Text.ElideRight
                    color: row.secret !== "" ? root.shell.mutedText : root.shell.foreground
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                    font.italic: row.secret !== ""
                }
                Row {
                    id: rowActions
                    anchors.right: parent.right; anchors.rightMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    opacity: row.cursored ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Style.duration(90) } }
                    PopupIconButton {
                        shell: root.shell; keyboardEnabled: false
                        visible: row.isImage
                        glyph: "\u{f113d}"
                        hint: "Extract text (OCR)"
                        onClicked: root.act(["--scan-image", String(row.modelData.key)], true)
                    }
                    PopupIconButton {
                        shell: root.shell; keyboardEnabled: false
                        visible: row.isImage
                        glyph: "\u{f0432}"
                        hint: "Decode QR code"
                        onClicked: root.act(["--scan-qr", String(row.modelData.key)], true)
                    }
                    PopupIconButton {
                        shell: root.shell; keyboardEnabled: false
                        glyph: row.isFavorite ? "\u{f04ce}" : "\u{f04d2}"
                        hint: row.isFavorite ? "Remove from favourites" : "Add to favourites"
                        onClicked: root.pinRow(row.modelData)
                    }
                    PopupIconButton {
                        shell: root.shell; keyboardEnabled: false
                        glyph: "\u{f0a7a}"
                        hint: row.isFavorite ? "Remove favourite" : "Delete from history"
                        onClicked: root.deleteRow(row.modelData)
                    }
                }
            }
        }

        Column {
            id: previewBlock
            visible: root.rows.length > 0
            width: parent.width; spacing: Style.sm
            // fixed height: a pane that grew with each entry would resize
            // the list under the cursor as you move down it
            property real paneHeight: lineProbe.implicitHeight * (root.previewExpanded ? root.expandedPreviewLines : root.previewLines)
            Behavior on paneHeight { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
            PopupSeparator { shell: root.shell }
            Image {
                id: previewImage
                visible: root.previewImageKey !== "" && status !== Image.Error
                width: parent.width; height: previewBlock.paneHeight
                source: root.previewImagePath !== "" ? "file://" + root.previewImagePath : ""
                sourceSize.width: width
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
            Flickable {
                visible: !previewImage.visible
                width: parent.width
                height: previewBlock.paneHeight
                contentHeight: previewText.implicitHeight
                clip: true; interactive: root.previewExpanded
            Text {
                id: previewText
                width: parent.width
                text: root.previewText
                wrapMode: Text.Wrap
                maximumLineCount: root.previewExpanded ? 0 : root.previewLines
                elide: root.previewExpanded ? Text.ElideNone : Text.ElideRight
                color: root.shell.alpha(root.shell.foreground, .75)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                font.italic: root.previewRow && root.secretKind(String(root.previewRow.text || "")) !== ""
                Text { id: lineProbe; visible: false; text: "M"; font: parent.font }
            }
            }
        }

        Column {
            id: footerBlock
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "\u{f0a79}"; title: "Clear all"
                onClicked: { wipeDialog.selectedIndex = 0; wipeDialog.opened = true }
            }
        }
    }

    Ui.ConfirmDialog {
        id: wipeDialog
        anchors.fill: parent
        z: 10
        message: "Clear clipboard history? Favourites are kept."
        confirmText: "Clear"
        background: root.background
        foreground: root.shell.foreground
        fontFamily: root.shell.fontFamily
        onCanceled: opened = false
        onConfirmed: {
            opened = false
            root.act(["--wipe"], false)
        }
    }
}
