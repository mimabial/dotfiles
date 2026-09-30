pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    property bool raisePending: false
    property bool cliampLoaded: false
    readonly property real artSize: Style.px(36)
    readonly property string genericArt: Quickshell.iconPath("audio-x-generic", true)
    css: "nowplaying"
    text: Media.player ? "󰐊" : ""
    symbol: "media-playback-start"; symbolContext: "actions"
    onClicked: shell.togglePopup("nowplaying")
    function appIcon(player) { return player.desktopEntry && DesktopEntries.applications.values.length ? Quickshell.iconPath(DesktopEntries.heuristicLookup(player.desktopEntry)?.icon ?? "", true) : "" }
    PopupCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "nowplaying"
        contentWidth: Style.px(320); contentHeight: sources.implicitHeight + padding * 2; keyboardHint: ""
        onOpenChanged: if (!open) root.raisePending = false
        Column {
            id: sources
            width: parent.width; spacing: Style.xs
            Repeater {
                model: Media.sourcePlayers
                PopupRow {
                    id: entry
                    required property var modelData
                    readonly property string app: root.appIcon(modelData)
                    width: parent.width; shell: root.shell; interactive: modelData.canRaise
                    iconSource: modelData.trackArtUrl || app || root.genericArt; iconSize: root.artSize
                    title: modelData.trackTitle || modelData.identity; detail: Media.displayArtist(modelData); rightInset: controls.width + Style.sm
                    onClicked: { root.raisePending = true; entry.modelData.raise() }
                    IconImage {
                        visible: entry.modelData.trackArtUrl !== "" && entry.app !== ""
                        width: root.artSize / 2; height: width; source: entry.app
                        x: Style.controlPaddingX + root.artSize - width; y: (entry.height + root.artSize) / 2 - height
                    }
                    Row {
                        id: controls
                        anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                        TransportButton { shell: root.shell; text: entry.modelData.isPlaying ? "󰏤" : "󰐊"; onClicked: Media.playPause(entry.modelData) }
                        TransportButton { shell: root.shell; text: "󰒭"; enabled: Media.canNext(entry.modelData); onClicked: Media.next(entry.modelData) }
                    }
                }
            }
            PopupSeparator { shell: root.shell }
            PopupRow { width: parent.width; shell: root.shell; title: "Open CLIamp…"; onClicked: { root.cliampLoaded = true; root.shell.togglePopup("media") } }
        }
    }
    Loader {
        active: root.cliampLoaded; visible: false
        sourceComponent: Component { MediaPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed } }
    }
    // Hyprland answers an app's focus request by marking it urgent (focus_on_activate is off),
    // so the window a row click raised is focused here instead
    Connections {
        target: Hyprland; enabled: root.raisePending
        function onRawEvent(event) {
            if (event.name !== "urgent") return
            root.raisePending = false
            const address = "0x" + event.data
            const dock = root.shell.dock
            if (!(dock && (dock.minimizedOrigins[address] !== undefined || dock.isMinimizedWorkspace(dock.liveWsNameOf({ address })))
                && dock.restoreWindow(address, "")))
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + address + '" })')
            root.shell.closePopup()
        }
    }
}
