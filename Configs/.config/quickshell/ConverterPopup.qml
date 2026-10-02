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

    Column {
        id: panel
        anchors.fill: parent; spacing: Style.sectionGap
        PopupHero {
            shell: root.shell; title: "Converter"
            status: root.selectedTab === "units" ? root.category.label || "units"
                : root.ratesLoading ? "loading rates" : root.rateError || (root.rateDate ? "ECB · " + root.rateDate : "currency")
        }
        Row {
            width: parent.width; spacing: Style.sm
            PopupTab { width: (parent.width - parent.spacing) / 2; shell: root.shell; text: "Unit"; selected: root.selectedTab === "units"; onClicked: root.selectTab("units") }
            PopupTab { width: (parent.width - parent.spacing) / 2; shell: root.shell; text: "Currency"; selected: root.selectedTab === "currency"; onClicked: root.selectTab("currency") }
        }
        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "AMOUNT" }
            TextField {
                id: amountField
                readonly property bool navigable: true
                property bool cursored: false
                function activateKeyboard() { forceActiveFocus(); selectAll() }
                width: parent.width; height: Style.controlHeight; text: "1"; selectByMouse: true
                color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.title
                leftPadding: Style.controlPaddingX; rightPadding: Style.controlPaddingX
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                validator: DoubleValidator { notation: DoubleValidator.ScientificNotation }
                onActiveFocusChanged: if (activeFocus) root.selectRow(amountField)
                Keys.onTabPressed: { root.resumeKeyboard(); root.moveCursor(1) }
                Keys.onBacktabPressed: { root.resumeKeyboard(); root.moveCursor(-1) }
                background: Rectangle {
                    radius: root.shell.rounding; color: root.shell.alpha(root.shell.foreground, .06)
                    border.color: amountField.cursored ? root.shell.hoverEdge(.85)
                        : root.shell.alpha(root.shell.role(amountField.activeFocus ? "act_br" : "br", root.shell.foreground), amountField.activeFocus ? .55 : .3)
                }
            }
        }
        Column {
            visible: root.selectedTab === "units"
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "CATEGORY" }
            PopupSelect { width: parent.width; shell: root.shell; choices: root.categories; selectedIndex: root.categoryIndex; onActivated: index => root.categoryIndex = index }
        }
        Row {
            width: parent.width; spacing: Style.xs
            Column {
                width: (parent.width - swapButton.width - parent.spacing * 2) / 2; spacing: Style.sm
                PopupSection { shell: root.shell; text: "FROM" }
                PopupSelect { width: parent.width; shell: root.shell; choices: root.choices; selectedIndex: root.fromIndex; onActivated: index => root.fromIndex = index }
            }
            Rectangle {
                id: swapButton
                readonly property bool navigable: true
                property bool cursored: false
                signal clicked(int button)
                onClicked: root.swap()
                anchors.bottom: parent.bottom; width: Style.controlHeight; height: Style.controlHeight; radius: root.shell.rounding
                color: swapMouse.containsMouse ? root.shell.hoverFill() : root.shell.alpha(root.shell.foreground, .06)
                border.color: cursored ? root.shell.hoverEdge(.85) : "transparent"
                Text { anchors.centerIn: parent; text: "󰑃"; color: root.shell.foreground; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.title }
                MouseArea { id: swapMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: swapButton.clicked(Qt.LeftButton) }
            }
            Column {
                width: (parent.width - swapButton.width - parent.spacing * 2) / 2; spacing: Style.sm
                PopupSection { shell: root.shell; text: "TO" }
                PopupSelect { width: parent.width; shell: root.shell; choices: root.choices; selectedIndex: root.toIndex; onActivated: index => root.toIndex = index }
            }
        }
        Rectangle {
            readonly property bool navigable: root.valid
            property bool cursored: false
            signal clicked(int button)
            onClicked: root.shell.run(["wl-copy", root.result])
            width: parent.width; height: resultColumn.implicitHeight + Style.controlPaddingX * 2; radius: root.shell.rounding
            color: root.shell.alpha(root.shell.role("act_bg", root.shell.background), .22)
            border.width: 1; border.color: cursored ? root.shell.hoverEdge(.85) : root.shell.alpha(root.shell.role("act_br", root.shell.accent), .4)
            Column {
                id: resultColumn
                anchors.fill: parent; anchors.margins: Style.controlPaddingX; spacing: Style.sm
                PopupSection { shell: root.shell; text: "RESULT" }
                Text { width: parent.width; text: root.ratesLoading ? "Loading…" : root.result; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.display; font.bold: true; elide: Text.ElideRight }
                Text { width: parent.width; text: root.valid ? root.number(root.amount) + " " + root.fromUnit.symbol + " → " + root.toUnit.symbol : root.rateError; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight }
            }
            MouseArea { anchors.fill: parent; enabled: root.valid; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked(Qt.LeftButton) }
        }
        Text {
            width: parent.width
            text: root.selectedTab === "currency" ? "ECB reference rates · click the result to copy" : root.category.label === "Volume" ? "US customary liquid measures · click the result to copy" : "Click the result to copy"
            color: root.shell.faintText; font.family: root.shell.fontFamily
            font.pixelSize: Style.caption; horizontalAlignment: Text.AlignHCenter
        }
    }
}
