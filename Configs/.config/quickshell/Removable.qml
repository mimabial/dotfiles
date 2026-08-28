pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "RemovableModel.js" as Model

Singleton {
    id: root

    property var devices: []
    property var portables: []
    property var support: ({backends: {}, devices: []})
    property var activity: ({})
    property var mountFlags: ({})
    property var blockers: []
    property var store: ({version: 1, drives: {}})
    property bool loaded: false
    property bool refreshing: false
    property bool watchClosely: false
    property bool notificationsEnabled: true
    property string busyPath: ""
    property string busyAction: ""
    property string pendingEjectPath: ""
    property string blockedFsPath: ""
    property string lastError: ""
    property string actionStatus: ""

    property var _samples: ({})
    property var _previousDevices: []
    property var _expectedRemovals: ({})
    property var _actionExpectedRemovals: []
    property bool _seenSnapshot: false
    property int _quietTicks: 0
    property string _stderr: ""
    property string _successMessage: ""
    property string _openAfterPath: ""

    readonly property bool busy: actionProc.running
    readonly property int deviceCount: devices.length
    readonly property int mountedCount: devices.reduce((count, device) => count + device.mountedCount, 0)
    readonly property string supportHint: Model.supportHint(support)
    readonly property bool present: devices.length > 0 || portables.length > 0 || supportHint !== ""
    readonly property bool anyBusy: devices.some(device => isDeviceBusy(device))
    readonly property real totalWriteRate: devices.reduce((total, device) => {
        const entry = activity[device.name]
        return total + (entry ? Number(entry.writeRate || 0) : 0)
    }, 0)
    readonly property string barGlyph: devices.length ? devices[0].glyph
        : portables.length ? Model.portableGlyph(portables[0])
        : supportHint ? Model.GLYPH_ALERT : Model.GLYPH_USB
    readonly property string summary: anyBusy
        ? (Model.formatRate(totalWriteRate) ? "Writing " + Model.formatRate(totalWriteRate) + " — do not remove" : "Busy — do not remove")
        : devices.length ? Model.summary(devices)
        : portables.length ? portables.length + (portables.length === 1 ? " portable device" : " portable devices")
        : supportHint || "No removable media"

    readonly property string storePath: Quickshell.env("HOME") + "/.local/state/hypr/removable-drives.json"

    function refresh() {
        if (!lsblkProc.running) { refreshing = true; lsblkProc.running = true }
        if (!mountsProc.running) mountsProc.running = true
    }

    function rescan() { refresh(); refreshPortables() }
    function deviceByPath(path) { return devices.find(device => device.path === String(path)) || null }
    function volumeByPath(path) {
        for (let d = 0; d < devices.length; ++d)
            for (let v = 0; v < devices[d].volumes.length; ++v)
                if (devices[d].volumes[v].fsPath === String(path) || devices[d].volumes[v].path === String(path)) return devices[d].volumes[v]
        return null
    }
    function deviceOfVolume(volume) {
        if (!volume) return null
        for (let d = 0; d < devices.length; ++d)
            if (devices[d].volumes.some(candidate => candidate.fsPath === volume.fsPath)) return devices[d]
        return null
    }
    function readOnlyFor(volume) { return Model.isReadOnly(mountFlags, volume) }
    function volumeMeta(volume) { return Model.volumeMeta(volume, readOnlyFor(volume)) }
    function activityFor(device) { return device ? activity[device.name] || null : null }
    function isDeviceBusy(device) { const entry = activityFor(device); return !!(entry && entry.busy) }
    function activityLabel(device) { return Model.activityLabel(activityFor(device)) }

    function applySnapshot(raw) {
        let next
        try { next = Model.applyStore(Model.parse(raw), store) }
        catch (error) {
            lastError = "Could not read removable drives"
            refreshing = false
            return
        }
        const diff = Model.deviceDiff(_previousDevices, next)
        devices = next
        _previousDevices = next
        loaded = true
        refreshing = false
        if (_seenSnapshot) announceChanges(diff)
        _seenSnapshot = true
        if (_openAfterPath) {
            const pending = volumeByPath(_openAfterPath)
            if (pending && pending.mounted) { _openAfterPath = ""; openVolume(pending) }
        }
    }

    function announceChanges(diff) {
        for (let i = 0; i < diff.added.length; ++i)
            notify(diff.added[i].title + " connected", Model.connectedSummary(diff.added[i]))
        for (let i = 0; i < diff.removed.length; ++i) {
            const device = diff.removed[i]
            if (_expectedRemovals[device.path]) {
                const expected = Object.assign({}, _expectedRemovals)
                delete expected[device.path]
                _expectedRemovals = expected
            } else if (device.mountedCount > 0) {
                notify("Removed while still mounted", device.title + " may have incomplete files", "critical")
            } else notify(device.title + " removed", "")
        }
    }

    function sampleActivity() {
        if (statsProc.running || devices.length === 0) return
        const command = ["head", "-v", "-n", "1"]
        for (let i = 0; i < devices.length; ++i) command.push("/sys/block/" + devices[i].name + "/stat")
        statsProc.command = command
        statsProc.running = true
    }

    function applyStats(raw) {
        const next = Model.buildActivity(_samples, Model.parseBlockStats(raw), Date.now())
        activity = next.activity
        _samples = next.samples
        advancePendingEject()
    }

    function pendingTargets() {
        if (!pendingEjectPath) return []
        if (pendingEjectPath === "*") return devices
        const device = deviceByPath(pendingEjectPath)
        return device ? [device] : []
    }

    function advancePendingEject() {
        if (!pendingEjectPath) return
        const targets = pendingTargets()
        if (!targets.length) { cancelPendingEject(); return }
        const step = Model.advanceQuiet(targets.some(device => isDeviceBusy(device)), _quietTicks, 2)
        _quietTicks = step.quietTicks
        if (step.run) { pendingEjectPath = ""; _quietTicks = 0; runEject(targets) }
    }

    function cancelPendingEject() { pendingEjectPath = ""; _quietTicks = 0; actionStatus = "" }

    function runAction(command, path, action, successMessage) {
        if (busy) return false
        lastError = ""; actionStatus = ""; blockers = []; blockedFsPath = ""
        _stderr = ""; _successMessage = successMessage
        busyPath = path; busyAction = action
        actionProc.command = command
        actionProc.running = true
        return true
    }

    function mount(volume, openAfter) {
        if (!Model.isMountable(volume)) return false
        _openAfterPath = openAfter ? volume.fsPath : ""
        return runAction(["udisksctl", "mount", "--no-user-interaction", "-b", volume.fsPath], volume.fsPath, "mount", "Mounted " + volume.title)
    }

    function unmount(volume, force) {
        if (!volume || !volume.mounted) return false
        _openAfterPath = ""
        const command = ["udisksctl", "unmount", "--no-user-interaction", "-b", volume.fsPath]
        if (force) command.push("--force")
        return runAction(command, volume.fsPath, "unmount", (force ? "Force unmounted " : "Unmounted ") + volume.title)
    }

    function mountReadOnly(volume) {
        if (!volume) return "Unknown volume"
        if (busy) return "Another action is running"
        if (volume.encrypted && !volume.unlocked) return "Unlock this volume first"
        if (volume.mounted && readOnlyFor(volume)) { actionStatus = volume.title + " is already read-only"; return "unchanged" }
        if (!volume.mounted && !Model.isMountable(volume)) return "This volume cannot be mounted"
        const device = deviceOfVolume(volume)
        if (device && isDeviceBusy(device)) return "Wait for writes to finish"
        const script = "set -e\ndev=$1\nif [ \"$2\" = 1 ]; then udisksctl unmount --no-user-interaction -b \"$dev\" >/dev/null; fi\nudisksctl mount --no-user-interaction -o ro -b \"$dev\" >/dev/null"
        return runAction(["bash", "-c", script, "removable-drives", volume.fsPath, volume.mounted ? "1" : "0"], volume.fsPath, "mount-ro", "Mounted " + volume.title + " read-only") ? "ok" : "Another action is running"
    }

    function activateVolume(volume) {
        if (!volume) return
        if (volume.mounted) openVolume(volume)
        else if (volume.encrypted && !volume.unlocked) unlock(volume)
        else mount(volume, true)
    }

    function toggleMount(volume) {
        if (!volume) return
        if (volume.mounted) unmount(volume, false)
        else if (volume.encrypted && !volume.unlocked) unlock(volume)
        else mount(volume, false)
    }

    function unlock(volume) {
        if (!volume || !volume.encrypted || volume.unlocked) return
        Quickshell.execDetached(["hyprshell", "launch/terminal-present", "--app-id", "org.hypr.RemovableUnlock", "--title", "Unlock drive", "--", "udisksctl", "unlock", "-b", volume.path])
    }

    function eject(device) {
        if (!device || busy) return
        if (isDeviceBusy(device)) {
            pendingEjectPath = device.path; _quietTicks = 0
            actionStatus = "Waiting for writes to finish on " + device.title + "…"
        } else runEject([device])
    }

    function ejectAll() {
        if (busy || devices.length === 0) return
        if (anyBusy) { pendingEjectPath = "*"; _quietTicks = 0; actionStatus = "Waiting for writes to finish…" }
        else runEject(devices)
    }

    function runEject(targets) {
        if (!targets || !targets.length || busy) return
        let script = "set -e\n", titles = [], expected = Object.assign({}, _expectedRemovals), paths = []
        for (let d = 0; d < targets.length; ++d) {
            const device = targets[d]
            titles.push(device.title); paths.push(device.path); expected[device.path] = true
            for (let v = 0; v < device.volumes.length; ++v) {
                const volume = device.volumes[v]
                if (volume.mounted) script += "udisksctl unmount --no-user-interaction -b " + Model.shellQuote(volume.fsPath) + "\n"
                if (volume.encrypted && volume.unlocked) script += "udisksctl lock --no-user-interaction -b " + Model.shellQuote(volume.path) + "\n"
            }
            script += "udisksctl power-off --no-user-interaction -b " + Model.shellQuote(device.path) + " || true\n"
        }
        _expectedRemovals = expected; _actionExpectedRemovals = paths
        runAction(["bash", "-c", script], targets.length === 1 ? targets[0].path : "*", "eject", "Safe to remove " + titles.join(", "))
    }

    function mountedPathsFor(path) {
        const result = [], device = deviceByPath(path), volume = volumeByPath(path)
        const targets = path === "*" ? devices : device ? [device] : []
        if (volume && volume.mounted) { blockedFsPath = volume.fsPath; return [volume.mountpoint] }
        for (let d = 0; d < targets.length; ++d)
            for (let v = 0; v < targets[d].volumes.length; ++v)
                if (targets[d].volumes[v].mounted) { if (!blockedFsPath) blockedFsPath = targets[d].volumes[v].fsPath; result.push(targets[d].volumes[v].mountpoint) }
        return result
    }

    function probeBlockers(paths) {
        if (!paths.length || blockersProc.running) return
        const command = ["bash", "-c", "pids=$(fuser -m \"$@\" 2>/dev/null); [ -n \"$pids\" ] && ps -o pid=,comm= -p $pids || true", "removable-drives"]
        for (let i = 0; i < paths.length; ++i) command.push(paths[i])
        blockersProc.command = command; blockersProc.running = true
    }

    function forceUnmountBlocked() { const volume = volumeByPath(blockedFsPath); if (volume) unmount(volume, true) }
    function openVolume(volume) { if (volume && volume.mounted) Quickshell.execDetached(["xdg-open", volume.mountpoint]) }
    function openFirstMounted() { const volumes = Model.mountedVolumes(devices); if (volumes.length) openVolume(volumes[0]) }
    function copyPath(volume) { if (volume && volume.mounted) { Quickshell.execDetached(["wl-copy", volume.mountpoint]); actionStatus = "Copied " + volume.mountpoint } }

    function setNickname(device, nickname) {
        if (!device) return
        const next = Model.withNickname(store, device, nickname)
        store = next
        storeFile.setText(JSON.stringify(next, null, 2) + "\n")
        devices = Model.applyStore(devices.slice(), next)
    }

    function applyStore(raw) {
        store = Model.parseStore(raw)
        devices = Model.applyStore(devices.slice(), store)
    }

    function refreshPortables() {
        if (!gioProc.running) gioProc.running = true
        if (!supportProc.running) supportProc.running = true
    }
    function openPortable(entry) { if (entry && entry.uri) Quickshell.execDetached(["gio", "open", entry.uri]) }
    function togglePortable(entry) {
        if (!entry || !entry.uri) return
        runAction(entry.mounted ? ["gio", "mount", "-u", entry.uri] : ["gio", "mount", entry.uri], entry.uri,
            entry.mounted ? "unmount-portable" : "mount-portable", (entry.mounted ? "Unmounted " : "Mounted ") + entry.name)
    }

    function notify(title, body, urgency) {
        if (!notificationsEnabled) return
        const command = ["notify-send", "-a", "Removable drives", "-i", "drive-removable-media"]
        if (urgency) command.push("-u", urgency)
        command.push(Model.plain(title))
        if (body) command.push(Model.plain(body))
        Quickshell.execDetached(command)
    }

    Process {
        id: lsblkProc
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,LABEL,PARTLABEL,FSTYPE,SIZE,FSSIZE,FSAVAIL,FSUSED,MOUNTPOINT,MOUNTPOINTS,RM,HOTPLUG,TYPE,TRAN,VENDOR,MODEL,UUID,SERIAL"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applySnapshot(text) }
        onExited: code => { root.refreshing = false; if (code !== 0) root.lastError = "lsblk failed" }
    }
    Process { id: statsProc; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStats(text) } }
    Process { id: mountsProc; command: ["cat", "/proc/mounts"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.mountFlags = Model.parseMountFlags(text) } }
    Process { id: blockersProc; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.blockers = Model.parseBlockers(text) } }
    Process {
        id: actionProc
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._stderr = text }
        onExited: code => {
            const action = root.busyAction, path = root.busyPath
            root.busyAction = ""; root.busyPath = ""
            if (code === 0) {
                root.actionStatus = root._successMessage
                if (action === "eject") root.notify("Safe to remove", root._successMessage.replace(/^Safe to remove /, ""))
            } else {
                if (action === "eject") {
                    const expected = Object.assign({}, root._expectedRemovals)
                    for (let i = 0; i < root._actionExpectedRemovals.length; ++i) delete expected[root._actionExpectedRemovals[i]]
                    root._expectedRemovals = expected
                }
                root._openAfterPath = ""
                root.lastError = Model.formatError(root._stderr) || action + " failed"
                if (/busy/i.test(root.lastError)) root.probeBlockers(root.mountedPathsFor(path))
            }
            root._actionExpectedRemovals = []
            actionSettle.restart()
            if (action === "mount-portable" || action === "unmount-portable") root.refreshPortables()
        }
    }
    Process { id: gioProc; command: ["gio", "mount", "-li"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.portables = Model.parseGioMounts(text) } }
    Process {
        id: supportProc
        command: ["bash", "-c", "for f in /usr/share/gvfs/mounts/*.mount; do [ -e \"$f\" ] || continue; echo backend $(basename \"$f\" .mount); done; for d in /sys/bus/usb/devices/*/; do [ -r \"$d/idVendor\" ] || continue; v=$(cat \"$d/idVendor\" 2>/dev/null); [ \"$v\" = 1d6b ] && continue; cls=; for i in \"$d\"*:*/bInterfaceClass; do [ -r \"$i\" ] && cls=\"$cls,$(cat \"$i\" 2>/dev/null)\"; done; echo usb \"$v$cls\" \"$(cat \"$d/product\" 2>/dev/null)\"; done"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.support = Model.parseSupport(text) }
    }
    Process {
        id: monitorProc
        command: ["stdbuf", "-oL", "udevadm", "monitor", "--udev", "--subsystem-match=block", "--subsystem-match=usb"]
        running: true
        stdout: SplitParser { onRead: line => { if (/(add|remove|change|bind|unbind)/.test(String(line))) udevSettle.restart() } }
        onExited: monitorRestart.restart()
    }

    FileView {
        id: storeFile
        path: root.storePath; watchChanges: true; printErrors: false; atomicWrites: true
        onLoaded: root.applyStore(text())
        onFileChanged: reload()
        onLoadFailed: root.applyStore("")
    }

    Timer { id: actionSettle; interval: 700; onTriggered: root.refresh() }
    Timer { id: udevSettle; interval: 350; onTriggered: { root.refresh(); root.refreshPortables(); portableSettle.restart() } }
    Timer { id: portableSettle; interval: 2500; onTriggered: root.refreshPortables() }
    Timer { id: monitorRestart; interval: 3000; onTriggered: if (!monitorProc.running) monitorProc.running = true }
    Timer { interval: 1000; running: root.devices.length > 0; repeat: true; triggeredOnStart: true; onTriggered: root.sampleActivity() }
    Timer { interval: 8000; running: root.watchClosely; repeat: true; onTriggered: root.rescan() }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: root.rescan() }
    onWatchCloselyChanged: if (watchClosely) rescan()

    property IpcHandler ipc: IpcHandler {
        target: "removable-drives"
        function refresh(): string { root.rescan(); return "ok" }
        function list(): string { return JSON.stringify(root.devices) }
        function phones(): string { return JSON.stringify(root.portables) }
        function status(): string { return JSON.stringify({devices: root.deviceCount, mounted: root.mountedCount, busy: root.anyBusy, writeRate: Math.round(root.totalWriteRate), pendingEject: root.pendingEjectPath, working: root.busy}) }
        function eject(path: string): string { const device = root.deviceByPath(path); if (!device) return "unknown device: " + path; root.eject(device); return "ok" }
        function ejectAll(): string { if (!root.devices.length) return "no drives attached"; root.ejectAll(); return "ok" }
        function mount(path: string): string { const volume = root.volumeByPath(path); return volume && root.mount(volume, false) ? "ok" : "unable to mount: " + path }
        function unmount(path: string): string { const volume = root.volumeByPath(path); return volume && root.unmount(volume, false) ? "ok" : "unable to unmount: " + path }
        function mountReadOnly(path: string): string { return root.mountReadOnly(root.volumeByPath(path)) }
        function open(path: string): string { const volume = root.volumeByPath(path); if (!volume || !volume.mounted) return "not mounted: " + path; root.openVolume(volume); return "ok" }
        function rename(path: string, nickname: string): string { const device = root.deviceByPath(path); if (!device) return "unknown device: " + path; root.setNickname(device, nickname); return "ok" }
    }

    Component.onCompleted: rescan()
}
