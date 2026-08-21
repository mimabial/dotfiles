pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Single source for screen brightness. The device is resolved once via
// brightnessctl, then the value is read straight from sysfs so routine updates
// cost a file read rather than a subprocess.
Singleton {
    id: root

    // waybar's backlight format-icons: a moon-phase ramp, new -> full
    readonly property var icons: [
        "\u{e38d}", "\u{e3d3}", "\u{e3d1}", "\u{e3cf}", "\u{e3ce}",
        "\u{e3cd}", "\u{e3ca}", "\u{e3c8}", "\u{e39b}"
    ]

    property string device: ""
    property int raw: 0
    property int maximum: 0
    readonly property int percent: maximum > 0 ? Math.round(raw * 100 / maximum) : 0
    // waybar buckets with integer division: idx = percent / (100 / count)
    readonly property string icon: icons[Math.min(icons.length - 1,
        Math.floor(percent / Math.floor(100 / icons.length)))]

    function refresh() { if (device !== "") value.reload() }
    // something changed brightness out-of-process; give the write a moment to
    // land before reading back
    function nudge() { settle.restart() }

    property Timer settle: Timer { interval: 150; onTriggered: root.refresh() }

    property Process probe: Process {
        running: true
        command: ["brightnessctl", "-m"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            const fields = String(text).trim().split("\n")[0].split(",")
            if (fields.length < 5) return
            root.maximum = Number(fields[4])
            root.device = fields[0]
        } }
    }

    property FileView value: FileView {
        path: root.device === "" ? "" : "/sys/class/backlight/" + root.device + "/brightness"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.raw = Number(String(text()).trim())
    }

    // sysfs does not always notify, so keep a cheap fallback read
    property Timer poll: Timer {
        running: root.device !== ""; interval: 2000; repeat: true
        onTriggered: root.refresh()
    }
}
