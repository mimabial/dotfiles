import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "vpn"
    contentWidth: 380
    contentHeight: vpnColumn.implicitHeight + padding * 2

    property var status: ({})
    readonly property string state: String(status.state || "disconnected")
    readonly property bool connected: state === "connected"
    readonly property bool busy: state === "connecting" || state === "disconnecting"
    readonly property var features: status.features || []

    property var relays: ({})
    property string browsing: ""          // "", "countries", or a country code
    readonly property var countries: relays.countries || []
    readonly property var currentLocation: relays.current || ({})
    readonly property var openCountry: {
        for (const country of countries) if (country.code === browsing) return country
        return null
    }
    readonly property string locationLabel: {
        const here = currentLocation
        if (!here.kind || here.kind === "any") return "Automatic"
        for (const country of countries) {
            if (country.code !== here.country) continue
            for (const city of country.cities) if (city.code === here.city) return city.name + ", " + country.name
            return country.name
        }
        return String(here.country || "").toUpperCase()
    }

    function relayCount(count) { return count + (count === 1 ? " relay" : " relays") }
    function pinCurrent() {
        // 50 countries in a 208px window: open on the one currently in use
        if (browsing !== "countries") return
        for (let i = 0; i < countries.length; i++)
            if (countries[i].code === currentLocation.country)
                return locationList.positionViewAtIndex(i, ListView.Center)
    }

    function refresh() { if (!statusProc.running) statusProc.running = true }
    function loadRelays() { if (!relayProc.running) relayProc.running = true }
    function setLocation(args) {
        // mullvad reconnects on its own once the constraint changes
        shell.run(["mullvad", "relay", "set", "location"].concat(args))
        browsing = ""
        settle.restart()
        relaySettle.restart()
    }
    function label(value) { return value.charAt(0).toUpperCase() + value.slice(1) }
    function toggle() {
        shell.run(["hyprshell", "waybar.vpn.toggle.sh"])
        // the daemon takes a moment to settle; re-read rather than guess
        settle.restart()
    }

    onBrowsingChanged: pinCurrent()
    onOpenChanged: {
        if (open) { refresh(); loadRelays() }
        else browsing = ""
    }

    property Process statusProc: Process {
        command: ["hyprshell", "system/vpn-status"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.status = JSON.parse(text) || ({}) }
            catch (error) { root.status = ({}) }
        } }
    }
    property Timer poll: Timer { interval: 5000; running: root.open; repeat: true; onTriggered: root.refresh() }
    property Timer settle: Timer { interval: 1200; repeat: false; onTriggered: root.refresh() }
    property Timer relaySettle: Timer { interval: 1200; repeat: false; onTriggered: root.loadRelays() }
    property Process relayProc: Process {
        command: ["hyprshell", "system/vpn-relays"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.relays = JSON.parse(text) || ({}) }
            catch (error) { root.relays = ({}) }
            root.pinCurrent()
        } }
    }

    component InfoPair: Row {
        property string label: ""
        property string value: ""
        visible: value !== ""
        width: parent.width; spacing: Style.lg
        Text { id: pairLabel; text: parent.label; color: root.shell.alpha(root.shell.foreground, .6); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        Item { width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.implicitWidth - parent.spacing * 2); height: 1 }
        Text { id: pairValue; text: parent.value; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    }

    Column {
        id: vpnColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupSection { shell: root.shell; text: "VPN" }
        Column {
            width: parent.width; spacing: Style.xxs
            Text {
                width: parent.width
                text: root.status.provider && root.status.provider !== "none"
                    ? root.label(String(root.status.provider))
                    : "No VPN client detected"
                color: root.shell.foreground; font.family: root.shell.fontFamily
                font.pixelSize: Style.title; font.bold: true
            }
            Text {
                width: parent.width
                text: root.label(root.state)
                color: root.connected ? root.shell.role("success", root.shell.foreground)
                    : root.busy ? root.shell.role("warning", root.shell.foreground)
                    : root.shell.alpha(root.shell.foreground, .6)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
        }

        Column {
            visible: root.connected
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "TUNNEL" }
            InfoPair { label: "Relay"; value: String(root.status.relay || "") }
            InfoPair { label: "Location"; value: String(root.status.location || "") }
            InfoPair { label: "Exit IP"; value: String(root.status.address || "") }
            InfoPair { label: "Interface"; value: String(root.status.iface || "") }
            InfoPair { label: "Endpoint"; value: String(root.status.endpoint || "") }
        }

        Column {
            visible: root.features.length > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "FEATURES" }
            Repeater {
                model: root.features
                Text {
                    required property var modelData
                    width: vpnColumn.width; text: "•  " + modelData
                    color: root.shell.alpha(root.shell.foreground, .8)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
        }

        Column {
            visible: root.countries.length > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "LOCATION" }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰍎"
                title: root.locationLabel
                detail: root.browsing === "" ? "Tap to change" : "Choose a location"
                active: root.browsing !== ""
                onClicked: root.browsing = root.browsing === "" ? "countries" : ""
            }
            ListView {
                id: locationList
                visible: root.browsing !== ""
                width: parent.width
                height: Math.min(contentHeight, 208)
                clip: true; spacing: Style.xxs
                model: root.openCountry ? root.openCountry.cities : root.countries
                header: Column {
                    width: ListView.view.width; spacing: Style.xxs
                    PopupRow {
                        visible: root.openCountry === null
                        width: parent.width; shell: root.shell
                        icon: "󰇧"; title: "Automatic"; detail: "Closest relay"
                        active: root.currentLocation.kind === "any"
                        onClicked: root.setLocation(["any"])
                    }
                    PopupRow {
                        visible: root.openCountry !== null
                        width: parent.width; shell: root.shell
                        icon: "󰁍"; title: "All countries"; detail: "Back"
                        onClicked: root.browsing = "countries"
                    }
                    PopupRow {
                        visible: root.openCountry !== null
                        width: parent.width; shell: root.shell
                        icon: " "
                        title: root.openCountry ? "Anywhere in " + root.openCountry.name : ""
                        detail: root.openCountry ? root.relayCount(root.openCountry.relays) : ""
                        active: root.currentLocation.kind === "country"
                        onClicked: root.setLocation([root.openCountry.code])
                    }
                }
                delegate: PopupRow {
                    required property var modelData
                    readonly property bool current: root.openCountry
                        ? modelData.code === root.currentLocation.city
                        : modelData.code === root.currentLocation.country
                    width: ListView.view.width; shell: root.shell
                    // a blank icon keeps every row's text on the same left edge
                    icon: current ? "󰍎" : " "
                    title: modelData.name
                    detail: root.relayCount(modelData.relays)
                    active: current
                    onClicked: {
                        if (root.openCountry) root.setLocation([root.openCountry.code, modelData.code])
                        else root.browsing = modelData.code
                    }
                }
            }
        }

        Column {
            visible: root.status.provider !== undefined && root.status.provider !== "none"
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: root.connected ? "󰳌" : "󱦛"
                title: root.busy ? root.label(root.state) + "…" : root.connected ? "Disconnect" : "Connect"
                detail: root.status.relay ? String(root.status.relay) : ""
                active: root.connected
                enabled: !root.busy
                onClicked: root.toggle()
            }
        }
    }
}
