pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell.Io
import "CalendarMath.js" as CalendarMath

PopupCard {
    id: root
    popupName: "weather"
    keyboardHint: searching ? "Type city · ↑↓ suggestions · Enter select · Esc" : "←→ forecast · ↑↓ day · U units · R refresh · S city · Esc"
    contentWidth: Style.px(420)
    contentHeight: weatherColumn.implicitHeight + 32
    readonly property var conditions: Weather.data.current_condition ? Weather.data.current_condition[0] : ({})
    readonly property var days: Weather.data.weather ? Weather.data.weather.slice(0, 7) : []
    property int selectedDay: -1
    readonly property var hours: {
        if (selectedDay >= 0 && selectedDay < days.length) return days[selectedDay].hourly || []
        const upcoming = [], cutoff = Date.now() - CalendarMath.MS_PER_HOUR
        for (const day of days) for (const hour of day.hourly || [])
            if (new Date(hour.time).getTime() >= cutoff) upcoming.push(hour)
        return upcoming.slice(0, 12)
    }
    readonly property string hourlyLabel: selectedDay < 0 || selectedDay >= days.length ? "HOURLY"
        : selectedDay === 0 ? "TODAY"
        : Qt.formatDate(new Date(days[selectedDay].date + "T12:00:00"), "ddd").toUpperCase()
    property string forecastView: "hourly"
    readonly property var cards: forecastView === "hourly" ? hours : days
    property int cardIndex: -1
    function showHours(day) {
        selectedDay = day
        forecastView = "hourly"
        cardIndex = -1
        forecast.positionViewAtBeginning()
    }
    function showDays() {
        const from = selectedDay
        selectedDay = -1
        forecastView = "daily"
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
    function drillIn() {
        if (forecastView !== "daily") return false
        showHours(cardIndex < 0 ? 0 : cardIndex)
        return true
    }
    function drillOut() {
        if (forecastView !== "hourly") return false
        showDays()
        return true
    }

    function handleKey(event) {
        if (event.key === Qt.Key_Escape && searching) { cityField.text = ""; searching = false; return true }
        if (searching) return false
        switch (event.key) {
        case Qt.Key_Left:
        case Qt.Key_H:      moveCard(-1); return true
        case Qt.Key_Right:
        case Qt.Key_L:      moveCard(1); return true
        case Qt.Key_Home:   moveCardTo(0); return true
        case Qt.Key_End:    moveCardTo(cards.length - 1); return true
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
        case Qt.Key_Escape: if (selectedDay >= 0) { showDays(); return true } break
        }
        return defaultKey(event)
    }
    readonly property bool imperial: Weather.imperial
    readonly property string degrees: imperial ? "\u00b0F" : "\u00b0C"
    readonly property string windUnit: imperial ? " mph" : " km/h"
    function temp(source, key) { return (source && source[key + (imperial ? "F" : "C")]) || "--" }
    function wind() { return (conditions[imperial ? "windspeedMiles" : "windspeedKmph"] || "--") + windUnit }
    function toggleUnits() { Weather.savePrefs({imperial: !imperial}) }

    property bool settingsOpen: false
    readonly property var readoutLabels: ({ temp: "Temperature", minmax: "High | low", sunrise: "Sunrise", sunset: "Sunset", rain: "Rain chance", wind: "Wind", humidity: "Humidity" })
    readonly property var shownReadouts: Weather.readouts()
    readonly property var orderedReadouts: shownReadouts.concat(Object.keys(readoutLabels).filter(id => !shownReadouts.includes(id)))
    function setReadouts(list) { Weather.savePrefs({readouts: list}) }
    function toggleReadout(id) { setReadouts(shownReadouts.includes(id) ? shownReadouts.filter(shown => shown !== id) : shownReadouts.concat([id])) }
    function moveReadout(id, step) {
        const list = shownReadouts.filter(shown => shown !== id)
        list.splice(shownReadouts.indexOf(id) + step, 0, id)
        setReadouts(list)
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
    property string pinnedCity: ""

    property var suggestions: []
    property int suggestionIndex: 0
    onSuggestionsChanged: suggestionIndex = 0
    function moveSuggestion(step) {
        if (!suggestions.length) return
        suggestionIndex = Math.max(0, Math.min(suggestions.length - 1, suggestionIndex + step))
    }
    property bool acceptPendingCityResults: false
    property string pendingCityQuery: ""
    property string activeCityQuery: ""
    onSearchingChanged: if (!searching) { pendingCityQuery = ""; acceptPendingCityResults = false }

    function readPinnedCity() { if (!pinnedCityProcess.running) pinnedCityProcess.running = true }
    function searchCities(query) {
        pendingCityQuery = query.trim()
        if (pendingCityQuery === "") suggestions = []
        startCitySearch()
    }
    function startCitySearch() {
        if (citySearchProcess.running || pendingCityQuery === "") return
        activeCityQuery = pendingCityQuery
        citySearchProcess.command = [root.shell.home + "/.local/lib/hypr/util/weather-status.py", "--search", pendingCityQuery]
        citySearchProcess.running = true
    }
    function pick(place) {
        const label = place.name + (place.country ? ", " + place.country : "")
        shell.run(["hyprshell", "util/weather-location", "--pin",
                   place.latitude + "," + place.longitude, label], root.readPinnedCity)
        suggestions = []
        cityField.text = ""
        searching = false
    }

    property Process citySearchProcess: Process {
        onRunningChanged: if (!running && root.activeCityQuery !== root.pendingCityQuery) Qt.callLater(root.startCitySearch)
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            if (!root.searching || root.activeCityQuery !== root.pendingCityQuery) return
            try { root.suggestions = JSON.parse(text) || [] }
            catch (error) { root.suggestions = [] }
            if (root.acceptPendingCityResults) {
                root.acceptPendingCityResults = false
                if (root.suggestions.length > 0) root.pick(root.suggestions[0])
                else { root.cityFieldText(""); root.searching = false }
            }
        } }
    }
    function cityFieldText(value) { cityField.text = value }
    function cityName() {
        const area = Weather.data.nearest_area
        return area && area.length ? value(area[0].areaName, pinnedCity) : pinnedCity
    }
    function openSearch() {
        searching = true
        cityField.text = pinnedCity === "" ? "" : cityName()
        cityField.forceActiveFocus()
        if (pinnedCity !== "") cityField.selectAll()
    }

    onOpenChanged: {
        if (open) readPinnedCity()
        else { searching = false; settingsOpen = false; cityField.text = ""; selectedDay = -1; cardIndex = -1; forecastView = "hourly" }
    }

    property Process pinnedCityProcess: Process {
        command: ["hyprshell", "util/weather-location"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.pinnedCity = String(text).trim() }
    }

    function setLocation(name) {
        shell.run(["hyprshell", "util/weather-location", name], root.readPinnedCity)
    }

    function value(list, fallback) { return list && list.length ? list[0].value : fallback }

    component GlyphButton: Text {
        required property string glyph
        text: glyph
        color: root.shell.alpha(root.shell.foreground, glyphMouse.containsMouse ? 1 : .5)
        font.family: root.shell.fontFamily; font.pixelSize: Style.display
        signal activated
        MouseArea {
            id: glyphMouse; anchors.fill: parent; anchors.margins: -6
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.searching
        onClicked: { cityField.text = ""; root.searching = false }
    }

    Column {
        id: weatherColumn
        anchors.left: parent.left; anchors.right: parent.right
        spacing: Style.sectionGap
        Item {
            id: hero
            width: parent.width
            height: Math.max(heroLeft.implicitHeight, heroRight.implicitHeight + heroRight.anchors.topMargin)
            Row {
                id: heroLeft
                anchors.left: parent.left; anchors.leftMargin: Style.px(16)
                anchors.verticalCenter: parent.verticalCenter; spacing: Style.px(16)
                Text {
                    anchors.verticalCenter: parent.verticalCenter; anchors.verticalCenterOffset: Style.px(5)
                    text: String(Weather.output.text).trim().split(/\s+/)[0] || "󰖐"
                    color: root.shell.role("c2", root.shell.foreground)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.typePx(4.5)
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter; spacing: Style.xxs
                    Text {
                        id: heroTemp
                        text: root.temp(root.conditions, "temp_")
                        color: tempMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: Style.typePx(4); font.bold: true
                        MouseArea { id: tempMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleUnits() }
                    }
                    Text {
                        anchors.top: heroTemp.top; anchors.topMargin: Style.px(10)
                        text: root.degrees
                        color: root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: Style.typePx(1.75)
                    }
                }
            }
            Column {
                anchors.top: parent.top; anchors.right: parent.right; spacing: Style.md
                GlyphButton { glyph: "\uf423"; onActivated: root.settingsOpen = !root.settingsOpen }
                GlyphButton { glyph: "󰑐"; onActivated: root.shell.run(["hyprshell", "weather", "--force", "--alt"]) }
            }
            Column {
                id: heroRight
                width: Math.max(heroStats.implicitWidth, root.searching ? Style.px(230) : Style.px(150))
                anchors.right: parent.right; anchors.rightMargin: Style.px(28)
                anchors.top: parent.top; anchors.topMargin: Style.px(8)
                spacing: Style.px(12)
                Item {
                    width: parent.width; height: cityRow.implicitHeight
                    Row {
                        id: cityRow
                        visible: !root.searching; spacing: Style.px(6)
                        Repeater {
                            model: ["\uf450", root.cityName().toUpperCase()]
                            Text {
                                required property string modelData
                                text: modelData
                                color: cityMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.mutedText
                                font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.letterSpacing: 1
                            }
                        }
                    }
                    MouseArea { id: cityMouse; visible: !root.searching; anchors.fill: cityRow; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.openSearch() }
                    TextField {
                        id: cityField
                        visible: root.searching
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                        placeholderText: "City name — Empty to auto-detect"
                        color: root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        background: null
                        onTextChanged: if (root.searching) { root.acceptPendingCityResults = false; root.searchCities(text) }
                        onAccepted: {
                            if (text === "") { root.setLocation("--clear"); root.searching = false }
                            else if (!root.citySearchProcess.running && root.activeCityQuery === text.trim() && root.suggestions.length > 0) root.pick(root.suggestions[root.suggestionIndex])
                            else { root.acceptPendingCityResults = true; root.searchCities(text) }
                        }
                        Keys.onDownPressed: root.moveSuggestion(1)
                        Keys.onUpPressed: root.moveSuggestion(-1)
                        Keys.onEscapePressed: { text = ""; root.searching = false }
                    }
                }
                Row {
                    id: heroStats
                    spacing: Style.px(20)
                    Repeater {
                        model: [
                            ["FEELS", root.temp(root.conditions, "FeelsLike") + root.degrees],
                            ["WIND", root.wind()],
                            ["HUMID", (root.conditions.humidity || "--") + "%"]
                        ]
                        Column {
                            required property var modelData
                            spacing: Style.px(5)
                            Text { text: parent.modelData[0]; color: root.shell.faintText; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.letterSpacing: 1 }
                            Text { text: parent.modelData[1]; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.typePx(1.17) }
                        }
                    }
                }
            }
        }
        property bool expanded: false
        readonly property var metrics: [
            ["MAX|MIN", root.today.maxtempC ? root.temp(root.today, "maxtemp") + "\u00b0 | " + root.temp(root.today, "mintemp") + "\u00b0" : "--"],
            ["RAIN", (root.days.length ? root.days[0].chanceofrain : "--") + "%"],
            ["SUNRISE", root.astronomy.sunrise || "--"],
            ["SUNSET", root.astronomy.sunset || "--"],
            ["DEW POINT", root.conditions.DewPointC ? root.temp(root.conditions, "DewPoint") + root.degrees : "--"],
            ["VISIBILITY", root.distance(root.conditions.visibility)],
            ["CLOUD", (root.conditions.cloudcover || "--") + "%"],
            ["UV", root.conditions.uvIndex || "--"],
            ["PRESSURE", root.pressure(root.conditions.pressure)]
        ]

        Column {
            visible: root.settingsOpen
            width: parent.width
            Repeater {
                model: root.orderedReadouts
                Item {
                    id: readoutRow
                    required property string modelData
                    readonly property int position: root.shownReadouts.indexOf(modelData)
                    width: parent.width; height: Style.controlHeight
                    ToggleSwitch {
                        id: readoutSwitch
                        shell: root.shell; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        checked: readoutRow.position >= 0
                        enabled: !checked || root.shownReadouts.length > 1
                        onToggled: root.toggleReadout(readoutRow.modelData)
                    }
                    Text {
                        anchors.left: readoutSwitch.right; anchors.leftMargin: Style.px(12); anchors.verticalCenter: parent.verticalCenter
                        text: root.readoutLabels[readoutRow.modelData]
                        color: root.shell.foreground; opacity: readoutRow.position >= 0 ? 1 : .5
                        font.family: root.shell.fontFamily; font.pixelSize: Style.body
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: Style.lg
                        visible: readoutRow.position >= 0
                        GlyphButton { glyph: "󰁝"; enabled: readoutRow.position > 0; opacity: enabled ? 1 : .25; onActivated: root.moveReadout(readoutRow.modelData, -1) }
                        GlyphButton { glyph: "󰁅"; enabled: readoutRow.position < root.shownReadouts.length - 1; opacity: enabled ? 1 : .25; onActivated: root.moveReadout(readoutRow.modelData, 1) }
                    }
                }
            }
        }
        Column {
            visible: root.searching && root.suggestions.length > 0
            width: parent.width; spacing: 2
            Repeater {
                model: root.suggestions
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool cursored: root.suggestionIndex === index
                    width: parent.width; height: Style.popupRowHeight; radius: root.shell.rounding
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
            PopupTab { width: (parent.width - parent.spacing) / 2; shell: root.shell; text: root.hourlyLabel; selected: root.forecastView === "hourly"; onClicked: root.showHours(-1) }
            PopupTab { width: (parent.width - parent.spacing) / 2; shell: root.shell; text: "Daily"; selected: root.forecastView === "daily"; onClicked: root.showDays() }
        }
        Item {
            width: parent.width; height: Style.px(88)
            ListView {
                id: forecast
                anchors.fill: parent
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
                            text: root.forecastView === "daily"
                                ? (forecastCard.index === 0 ? "TODAY" : Qt.formatDate(new Date(forecastCard.modelData.date + "T12:00:00"), "ddd").toUpperCase())
                                : (root.selectedDay < 0 && forecastCard.index === 0 ? "NOW" : Qt.formatTime(new Date(forecastCard.modelData.time), "HH:mm"))
                            color: root.shell.mutedText
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: forecastCard.modelData.icon || "󰖐"; color: root.shell.role("c2", root.shell.foreground); font.family: root.shell.fontFamily; font.pixelSize: Style.display }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: root.forecastView === "hourly" ? root.temp(forecastCard.modelData, "temp") + "\u00b0"
                                : root.temp(forecastCard.modelData, "maxtemp") + "\u00b0 | " + root.temp(forecastCard.modelData, "mintemp") + "\u00b0"
                            color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󱢋 " + (forecastCard.modelData.chanceofrain || "0") + "%"; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
                    }
                    MouseArea {
                        id: dayMouse; anchors.fill: parent
                        enabled: root.forecastView === "daily"
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: root.showHours(forecastCard.index)
                    }
                }
                WheelHandler { onWheel: event => {
                    const delta = event.angleDelta.x || event.angleDelta.y
                    if (delta) root.scrollForecast(delta > 0 ? -Style.px(72) : Style.px(72))
                } }
            }
            GlyphButton {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                glyph: "\u2039"; opacity: forecast.atXBeginning ? .25 : 1
                onActivated: root.scrollForecast(-forecast.width)
            }
            GlyphButton {
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
                    Text { text: parent.modelData[0]; color: root.shell.faintText; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: 1 }
                    Text { text: parent.modelData[1]; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.subtitle }
                }
            }
        }
        Item {
            width: parent.width; height: Style.px(16)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: weatherColumn.expanded ? "\u25b4  less" : "\u25be  more"
                color: moreMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                MouseArea { id: moreMouse; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: weatherColumn.expanded = !weatherColumn.expanded }
            }
        }
    }
}
