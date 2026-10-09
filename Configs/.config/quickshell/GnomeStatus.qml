pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    property int readers: 0
    property var vpn: ({ provider: "none", state: "disconnected" })
    property bool refreshPending: false
    property string keyboardDevice: ""
    property int keyboardBrightness: 0
    property int keyboardMaximum: 0
    function refresh() {
        if (readers === 0) return
        if (vpnStatus.running) refreshPending = true
        else vpnStatus.running = true
    }
    function refreshKeyboard() { if (keyboardDevice) keyboardValue.reload() }
    onReadersChanged: if (readers > 0) { refresh(); if (!keyboardDevice) keyboardProbe.running = true }
    Process {
        id: vpnStatus
        command: [root.home + "/.local/lib/hypr/system/vpn-status.sh"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            try { root.vpn = JSON.parse(text) }
            catch (error) { console.warn("VPN status: " + error) }
        } }
        onExited: if (root.refreshPending) { root.refreshPending = false; root.refresh() }
    }
    Process { command: ["nmcli", "monitor"]; running: root.readers > 0; stdout: SplitParser { onRead: root.refresh() } }
    Process { command: ["mullvad", "status", "listen"]; running: root.readers > 0 && root.vpn.provider === "mullvad"; stdout: SplitParser { onRead: root.refresh() } }
    Process {
        id: keyboardProbe
        command: ["brightnessctl", "--list", "--class", "leds", "--machine-readable"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            const device = text.trim().split("\n").map(line => line.split(",")).find(([name]) => name.endsWith("::kbd_backlight"))
            if (!device) return
            const [name, , current, , maximum] = device
            root.keyboardDevice = name; root.keyboardBrightness = Number(current); root.keyboardMaximum = Number(maximum)
        } }
    }
    FileView {
        id: keyboardValue
        path: root.keyboardDevice ? "/sys/class/leds/" + root.keyboardDevice + "/brightness" : ""
        printErrors: false; watchChanges: root.readers > 0
        onFileChanged: reload()
        onLoaded: root.keyboardBrightness = Number(text())
    }
}
