import QtQuick
import QtQuick.Controls
import Quickshell.Io

// Full replacement for the rofi clipboard menu: history, favourites, search
// and per-entry delete/favourite. OCR and QR live on the capture submap, since
// they select a screen region rather than reading from history.
PopupCard {
    id: root
    popupName: "cliphist"
    contentWidth: 430
    contentHeight: 470

    property var entries: []
    property var favorites: []
    property string filter: ""
    property bool showFavorites: false

    // previews render on hover now, so anything token-shaped is shown masked.
    // the entry still copies normally — only the display is withheld
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
        const source = showFavorites
            ? favorites.map(entry => ({ key: entry.index, text: entry.text, favorite: true, image: false }))
            : entries.map(entry => ({ key: entry.id, text: entry.preview, favorite: false, image: entry.image === true }))
        return needle === "" ? source : source.filter(entry => entry.text.toLowerCase().indexOf(needle) >= 0)
    }

    function refresh() { if (!listProc.running) listProc.running = true }
    function act(args, close) {
        const process = actionComponent.createObject(root)
        process.command = ["hyprshell", "cliphist"].concat(args)
        process.running = true
        if (close) shell.closePopup()
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
        if (!open) { filter = ""; showFavorites = false; return }
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
    property Component actionComponent: Component { Process { onExited: { root.refresh(); destroy() } } }

    component Tab: Rectangle {
        required property string label
        required property bool selected
        signal picked
        implicitWidth: tabText.implicitWidth + Style.controlPaddingX * 2
        implicitHeight: 24
        radius: root.shell.rounding
        color: selected ? root.shell.alpha(root.shell.role("act_bg", root.shell.accent), .25)
            : tabArea.containsMouse ? root.shell.alpha(root.shell.role("hvr_bg", root.shell.accent), Style.hoverFillAlpha)
            : "transparent"
        Text {
            id: tabText
            anchors.centerIn: parent
            text: parent.label
            color: parent.selected ? root.shell.foreground : root.shell.alpha(root.shell.foreground, .6)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            font.bold: parent.selected; font.letterSpacing: 1
        }
        MouseArea {
            id: tabArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.picked()
        }
    }

    // an inline row action, labelled by its own tooltip rather than a mouse button
    component RowAction: Rectangle {
        id: rowAction
        required property string glyph
        required property string hint
        signal triggered
        readonly property alias hovered: actionArea.containsMouse
        width: 30; height: 30; radius: root.shell.rounding
        color: actionArea.containsMouse ? root.shell.alpha(root.shell.role("hvr_bg", root.shell.accent), .35) : "transparent"
        Text {
            anchors.centerIn: parent
            text: rowAction.glyph
            color: root.shell.alpha(root.shell.foreground, actionArea.containsMouse ? 1 : .7)
            font.family: root.shell.fontFamily; font.pixelSize: Style.title
        }
        MouseArea {
            id: actionArea
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: rowAction.triggered()
        }
        BarTooltip { shell: root.shell; anchorItem: rowAction; text: rowAction.hint; hovered: actionArea.containsMouse }
    }

    Column {
        id: clipColumn
        anchors.fill: parent; spacing: Style.sm

        Row {
            width: parent.width; spacing: Style.xs
            Tab {
                label: "HISTORY"; selected: !root.showFavorites
                onPicked: root.showFavorites = false
            }
            Tab {
                label: "FAVOURITES  " + root.favorites.length; selected: root.showFavorites
                onPicked: root.showFavorites = true
            }
        }

        Rectangle {
            width: parent.width; height: 28
            radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("alt_bg", root.shell.background), .25)
            border.width: 1
            border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), searchField.activeFocus ? .5 : .25)
            Text {
                id: searchGlyph
                anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0349}"
                color: root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            TextField {
                id: searchField
                anchors.left: searchGlyph.right; anchors.leftMargin: Style.xs
                anchors.right: countText.left; anchors.rightMargin: Style.xs
                anchors.verticalCenter: parent.verticalCenter
                height: 20
                leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                placeholderText: "Type to filter — Enter copies, Esc closes"
                color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                background: null
                onTextChanged: root.filter = text
                Keys.onDownPressed: root.moveCursor(1)
                Keys.onUpPressed: root.moveCursor(-1)
                Keys.onReturnPressed: if (root.rows.length > 0) root.copyRow(root.rows[Math.max(0, root.cursorIndex)])
                Keys.onEnterPressed: if (root.rows.length > 0) root.copyRow(root.rows[Math.max(0, root.cursorIndex)])
            }
            Text {
                id: countText
                anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
                anchors.verticalCenter: parent.verticalCenter
                text: root.rows.length
                color: root.shell.alpha(root.shell.foreground, .4)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
        }

        Text {
            visible: root.rows.length === 0
            width: parent.width
            text: root.filter !== "" ? "No match" : root.showFavorites ? "No favourites yet — pin one from History" : "History is empty"
            color: root.shell.alpha(root.shell.foreground, .5)
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }

        ListView {
            id: rowList
            width: parent.width
            height: Math.max(0, parent.height - y - footerBlock.height - clipColumn.spacing * 2)
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
                // the action buttons take the hover off rowArea, so the row's
                // highlight has to account for them too
                readonly property bool highlighted: rowArea.containsMouse || cursored
                    || pinAction.hovered || deleteAction.hovered

                width: ListView.view.width
                height: 34
                radius: root.shell.rounding
                color: highlighted
                    ? root.shell.alpha(root.shell.role("hvr_bg", root.shell.accent), Style.hoverFillAlpha * 2)
                    : "transparent"
                border.width: highlighted ? 1 : 0
                border.color: root.shell.alpha(root.shell.role("hvr_br", root.shell.foreground), cursored ? .55 : .3)
                Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
                onClicked: root.copyRow(modelData)

                MouseArea {
                    id: rowArea
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyRow(row.modelData)
                }
                Text {
                    id: rowGlyph
                    visible: row.isFavorite || row.isImage || row.secret !== ""
                    anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.secret !== "" ? "\u{f0306}" : row.isFavorite ? "\u{f04ce}" : "\u{f021f}"
                    color: root.shell.alpha(root.shell.foreground, .5)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                }
                Text {
                    anchors.left: rowGlyph.visible ? rowGlyph.right : parent.left
                    anchors.leftMargin: Style.controlPaddingX
                    anchors.right: rowActions.left; anchors.rightMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.secret !== "" ? row.secret : row.bodyText
                    elide: Text.ElideRight
                    color: row.secret !== "" ? root.shell.alpha(root.shell.foreground, .55) : root.shell.foreground
                    font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                    font.italic: row.secret !== ""
                }
                Row {
                    id: rowActions
                    anchors.right: parent.right; anchors.rightMargin: Style.xs
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    opacity: row.highlighted ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 90 } }
                    RowAction {
                        id: pinAction
                        glyph: row.isFavorite ? "\u{f04ce}" : "\u{f04d2}"
                        hint: row.isFavorite ? "Remove from favourites" : "Add to favourites"
                        onTriggered: root.pinRow(row.modelData)
                    }
                    RowAction {
                        id: deleteAction
                        glyph: "\u{f0a7a}"
                        hint: row.isFavorite ? "Remove favourite" : "Delete from history"
                        onTriggered: root.deleteRow(row.modelData)
                    }
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
                onClicked: root.act(["-w"], false)
            }
        }
    }
}
