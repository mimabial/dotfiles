pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io

PopupCard {
    id: root
    popupName: "converter"
    contentWidth: Style.px(430)
    contentHeight: Style.px(520)

    property string selectedTab: "units"
    property int categoryIndex: 0
    property int fromIndex: 0
    property int toIndex: 1
    property var categories: []
    property var currencies: []
    property string rateDate: ""
    property string rateError: ""
    property bool ratesLoading: false
    readonly property var category: categories[categoryIndex] || ({units: []})
    readonly property var choices: selectedTab === "units" ? category.units : currencies
    readonly property var fromUnit: choices[fromIndex] || null
    readonly property var toUnit: choices[toIndex] || null
    readonly property real amount: Number(String(amountField.text).replace(",", "."))
    readonly property bool valid: amountField.text.trim() !== "" && Number.isFinite(amount) && fromUnit && toUnit
    readonly property real converted: valid ? (amount * fromUnit.scale + fromUnit.offset - toUnit.offset) / toUnit.scale : NaN
    readonly property string result: valid ? root.number(converted) + " " + toUnit.symbol : "—"

    function number(value) { return Number(value.toPrecision(10)).toString() }
    function resetUnits() { fromIndex = 0; toIndex = Math.min(1, choices.length - 1) }
    function swap() { const previous = fromIndex; fromIndex = toIndex; toIndex = previous }
    function loadUnits(raw) {
        try { categories = JSON.parse(raw).categories || [] }
        catch (error) { categories = [] }
        categoryIndex = 0; resetUnits()
    }
    function loadRates(raw) {
        try {
            const payload = JSON.parse(raw)
            currencies = payload.currencies || []; rateDate = payload.date || ""; rateError = payload.error || ""
        } catch (error) { currencies = []; rateError = "Currency rates unavailable" }
        ratesLoading = false
        if (selectedTab === "currency") resetUnits()
    }
    function ensureRates() {
        if (currencies.length || ratesProc.running) return
        ratesLoading = true; rateError = ""; ratesProc.running = true
    }
    function selectTab(tab) { selectedTab = tab; resetUnits(); if (tab === "currency") ensureRates() }
    onCategoryIndexChanged: resetUnits()
    onOpenChanged: if (open) {
        if (!categories.length && !unitsProc.running) unitsProc.running = true
        if (selectedTab === "currency") ensureRates()
        amountField.forceActiveFocus(); amountField.selectAll()
    }

    property Process unitsProc: Process {
        command: [root.shell.home + "/.local/lib/hypr/util/converter.py", "--units"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadUnits(text) }
    }
    property Process ratesProc: Process {
        command: [root.shell.home + "/.local/lib/hypr/util/converter.py", "--rates"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadRates(text) }
    }

    component FieldLabel: Text {
        color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily
        font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1
    }
    component TabButton: BarButton {
        required property string tab
        active: false; radius: shell.rounding; fill: "transparent"; outline: "transparent"
        textColor: root.selectedTab === tab ? shell.accent : shell.alpha(shell.foreground, .6)
    }

    Column {
        id: panel
        anchors.fill: parent; spacing: Style.md
        PopupHero {
            shell: root.shell; title: "Converter"
            status: root.selectedTab === "units" ? root.category.label || "units"
                : root.ratesLoading ? "loading rates" : root.rateError || (root.rateDate ? "ECB · " + root.rateDate : "currency")
        }
        Row {
            width: parent.width; spacing: Style.sm
            TabButton { width: (parent.width - parent.spacing) / 2; height: Style.controlHeight; shell: root.shell; text: "UNIT"; tab: "units"; onClicked: root.selectTab(tab) }
            TabButton { width: (parent.width - parent.spacing) / 2; height: Style.controlHeight; shell: root.shell; text: "CURRENCY"; tab: "currency"; onClicked: root.selectTab(tab) }
        }
        Column {
            width: parent.width; spacing: Style.xxs
            FieldLabel { text: "AMOUNT" }
            TextField {
                id: amountField
                width: parent.width; height: Style.px(42); text: "1"; selectByMouse: true
                color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.title
                leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: DoubleValidator { notation: DoubleValidator.ScientificNotation }
                background: Rectangle {
                    radius: root.shell.rounding; color: root.shell.alpha(root.shell.foreground, .06)
                    border.color: root.shell.alpha(root.shell.role(amountField.activeFocus ? "act_br" : "br", root.shell.foreground), amountField.activeFocus ? .55 : .3)
                }
            }
        }
        Column {
            visible: root.selectedTab === "units"
            width: parent.width; spacing: Style.xxs
            FieldLabel { text: "CATEGORY" }
            PopupSelect { width: parent.width; shell: root.shell; choices: root.categories; selectedIndex: root.categoryIndex; onActivated: index => root.categoryIndex = index }
        }
        Row {
            width: parent.width; spacing: Style.xs
            Column {
                width: (parent.width - swapButton.width - parent.spacing * 2) / 2; spacing: Style.xxs
                FieldLabel { text: "FROM" }
                PopupSelect { width: parent.width; shell: root.shell; choices: root.choices; selectedIndex: root.fromIndex; onActivated: index => root.fromIndex = index }
            }
            Rectangle {
                id: swapButton
                anchors.bottom: parent.bottom; width: Style.px(40); height: Style.px(40); radius: root.shell.rounding
                color: swapMouse.containsMouse ? root.shell.hoverFill() : root.shell.alpha(root.shell.foreground, .06)
                Text { anchors.centerIn: parent; text: "󰑃"; color: root.shell.foreground; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.title }
                MouseArea { id: swapMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.swap() }
            }
            Column {
                width: (parent.width - swapButton.width - parent.spacing * 2) / 2; spacing: Style.xxs
                FieldLabel { text: "TO" }
                PopupSelect { width: parent.width; shell: root.shell; choices: root.choices; selectedIndex: root.toIndex; onActivated: index => root.toIndex = index }
            }
        }
        Rectangle {
            width: parent.width; height: Style.px(94); radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("act_bg", root.shell.background), .22)
            border.width: 1; border.color: root.shell.alpha(root.shell.role("act_br", root.shell.accent), .4)
            Column {
                anchors.fill: parent; anchors.margins: Style.controlPaddingX; spacing: Style.xxs
                FieldLabel { text: "RESULT" }
                Text { width: parent.width; text: root.ratesLoading ? "Loading…" : root.result; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.display; font.bold: true; elide: Text.ElideRight }
                Text { width: parent.width; text: root.valid ? root.number(root.amount) + " " + root.fromUnit.symbol + " → " + root.toUnit.symbol : root.rateError; color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight }
            }
            MouseArea { anchors.fill: parent; enabled: root.valid; cursorShape: Qt.PointingHandCursor; onClicked: root.shell.run(["wl-copy", root.result]) }
        }
        Text {
            width: parent.width
            text: root.selectedTab === "currency" ? "ECB reference rates · click the result to copy" : root.category.label === "Volume" ? "US customary liquid measures · click the result to copy" : "Click the result to copy"
            color: root.shell.alpha(root.shell.foreground, .4); font.family: root.shell.fontFamily
            font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter
        }
    }
}
