pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

PopupCard {
    id: root
    popupName: "vpn"
    contentWidth: Style.px(380)
    contentHeight: vpnColumn.implicitHeight + padding * 2

    property string backend: "mullvad"
    property var status: ({provider: "mullvad", state: "checking"})
    property var nmStatus: ({available: false, profiles: [], connected: false, active: null})
    property string pendingAction: ""
    property string nmPending: ""
    property string statusError: ""
    property string actionError: ""
    property string nmError: ""
    property string settingsError: ""
    readonly property var nmProfiles: nmStatus.profiles || []
    readonly property var viewStatus: backend === "networkmanager"
        ? ({provider: "networkmanager", state: nmPending || (nmStatus.connected ? "connected" : "disconnected"), relay: nmStatus.active ? nmStatus.active.name : "", features: []}) : status
    readonly property string state: backend === "networkmanager" ? String(viewStatus.state || "checking") : pendingAction || String(viewStatus.state || "checking")
    readonly property bool connected: viewStatus.state === "connected"
    readonly property bool busy: backend === "networkmanager" ? nmActionProc.running : pendingAction !== "" || ["connecting", "disconnecting"].includes(String(status.state))
    readonly property bool blocked: backend === "mullvad" && (status.state === "blocked" || status.lockedDown === true)
    readonly property var features: viewStatus.features || []
    readonly property string notice: backend === "networkmanager" ? nmError : actionError || settingsError || statusError

    property var relays: ({})
    property string filter: ""
    property string browsing: ""          // "", "countries", or a country code
    property int resultIndex: -1
    readonly property int resultOffset: filter === "" ? 1 : 0
    readonly property var countries: relays.countries || []
    readonly property var currentLocation: relays.current || ({})
    property var settings: ({})
    property bool settingsLoaded: false
    property bool settingsOpen: false
    property bool ipCopied: false
    readonly property var openCountry: {
        for (const country of countries) if (country.code === browsing) return country
        return null
    }
    readonly property var locationRows: {
        const needle = filter.trim().toLowerCase(), rows = []
        if (openCountry) {
            for (const city of openCountry.cities)
                if (!needle || (city.name + " " + city.code).toLowerCase().includes(needle)) rows.push(city)
            return rows
        }
        if (!needle) return countries
        for (const country of countries) {
            if ((country.name + " " + country.code).toLowerCase().includes(needle)) rows.push(country)
            for (const city of country.cities)
                if ((city.name + " " + city.code).toLowerCase().includes(needle))
                    rows.push({name: city.name, code: city.code, relays: city.relays,
                               countryCode: country.code, countryName: country.name})
        }
        return rows
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
    function feature(value) { return String(value).replace(/([a-z0-9])([A-Z])/g, "$1 $2") }
    function kind(value) { return ({wireguard: "WireGuard", openvpn: "OpenVPN", openconnect: "OpenConnect", vpnc: "VPNC"})[value] || value }
    function selectBackend(name) { backend = name; browsing = ""; filter = ""; settingsOpen = false; cursorIndex = -1 }
    function pinCurrent() {
        // 50 countries in a 208px window: open on the one currently in use
        if (browsing !== "countries") return
        for (let i = 0; i < countries.length; i++)
            if (countries[i].code === currentLocation.country)
                return locationList.positionViewAtIndex(i, ListView.Center)
    }
    function moveResult(step) {
        const count = locationRows.length + resultOffset
        if (!count) return
        resultIndex = resultIndex < 0 ? (step > 0 ? 0 : count - 1) : (resultIndex + step + count) % count
        if (resultIndex < resultOffset) locationList.positionViewAtBeginning()
        else locationList.positionViewAtIndex(resultIndex - resultOffset, ListView.Contain)
    }
    function activateResult() {
        const index = Math.max(0, resultIndex)
        if (resultOffset && index === 0) setLocation(openCountry ? [openCountry.code] : ["any"])
        else chooseLocation(locationRows[index - resultOffset])
    }
    function chooseLocation(row) {
        if (!row) return
        if (row.countryCode !== undefined) setLocation([row.countryCode, row.code])
        else if (openCountry) setLocation([openCountry.code, row.code])
        else { filter = ""; browsing = row.code; resultIndex = 0 }
    }

    function refresh(force) {
        if (!statusProc.running) statusProc.running = true
        if (!nmStatusProc.running) nmStatusProc.running = true
        if (force) { loadRelays(true); if (settingsOpen) loadSettings() }
    }
    function loadRelays(force) { if ((force || countries.length === 0) && !relayProc.running) relayProc.running = true }
    function loadSettings() {
        if (settingsProc.running) return
        settingsProc.action = "load"
        settingsProc.command = ["hyprshell", "system/vpn-status", "--settings"]
        settingsProc.running = true
    }
    function toggleSettings() {
        settingsOpen = !settingsOpen
        if (settingsOpen) { browsing = ""; filter = ""; loadSettings() }
    }
    function applyStatus(raw) {
        try {
            const next = JSON.parse(raw) || ({})
            if (next.valid === false) { statusError = "Status unavailable — showing last reading"; return }
            status = next; statusError = ""
        } catch (error) { statusError = "Status unavailable — showing last reading" }
    }
    function applyNmStatus(raw) {
        try { const next = JSON.parse(raw) || ({}); if (next.valid === false) { nmError = next.error || "NetworkManager status unavailable"; return }; nmStatus = next; nmError = "" }
        catch (error) { nmError = "NetworkManager status unavailable" }
    }
    function nmAction(action, profile) {
        if (!profile || nmActionProc.running) return
        nmError = ""; nmPending = action === "connect" ? "connecting" : "disconnecting"
        nmActionProc.command = ["hyprshell", "system/vpn-networkmanager", "--" + action, profile.uuid]
        nmActionProc.running = true
    }
    function setLocation(args) {
        if (locationProc.running) return
        actionError = ""; pendingAction = "changing location"
        locationProc.selected = args
        locationProc.command = ["mullvad", "relay", "set", "location"].concat(args)
        locationProc.running = true
        browsing = ""; filter = ""
    }
    function label(value) { return value.charAt(0).toUpperCase() + value.slice(1) }
    function toggle() {
        if (backend === "networkmanager") {
            if (connected) nmAction("disconnect", nmStatus.active)
            else if (nmProfiles.length === 1) nmAction("connect", nmProfiles[0])
            return
        }
        if (busy || actionProc.running) return
        actionError = ""; pendingAction = connected ? "disconnecting" : "connecting"
        actionProc.running = true
    }
    function setSetting(name, enabled) {
        if (settingsProc.running) return
        settingsError = ""; settingsProc.action = name
        settingsProc.command = ["hyprshell", "system/vpn-status", "--set", name, enabled ? "on" : "off"]
        settingsProc.running = true
    }
    function copyIp() {
        if (!status.address) return
        shell.run(["wl-copy", String(status.address)])
        ipCopied = true; copiedTimer.restart()
    }
    function handleKey(event) {
        if (browsing !== "") {
            if (event.key === Qt.Key_Escape) {
                if (filter !== "") filter = ""
                else if (openCountry) browsing = "countries"
                else browsing = ""
                return true
            }
            if (event.key === Qt.Key_Down) { moveResult(1); return true }
            if (event.key === Qt.Key_Up) { moveResult(-1); return true }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activateResult(); return true }
            if (event.key === Qt.Key_Backspace) { filter = filter.slice(0, -1); return true }
            if (event.text === "/") return true
            if (event.text && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                filter += event.text; return true
            }
            return defaultKey(event)
        }
        const key = String(event.text || "").toLowerCase()
        if (key === "/" && backend === "mullvad" && countries.length) { settingsOpen = false; browsing = "countries"; return true }
        if (key === "r") { refresh(true); return true }
        if (key === "d") { if (connected) toggle(); return true }
        return defaultKey(event)
    }

    onBrowsingChanged: { cursorIndex = -1; resultIndex = -1; pinCurrent() }
    onFilterChanged: { cursorIndex = -1; resultIndex = -1 }
    onOpenChanged: {
        if (open) { refresh(); loadRelays(); if (settingsOpen) loadSettings() }
        else { browsing = ""; filter = "" }
    }

    property Process statusProc: Process {
        command: ["hyprshell", "system/vpn-status"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
    }
    property Process nmStatusProc: Process {
        command: ["hyprshell", "system/vpn-networkmanager"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyNmStatus(text) }
    }
    property Timer poll: Timer { interval: 5000; running: root.open; repeat: true; onTriggered: root.refresh() }
    property Timer settle: Timer { interval: 1200; repeat: false; onTriggered: root.refresh() }
    property Process relayProc: Process {
        command: ["hyprshell", "system/vpn-relays"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { const next = JSON.parse(text) || ({}); if (next.countries && next.countries.length) root.relays = next }
            catch (error) {}
            root.pinCurrent()
        } }
    }
    property Process actionProc: Process {
        command: ["hyprshell", "quickshell/vpn-toggle"]
        stderr: StdioCollector { id: actionStderr; waitForEnd: true }
        onExited: (code, status) => {
            root.pendingAction = ""
            if (code !== 0) root.actionError = String(actionStderr.text).trim() || "VPN action failed"
            root.settle.restart()
        }
    }
    property Process nmActionProc: Process {
        stderr: StdioCollector { id: nmActionStderr; waitForEnd: true }
        onExited: (code, status) => {
            root.nmPending = ""
            if (code !== 0) root.nmError = String(nmActionStderr.text).trim() || "NetworkManager action failed"
            root.settle.restart()
        }
    }
    property Process locationProc: Process {
        property var selected: []
        stderr: StdioCollector { id: locationStderr; waitForEnd: true }
        onExited: (code, status) => {
            root.pendingAction = ""
            if (code === 0) {
                const args = selected, here = !args.length || args[0] === "any" ? ({kind: "any"})
                    : args.length > 1 ? ({kind: "city", country: args[0], city: args[1]})
                    : ({kind: "country", country: args[0]})
                root.relays = ({countries: root.countries, current: here})
            } else root.actionError = String(locationStderr.text).trim() || "Could not change location"
            root.settle.restart()
        }
    }
    property Process settingsProc: Process {
        property string action: ""
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.settings = JSON.parse(text) || ({}); root.settingsLoaded = true; root.settingsError = "" }
            catch (error) {}
        } }
        stderr: StdioCollector { id: settingsStderr; waitForEnd: true }
        onExited: (code, status) => {
            if (code !== 0) root.settingsError = String(settingsStderr.text).trim() || "Could not update Mullvad settings"
            action = ""
        }
    }
    property Timer copiedTimer: Timer { interval: 1400; onTriggered: root.ipCopied = false }

    component InfoPair: Item {
        property string label: ""
        property string value: ""
        property bool interactive: false
        visible: value !== ""
        signal clicked
        width: parent.width; height: pair.implicitHeight
        Row {
            id: pair; width: parent.width; spacing: Style.lg
            Text { id: pairLabel; text: parent.parent.label; color: root.shell.alpha(root.shell.foreground, .6); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
            Item { width: Math.max(0, parent.width - pairLabel.implicitWidth - pairValue.implicitWidth - parent.spacing * 2); height: 1 }
            Text { id: pairValue; text: parent.parent.value; color: pairMouse.containsMouse ? root.shell.accent : root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        }
        MouseArea { id: pairMouse; anchors.fill: parent; enabled: parent.interactive; hoverEnabled: enabled; cursorShape: Qt.PointingHandCursor; onClicked: parent.clicked() }
    }

    component SettingRow: Item {
        required property string setting
        required property string label
        required property string detail
        required property bool checked
        width: vpnColumn.width; height: row.implicitHeight; enabled: !root.settingsProc.running
        PopupRow { id: row; anchors.fill: parent; shell: root.shell; title: parent.label; detail: parent.detail; active: parent.checked; rightInset: settingSwitch.width + Style.lg; onClicked: root.setSetting(parent.setting, !parent.checked) }
        ToggleSwitch { id: settingSwitch; anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter; shell: root.shell; checked: parent.checked; onToggled: root.setSetting(parent.setting, !parent.checked) }
    }
    component BackendTab: BarButton {
        required property string backendName
        active: false; radius: shell.rounding; fill: "transparent"; outline: "transparent"
        hoverOverride: ({fill: shell.hoverFill(), content: shell.role("hvr_fg", shell.accent)})
        textColor: root.backend === backendName ? shell.accent : shell.alpha(shell.foreground, .6)
    }

    Column {
        id: vpnColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        Column {
            width: parent.width; spacing: Style.xxs
            Text {
                width: parent.width
                text: root.backend === "networkmanager" ? "NetworkManager"
                    : root.status.provider && root.status.provider !== "none" ? root.label(String(root.status.provider))
                    : "No VPN client detected"
                color: root.shell.foreground; font.family: root.shell.fontFamily
                font.pixelSize: Style.title; font.bold: true
            }
            Text {
                width: parent.width
                text: root.label(root.state)
                color: root.connected ? root.shell.role("success", root.shell.foreground)
                    : root.busy ? root.shell.role("warning", root.shell.foreground)
                    : root.blocked || root.state === "error" ? root.shell.role("error", root.shell.foreground)
                    : root.shell.alpha(root.shell.foreground, .6)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            }
            Text { visible: root.notice !== ""; width: parent.width; wrapMode: Text.Wrap; text: root.notice; color: root.shell.role("error", root.shell.foreground); font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
        }

        Row {
            visible: root.nmStatus.available === true
            width: parent.width; spacing: Style.sm
            BackendTab { width: (parent.width - parent.spacing) / 2; height: Style.controlHeight; shell: root.shell; text: "MULLVAD"; backendName: "mullvad"; onClicked: root.selectBackend(backendName) }
            BackendTab { width: (parent.width - parent.spacing) / 2; height: Style.controlHeight; shell: root.shell; text: "NETWORKMANAGER"; backendName: "networkmanager"; onClicked: root.selectBackend(backendName) }
        }

        Column {
            visible: root.connected || !!root.viewStatus.address
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: root.connected ? "TUNNEL" : "NETWORK" }
            InfoPair { label: root.backend === "networkmanager" ? "Profile" : "Relay"; value: String(root.viewStatus.relay || "") }
            InfoPair { label: "Location"; value: String(root.viewStatus.location || "") }
            InfoPair { label: root.connected ? "Exit IP" : "Public IP"; value: root.ipCopied ? "Copied" : String(root.viewStatus.address || ""); interactive: root.backend === "mullvad"; onClicked: root.copyIp() }
            InfoPair { label: "Interface"; value: String(root.viewStatus.iface || "") }
            InfoPair { label: "Endpoint"; value: String(root.viewStatus.endpoint || "") }
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
                    width: vpnColumn.width; text: "•  " + root.feature(modelData)
                    color: root.shell.alpha(root.shell.foreground, .8)
                    font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
        }

        Column {
            visible: root.backend === "mullvad" && root.status.provider === "mullvad"
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "PRIVACY" }
            PopupRow { width: parent.width; shell: root.shell; icon: "󰒓"; title: "Mullvad settings"; detail: root.settingsOpen ? "Hide settings" : "Auto-connect, lockdown and local network"; active: root.settingsOpen; onClicked: root.toggleSettings() }
            Text { visible: root.settingsOpen && !root.settingsLoaded && root.settingsProc.running; text: "Loading settings…"; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
            SettingRow { visible: root.settingsOpen && root.settings.autoconnect !== undefined && root.settings.autoconnect !== null; setting: "autoconnect"; label: "Connect on startup"; detail: "Connect when the Mullvad daemon starts"; checked: root.settings.autoconnect === true }
            SettingRow { visible: root.settingsOpen && root.settings.lockdown !== undefined && root.settings.lockdown !== null; setting: "lockdown"; label: "Lockdown mode"; detail: "Block all traffic while disconnected"; checked: root.settings.lockdown === true }
            SettingRow { visible: root.settingsOpen && root.settings.lan !== undefined && root.settings.lan !== null; setting: "lan"; label: "Allow local network"; detail: "Reach printers and local devices"; checked: root.settings.lan === true }
        }

        Column {
            visible: root.backend === "networkmanager"
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "PROFILES" }
            Text { visible: root.nmProfiles.length === 0; width: parent.width; wrapMode: Text.Wrap; text: "No imported VPN profiles. Import an OpenVPN or WireGuard config with nmcli."; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.caption }
            Repeater {
                model: root.nmProfiles
                PopupRow {
                    required property var modelData
                    width: vpnColumn.width; shell: root.shell
                    icon: modelData.kind === "wireguard" ? "󰒄" : "󰖂"
                    title: modelData.name
                    detail: root.kind(modelData.kind) + (modelData.ready ? "" : " · " + modelData.reason)
                    active: modelData.active; enabled: !root.busy && (modelData.active || modelData.ready)
                    onClicked: root.nmAction(modelData.active ? "disconnect" : "connect", modelData)
                }
            }
        }

        Column {
            visible: root.backend === "mullvad" && root.countries.length > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "LOCATION" }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰍎"
                title: root.locationLabel
                detail: root.browsing === "" ? "Tap to change · / to search" : "Type to filter locations"
                active: root.browsing !== ""
                enabled: !root.busy
                onClicked: { root.settingsOpen = false; root.filter = ""; root.browsing = root.browsing === "" ? "countries" : "" }
            }
            Rectangle {
                visible: root.browsing !== ""
                width: parent.width; height: Style.controlHeight; radius: root.shell.rounding
                color: root.shell.alpha(root.shell.foreground, .06)
                border.width: 2; border.color: root.shell.alpha(root.shell.role("act_br", root.shell.accent), .65)
                Text { anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter; text: "󰍉"; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
                Text { id: searchText; anchors.left: parent.left; anchors.leftMargin: Style.px(34); anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter; text: root.filter; color: root.shell.alpha(root.shell.foreground, .9); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; elide: Text.ElideRight }
                Rectangle {
                    id: searchCaret; visible: root.browsing !== ""; x: searchText.x + Math.min(searchText.implicitWidth, searchText.width - width)
                    anchors.verticalCenter: parent.verticalCenter; width: Math.max(1, Style.px(1)); height: Style.bodySmall + Style.xs; color: root.shell.accent
                    SequentialAnimation on opacity { running: searchCaret.visible; loops: Animation.Infinite; NumberAnimation { to: 0; duration: 500 } NumberAnimation { to: 1; duration: 500 } }
                }
                Text { visible: root.filter === ""; anchors.left: searchCaret.right; anchors.leftMargin: Style.xs; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: root.openCountry ? "Filter cities…" : "Filter countries or cities…"; color: root.shell.alpha(root.shell.foreground, .4); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; elide: Text.ElideRight }
            }
            ListView {
                id: locationList
                visible: root.browsing !== ""
                width: parent.width
                height: Math.min(contentHeight, Style.px(208))
                clip: true; spacing: Style.xxs
                model: root.locationRows
                header: Column {
                    width: ListView.view.width; spacing: Style.xxs
                    PopupRow {
                        visible: root.openCountry === null && root.filter === ""
                        width: parent.width; shell: root.shell
                        icon: "󰇧"; title: "Automatic"; detail: "Closest relay"
                        active: root.currentLocation.kind === "any"
                        selected: root.resultIndex === 0
                        onClicked: root.setLocation(["any"])
                    }
                    PopupRow {
                        visible: root.openCountry !== null
                        width: parent.width; shell: root.shell
                        icon: "󰁍"; title: "All countries"; detail: "Back"
                        onClicked: { root.filter = ""; root.browsing = "countries" }
                    }
                    PopupRow {
                        visible: root.openCountry !== null && root.filter === ""
                        width: parent.width; shell: root.shell
                        icon: " "
                        title: root.openCountry ? "Anywhere in " + root.openCountry.name : ""
                        detail: root.openCountry ? root.relayCount(root.openCountry.relays) : ""
                        active: root.currentLocation.kind === "country"
                        selected: root.resultIndex === 0
                        onClicked: root.setLocation([root.openCountry.code])
                    }
                }
                delegate: PopupRow {
                    required property var modelData
                    required property int index
                    readonly property bool searchedCity: modelData.countryCode !== undefined
                    readonly property bool current: searchedCity
                        ? modelData.code === root.currentLocation.city && modelData.countryCode === root.currentLocation.country
                        : root.openCountry
                        ? modelData.code === root.currentLocation.city
                        : modelData.code === root.currentLocation.country
                    width: ListView.view.width; shell: root.shell
                    // a blank icon keeps every row's text on the same left edge
                    icon: current ? "󰍎" : " "
                    title: searchedCity ? modelData.name + ", " + modelData.countryName : modelData.name
                    detail: root.relayCount(modelData.relays)
                    active: current
                    selected: index + root.resultOffset === root.resultIndex
                    onClicked: root.chooseLocation(modelData)
                }
            }
            Text { visible: root.browsing !== "" && root.locationRows.length === 0; text: "No matching locations"; color: root.shell.alpha(root.shell.foreground, .55); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
        }

        Column {
            visible: root.backend === "mullvad" ? root.status.provider !== undefined && root.status.provider !== "none" : root.nmProfiles.length > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: root.connected ? "󰳌" : "󱦛"
                title: root.busy ? root.label(root.state) + "…" : root.connected ? "Disconnect" : root.backend === "networkmanager" && root.nmProfiles.length > 1 ? "Select a profile" : "Connect"
                detail: root.viewStatus.relay ? String(root.viewStatus.relay) : ""
                active: root.connected
                enabled: !root.busy && (root.backend === "mullvad" || root.connected || root.nmProfiles.length === 1)
                onClicked: root.toggle()
            }
        }
    }
}
