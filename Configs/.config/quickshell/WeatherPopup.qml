import QtQuick
import QtQuick.Controls
import Quickshell.Io

PopupCard {
    id: root
    popupName: "weather"
    contentWidth: 420
    contentHeight: weatherColumn.implicitHeight + 32
    readonly property var conditions: Weather.data.current_condition ? Weather.data.current_condition[0] : ({})
    readonly property var days: Weather.data.weather ? Weather.data.weather.slice(0, 3) : []
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
    // set when Enter arrived before the search returned
    property bool pendingAccept: false

    function readOverride() { if (!overrideProc.running) overrideProc.running = true }
    function searchCities(query) {
        suggestions = []
        if (query.trim() === "") return
        searchProc.command = ["hyprshell", "weather", "--search", query.trim()]
        searchProc.running = true
    }
    function pick(place) {
        const label = place.name + (place.country ? ", " + place.country : "")
        shell.run(["hyprshell", "util/weather-location", "--pin",
                   place.latitude + "," + place.longitude, label])
        suggestions = []
        cityField.text = ""
        searching = false
        overrideSettle.restart()
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
    // typing shouldn't fire a request per keystroke
    property Timer searchDebounce: Timer {
        interval: 350
        onTriggered: root.searchCities(cityField.text)
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

    property Timer overrideSettle: Timer { interval: 900; onTriggered: root.readOverride() }

    // the reading itself comes from the Weather singleton's file watch; this
    // only needs to learn whether a city is pinned
    onOpenChanged: {
        if (open) readOverride()
        else { searching = false; cityField.text = "" }
    }

    property Process overrideProc: Process {
        command: ["hyprshell", "util/weather-location"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.override = String(text).trim() }
    }

    function setLocation(name) {
        shell.run(["hyprshell", "util/weather-location", name])
        overrideSettle.restart()
        // the singleton watches the cache file, so it picks the new place up
        // on its own once the fetch lands
    }

    function value(list, fallback) { return list && list.length ? list[0].value : fallback }
    function location() { const area = Weather.data.nearest_area; return area && area.length ? value(area[0].areaName, "") + ", " + value(area[0].country, "") : "" }

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
        spacing: 14
        Item {
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
                font.family: root.shell.fontFamily; font.pixelSize: 92
            }
            Column {
                    id: heroStack
                    anchors.left: heroIcon.right; anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter; spacing: 2
                    Text {
                        text: root.temp(root.conditions, "FeelsLike") + root.degrees
                        color: tempMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: 32; font.bold: true
                        MouseArea {
                            id: tempMouse; anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleUnits()
                        }
                    }
                    Text {
                        text: root.value(root.conditions.weatherDesc, "Weather")
                        color: root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: 13
                    }
                    Item {
                        // from wherever the stack begins out to the popup's right
                        // edge, so the search glyph sits flush right
                        width: heroActions.x - heroStack.x - 10; height: 18

                        Text {
                            id: locationLabel
                            visible: !root.searching
                            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                            text: root.location()
                            color: (actionMouse.containsMouse || locationMouse.containsMouse)
                                ? root.shell.role("hvr_fg", root.shell.foreground)
                                : root.shell.alpha(root.shell.foreground, .55)
                            font.family: root.shell.fontFamily; font.pixelSize: 10
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
                            height: 18
                            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
                            placeholderText: "City name \u2014 Empty to auto-detect"
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: 10
                            background: null
                            onTextChanged: if (root.searching) { root.pendingAccept = false; root.searchDebounce.restart() }
                            onAccepted: {
                                if (text === "") { root.setLocation("--clear"); root.searching = false }
                                else if (root.suggestions.length > 0) root.pick(root.suggestions[0])
                                // typed and hit Enter before the debounce fired:
                                // run the search now and take the first result
                                else { root.pendingAccept = true; root.searchCities(text) }
                            }
                            Keys.onEscapePressed: { text = ""; root.searching = false }
                        }

                    }
            }
            // units, refresh and search share one column, so the hero has a
            // single place to look for actions
            Column {
                id: heroActions
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.imperial ? "󰔅" : "󰔄"
                    color: unitsMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.alpha(root.shell.foreground, .55)
                    font.family: root.shell.fontFamily; font.pixelSize: 14
                    MouseArea { id: unitsMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleUnits() }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "󰑐"
                    color: refreshMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.alpha(root.shell.foreground, .55)
                    font.family: root.shell.fontFamily; font.pixelSize: 14
                    MouseArea { id: refreshMouse; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.shell.run(["hyprshell", "weather", "--force", "--alt"]) }
                }
                Text {
                    id: actionGlyph
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.searching ? "󰅖" : "󰍉"
                    color: actionMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.alpha(root.shell.foreground, .55)
                    font.family: root.shell.fontFamily; font.pixelSize: 14
                    MouseArea {
                        id: actionMouse; anchors.fill: parent; anchors.margins: -6
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.searching) { cityField.text = ""; root.searching = false }
                            else root.openSearch()
                        }
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
                    width: parent.width; height: 26; radius: root.shell.rounding
                    color: pickMouse.containsMouse ? root.shell.alpha(root.shell.role("hvr_bg", root.shell.accent), .18) : "transparent"
                    Text {
                        anchors.left: parent.left; anchors.leftMargin: 6
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
            anchors.horizontalCenter: parent.horizontalCenter; spacing: 28
            Repeater {
                model: root.days
                Row {
                    required property var modelData
                    spacing: 7
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.icon || "󰖐"
                        color: root.shell.role("c2", root.shell.foreground)
                        font.family: root.shell.fontFamily; font.pixelSize: 22
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter; spacing: 1
                        Text {
                            text: Qt.formatDate(new Date(parent.parent.modelData.date + "T12:00:00"), "ddd").toUpperCase()
                            color: root.shell.alpha(root.shell.foreground, .5)
                            font.family: root.shell.fontFamily; font.pixelSize: 10; font.bold: true
                        }
                        Text {
                            text: root.temp(parent.parent.modelData, "maxtemp") + "\u00b0 | " + root.temp(parent.parent.modelData, "mintemp") + "\u00b0"
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: 13
                        }
                    }
                }
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
                    Text { text: parent.modelData[0]; color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: 9; font.bold: true; font.letterSpacing: 1 }
                    Text { text: parent.modelData[1]; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 13 }
                }
            }
        }
        Item {
            width: parent.width; height: 16
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: weatherColumn.expanded ? "\u25b4  less" : "\u25be  more"
                color: moreMouse.containsMouse ? root.shell.role("hvr_fg", root.shell.foreground) : root.shell.alpha(root.shell.foreground, .5)
                font.family: root.shell.fontFamily; font.pixelSize: 10
                MouseArea { id: moreMouse; anchors.fill: parent; anchors.margins: -8; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: weatherColumn.expanded = !weatherColumn.expanded }
            }
        }
    }
}
