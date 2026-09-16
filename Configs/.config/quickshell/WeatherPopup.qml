import QtQuick
import QtQuick.Controls
import Quickshell.Io

PopupCard {
    id: root
    popupName: "weather"
    contentWidth: Style.px(420)
    contentHeight: weatherColumn.implicitHeight + 32
    readonly property var conditions: Weather.data.current_condition ? Weather.data.current_condition[0] : ({})
    readonly property var days: Weather.data.weather ? Weather.data.weather.slice(0, 7) : []
    // -1 = the rolling next-12-hours view; otherwise the day whose card was clicked
    property int selectedDay: -1
    readonly property var hours: {
        if (selectedDay >= 0 && selectedDay < days.length) return days[selectedDay].hourly || []
        const upcoming = [], cutoff = Date.now() - 3600000
        for (const day of days) for (const hour of day.hourly || [])
            if (new Date(hour.time).getTime() >= cutoff) upcoming.push(hour)
        return upcoming.slice(0, 12)
    }
    readonly property string hourlyLabel: selectedDay < 0 || selectedDay >= days.length ? "HOURLY"
        : selectedDay === 0 ? "TODAY"
        : Qt.formatDate(new Date(days[selectedDay].date + "T12:00:00"), "ddd").toUpperCase()
    property int forecastTab: 0
    readonly property var cards: forecastTab === 0 ? hours : days
    // the keyboard cursor over the strip; -1 until an arrow key claims one
    property int cardIndex: -1
    function showHours(day) {
        selectedDay = day
        forecastTab = 0
        cardIndex = -1
        forecast.positionViewAtBeginning()
    }
    function showDays() {
        // coming back out of a day, land the cursor on the day we drilled into
        const from = selectedDay
        selectedDay = -1
        forecastTab = 1
        cardIndex = from
        forecast.positionViewAtBeginning()
        if (from >= 0) Qt.callLater(() => forecast.positionViewAtIndex(from, ListView.Contain))
    }
    function scrollForecast(amount) {
        const limit = Math.max(0, forecast.contentWidth - forecast.width)
        forecast.contentX = Math.max(0, Math.min(limit, forecast.contentX + amount))
    }
    function moveCard(step) { moveCardTo(cardIndex < 0 ? (step > 0 ? 0 : cards.length - 1) : cardIndex + step) }
    function moveCardTo(index) {
        if (!cards.length) return
        cardIndex = Math.max(0, Math.min(cards.length - 1, index))
        forecast.positionViewAtIndex(cardIndex, ListView.Contain)
    }
    // DAILY is the parent level and HOURLY the child, so Down drills into the
    // selected day and Up backs out of whichever hourly view is showing
    function drillIn() {
        if (forecastTab !== 1) return false
        showHours(cardIndex < 0 ? 0 : cardIndex)
        return true
    }
    function drillOut() {
        if (forecastTab !== 0) return false
        showDays()
        return true
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape && searching) { cityField.text = ""; searching = false; return true }
        // the city field owns the keyboard while the search is up
        if (searching) return false
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_H:      moveCard(-1); return true
        case Qt.Key_Right:
        case Qt.Key_L:      moveCard(1); return true
        case Qt.Key_Home:   moveCardTo(0); return true
        case Qt.Key_End:    moveCardTo(cards.length - 1); return true
        // no Tab binding: Qt's focus navigation escapes the popup's focus grab,
        // which closes the card out from under the keypress
        case Qt.Key_Down:
        case Qt.Key_J:      return drillIn()
        case Qt.Key_Return:
        case Qt.Key_Enter:  return drillIn()
        case Qt.Key_Up:
        case Qt.Key_K:      return drillOut()
        case Qt.Key_U:      toggleUnits(); return true
        case Qt.Key_R:      shell.run(["hyprshell", "weather", "--force", "--alt"]); return true
        case Qt.Key_M:      weatherColumn.expanded = !weatherColumn.expanded; return true
        case Qt.Key_S:
        case Qt.Key_Slash:  openSearch(); return true
        // back out of a pinned day before the popup itself closes
        case Qt.Key_Escape: if (selectedDay >= 0) { showDays(); return true } break
        }
        return defaultKey(event)
    }
    // the producer reports both unit systems, so switching needs no refetch
    // -1 = never chosen, so fall back to where the reading is from
    property int unitChoice: -1
    readonly property bool imperial: unitChoice >= 0 ? unitChoice === 1 : localeImperial
    readonly property bool localeImperial: {
        const country = String(value(Weather.data.nearest_area
            ? Weather.data.nearest_area[0].country : null, "")).toLowerCase()
        if (country) {
            if (["us", "usa", "united states", "united states of america"].includes(country)) return true
            if (["liberia", "myanmar", "burma"].includes(country)) return true
            return false
        }
        const locale = String(Qt.locale().name).replace(".", "_")
        return /^en[_-]US($|[_.-])/.test(locale) || /^en[_-]LR($|[_.-])/.test(locale) || /^my($|[_.-])/.test(locale)
    }
    readonly property string degrees: imperial ? "\u00b0F" : "\u00b0C"
    readonly property string windUnit: imperial ? " mph" : " km/h"
    function temp(source, key) { return (source && source[key + (imperial ? "F" : "C")]) || "--" }
    function wind() { return (conditions[imperial ? "windspeedMiles" : "windspeedKmph"] || "--") + windUnit }
    function toggleUnits() {
        unitChoice = imperial ? 0 : 1
        store.setText(JSON.stringify({imperial: unitChoice === 1}))
    }

    property FileView store: FileView {
        path: root.shell.home + "/.local/state/quickshell/weather.json"
        printErrors: false
        onLoaded: {
            try { root.unitChoice = JSON.parse(text()).imperial === true ? 1 : 0 }
            catch (error) { root.unitChoice = -1 }
        }
    }

    readonly property var today: days.length ? days[0] : ({})
    readonly property var astronomy: today.astronomy && today.astronomy.length ? today.astronomy[0] : ({})

    function distance(km) {
        if (!km) return "--"
        return imperial ? Math.round(Number(km) * 0.621371) + " mi" : km + " km"
    }
    function pressure(hpa) {
        if (!hpa) return "--"
        return imperial ? (Number(hpa) * 0.02953).toFixed(2) + " inHg" : hpa + " hPa"
    }

    property bool searching: false
    // empty when the location is auto-detected; the pinned city otherwise
    property string override: ""

    property var suggestions: []
    // keyboard cursor over the results; new results always reselect the first
    property int suggestionIndex: 0
    onSuggestionsChanged: suggestionIndex = 0
    function moveSuggestion(step) {
        if (!suggestions.length) return
        suggestionIndex = Math.max(0, Math.min(suggestions.length - 1, suggestionIndex + step))
    }
    // set when Enter arrived before the search returned
    property bool pendingAccept: false

    function readOverride() { if (!overrideProc.running) overrideProc.running = true }
    // the previous results stay up until the new ones land — clearing here made
    // the list blink shut and reopen on every keystroke
    function searchCities(query) {
        if (query.trim() === "") { suggestions = []; return }
        searchProc.command = ["hyprshell", "weather", "--search", query.trim()]
        searchProc.running = true
    }
    function pick(place) {
        const label = place.name + (place.country ? ", " + place.country : "")
        shell.run(["hyprshell", "util/weather-location", "--pin",
                   place.latitude + "," + place.longitude, label], root.readOverride)
        suggestions = []
        cityField.text = ""
        searching = false
    }

    property Process searchProc: Process {
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.suggestions = JSON.parse(text) || [] }
            catch (error) { root.suggestions = [] }
            if (root.pendingAccept) {
                root.pendingAccept = false
                if (root.suggestions.length > 0) root.pick(root.suggestions[0])
                else { root.cityFieldText(""); root.searching = false }
            }
        } }
    }
    function cityFieldText(value) { cityField.text = value }
    // typing shouldn't fire a request per keystroke, and a keystroke landing mid
    // request would be dropped: Process ignores a new command while it runs
    property Timer searchDebounce: Timer {
        interval: 200
        onTriggered: if (root.searchProc.running) restart(); else root.searchCities(cityField.text)
    }
    // the override stores what was typed; show the name the provider resolved
    function cityName() {
        const area = Weather.data.nearest_area
        return area && area.length ? value(area[0].areaName, override) : override
    }
    function openSearch() {
        searching = true
        // a pinned city is offered back for editing, selected so typing replaces it
        cityField.text = override === "" ? "" : cityName()
        cityField.forceActiveFocus()
        if (override !== "") cityField.selectAll()
    }

    // the reading itself comes from the Weather singleton's file watch; this
    // only needs to learn whether a city is pinned
    onOpenChanged: {
        if (open) readOverride()
        else { searching = false; cityField.text = ""; selectedDay = -1; cardIndex = -1; forecastTab = 0 }
    }

    property Process overrideProc: Process {
        command: ["hyprshell", "util/weather-location"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.override = String(text).trim() }
    }

    function setLocation(name) {
        shell.run(["hyprshell", "util/weather-location", name], root.readOverride)
        // the singleton watches the cache file, so it picks the new place up
        // on its own once the fetch lands
    }

    function value(list, fallback) { return list && list.length ? list[0].value : fallback }
    function location() { const area = Weather.data.nearest_area; return area && area.length ? value(area[0].areaName, "") + ", " + value(area[0].country, "") : "" }

    component ForecastTab: BarButton {
        required property int tab
        active: false; radius: shell.rounding; fill: "transparent"; outline: "transparent"
        textColor: root.forecastTab === tab ? shell.accent : shell.alpha(shell.foreground, .6)
    }

    component ForecastArrow: Text {
        required property string glyph
        text: glyph
        color: root.shell.alpha(root.shell.foreground, arrowMouse.containsMouse ? 1 : .5)
        font.family: root.shell.fontFamily; font.pixelSize: Style.display
        signal activated
        MouseArea {
            id: arrowMouse; anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    // sits under the content, and only while searching: a click that no control
    // handles lands here and closes the field
    MouseArea {
        anchors.fill: parent
        enabled: root.searching
        onClicked: { cityField.text = ""; root.searching = false }
    }

    Column {
        id: weatherColumn
        anchors.left: parent.left; anchors.right: parent.right
        spacing: Style.px(14)
        Item {
            id: hero
            width: parent.width
            height: heroStack.implicitHeight
            // the popup's centre line is the seam: glyph ends on it, stack starts
            Text {
                id: heroIcon
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.horizontalCenterOffset: -parent.width / 4
                anchors.verticalCenter: parent.verticalCenter
                text: String(Weather.output.text).trim().split(/\s+/)[0] || "󰖐"
                color: root.shell.role("c2", root.shell.foreground)
                font.family: root.shell.fontFamily; font.pixelSize: Style.heroIcon
            }
            Text {
                id: refreshAction
                anchors.top: parent.top; anchors.right: parent.right
                text: "󰑐"
                color: refreshMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily; font.pixelSize: Style.title
                MouseArea { id: refreshMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.shell.run(["hyprshell", "weather", "--force", "--alt"]) }
            }
            Column {
                    id: heroStack
                    anchors.left: heroIcon.right; anchors.leftMargin: Style.px(12)
                    anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Text {
                        text: root.temp(root.conditions, "FeelsLike") + root.degrees
                        color: tempMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: Style.displayLarge; font.bold: true
                        MouseArea {
                            id: tempMouse; anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleUnits()
                        }
                    }
                    Text {
                        text: root.value(root.conditions.weatherDesc, "Weather")
                        color: root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: Style.subtitle
                    }
                    Item {
                        // out to the popup's right edge
                        width: hero.width - heroStack.x; height: Style.px(18)

                        Text {
                            id: locationLabel
                            visible: !root.searching
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            text: root.location()
                            color: locationMouse.containsMouse
                                ? root.shell.role("hvr_fg", root.shell.foreground)
                                : root.shell.alpha(root.shell.foreground, .55)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                        MouseArea {
                            id: locationMouse
                            visible: !root.searching
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            width: locationLabel.implicitWidth + 12; height: parent.height + 8
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSearch()
                        }

                        TextField {
                            id: cityField
                            visible: root.searching
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: Style.px(18)
                            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                            placeholderText: "City name \u2014 Empty to auto-detect"
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                            background: null
                            onTextChanged: if (root.searching) { root.pendingAccept = false; root.searchDebounce.restart() }
                            onAccepted: {
                                if (text === "") { root.setLocation("--clear"); root.searching = false }
                                else if (root.suggestions.length > 0) root.pick(root.suggestions[root.suggestionIndex])
                                // typed and hit Enter before the debounce fired:
                                // run the search now and take the first result
                                else { root.pendingAccept = true; root.searchCities(text) }
                            }
                            Keys.onDownPressed: root.moveSuggestion(1)
                            Keys.onUpPressed: root.moveSuggestion(-1)
                            Keys.onEscapePressed: { text = ""; root.searching = false }
                        }

                    }
            }
        }
        // everything is one block now: the four that matter stay visible and
        // the rest unfold in two columns
        property bool expanded: false
        readonly property var metrics: [
            ["MAX|MIN", root.today.maxtempC ? root.temp(root.today, "maxtemp") + "\u00b0 | " + root.temp(root.today, "mintemp") + "\u00b0" : "--"],
            ["FEELS", root.temp(root.conditions, "FeelsLike") + root.degrees],
            ["RAIN", (root.days.length ? root.days[0].chanceofrain : "--") + "%"],
            ["WIND", root.wind()],
            ["UV", root.conditions.uvIndex || "--"],
            ["HUMID", (root.conditions.humidity || "--") + "%"],
            ["PRESSURE", root.pressure(root.conditions.pressure)],
            ["DEW POINT", root.conditions.DewPointC ? root.temp(root.conditions, "DewPoint") + root.degrees : "--"],
            ["VISIBILITY", root.distance(root.conditions.visibility)],
            ["CLOUD", (root.conditions.cloudcover || "--") + "%"],
            ["SUNRISE", root.astronomy.sunrise || "--"],
            ["SUNSET", root.astronomy.sunset || "--"]
        ]

        Column {
            visible: root.searching && root.suggestions.length > 0
            width: parent.width; spacing: 2
            Repeater {
                model: root.suggestions
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool cursored: root.suggestionIndex === index
                    width: parent.width; height: Style.px(26); radius: root.shell.rounding
                    color: (pickMouse.containsMouse || cursored) ? root.shell.hoverFill(1.5) : "transparent"
                    border.width: cursored ? 1 : 0
                    border.color: root.shell.hoverEdge(.85)
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: Style.px(6)
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.name
                            + (parent.modelData.region ? "  \u00b7  " + parent.modelData.region : "")
                            + (parent.modelData.country ? ", " + parent.modelData.country : "")
                        color: root.shell.alpha(root.shell.foreground, .85)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        elide: Text.ElideRight
                        width: parent.width - 12
                    }
                    MouseArea {
                        id: pickMouse; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.pick(parent.modelData)
                    }
                }
            }
        }
        PopupSeparator { shell: root.shell }
        Row {
            width: parent.width; spacing: Style.sm
            ForecastTab { width: (parent.width - parent.spacing) / 2; height: Style.controlHeight; shell: root.shell; tab: 0; text: root.hourlyLabel; onClicked: root.showHours(-1) }
            ForecastTab { width: (parent.width - parent.spacing) / 2; height: Style.controlHeight; shell: root.shell; tab: 1; text: "DAILY"; onClicked: root.showDays() }
        }
        Item {
            width: parent.width; height: Style.px(88)
            ListView {
                id: forecast
                anchors.fill: parent
                // the arrows keep their own gutters, so a click near an edge picks
                // the arrow rather than the card that would otherwise sit under it
                anchors.leftMargin: Style.px(15); anchors.rightMargin: Style.px(15)
                orientation: ListView.Horizontal
                model: root.cards
                spacing: Style.sm; clip: true; boundsBehavior: Flickable.StopAtBounds; snapMode: ListView.SnapToItem
                delegate: Rectangle {
                    id: forecastCard
                    required property var modelData
                    required property int index
                    readonly property bool cursored: root.cardIndex === index
                    width: (forecast.width - forecast.spacing * 4) / 5; height: forecast.height
                    radius: root.shell.rounding
                    color: (dayMouse.containsMouse || cursored) ? root.shell.hoverFill(1.5) : root.shell.alpha(root.shell.foreground, .045)
                    border.width: cursored ? 1 : 0
                    border.color: root.shell.hoverEdge(.85)
                    Column {
                        anchors.centerIn: parent; spacing: Style.xxs
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.forecastTab === 1
                                ? (index === 0 ? "TODAY" : Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd").toUpperCase())
                                : (root.selectedDay < 0 && index === 0 ? "NOW" : Qt.formatTime(new Date(modelData.time), "HH:mm"))
                            color: root.shell.alpha(root.shell.foreground, .5)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.icon || "󰖐"; color: root.shell.role("c2", root.shell.foreground); font.family: root.shell.fontFamily; font.pixelSize: Style.display }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.forecastTab === 0 ? root.temp(modelData, "temp") + "\u00b0"
                                : root.temp(modelData, "maxtemp") + "\u00b0 | " + root.temp(modelData, "mintemp") + "\u00b0"
                            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󱢋 " + (modelData.chanceofrain || "0") + "%"; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
                    }
                    MouseArea {
                        id: dayMouse; anchors.fill: parent
                        enabled: root.forecastTab === 1
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.showHours(forecastCard.index)
                    }
                }
                WheelHandler { onWheel: event => {
                    const delta = event.angleDelta.x || event.angleDelta.y
                    if (delta) root.scrollForecast(delta > 0 ? -Style.px(72) : Style.px(72))
                } }
            }
            ForecastArrow {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                glyph: "\u2039"; opacity: forecast.atXBeginning ? .25 : 1
                onActivated: root.scrollForecast(-forecast.width)
            }
            ForecastArrow {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                glyph: "\u203a"; opacity: forecast.atXEnd ? .25 : 1
                onActivated: root.scrollForecast(forecast.width)
            }
        }

        PopupSeparator { shell: root.shell }
        Grid {
            width: parent.width; columns: 2; rowSpacing: 9; columnSpacing: 12
            Repeater {
                model: weatherColumn.expanded ? weatherColumn.metrics : weatherColumn.metrics.slice(0, 4)
                Column {
                    required property var modelData
                    width: (weatherColumn.width - 12) / 2; spacing: 2
                    Text { text: parent.modelData[0]; color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1 }
                    Text { text: parent.modelData[1]; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.subtitle }
                }
            }
        }
        Item {
            width: parent.width; height: Style.px(16)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: weatherColumn.expanded ? "\u25b4  less" : "\u25be  more"
                color: moreMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                MouseArea { id: moreMouse; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: weatherColumn.expanded = !weatherColumn.expanded }
            }
        }
    }
}
