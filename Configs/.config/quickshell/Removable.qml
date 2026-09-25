pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "RemovableModel.js" as Model

Singleton {
    id: root

    property var devices: []
    property var systemDevices: []
    property var networkShares: []
    property var health: ({})
    property var portables: []
    property var support: ({backends: {}, devices: []})
    property var activity: ({})
    property var activityHistory: ({})
    property var temperatureHistory: ({})
    property var mountFlags: ({})
    property var blockers: []
    property var store: ({version: 1, drives: {}, showSystem: true})
    property bool loaded: false
    property bool watchClosely: false
    property bool healthAlertsEnabled: false
    readonly property bool notificationsEnabled: store.notify !== false
    readonly property bool automount: store.automount !== false
    property string busyPath: ""
    property string busyAction: ""
    property string pendingEjectPath: ""
    property string blockedFsPath: ""
    property string lastError: ""
    property string actionStatus: ""
    property var checkedVolume: null
    property var hooks: ({})
    signal uiRequest(string name, string value)

    property var _samples: ({})
    property var _healthChecked: ({})
    property var _previousDevices: []
    property var _expectedRemovals: ({})
    property bool _seenSnapshot: false
    property int _quietTicks: 0
    property string _stderr: ""
    property string _stdout: ""
    property string _successMessage: ""
    property string _openAfterPath: ""
    property string _stdin: ""
    property var _pendingHooks: ({})

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

    readonly property string storePath: Quickshell.env("HOME") + "/.local/state/hypr/removable-drives.json"
    readonly property string hookDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/dev/shm") + "/removable-drives"
    readonly property string helper: Quickshell.env("HOME") + "/.local/lib/hypr/system/drive-filesystem.sh"

    property bool rescanQueued: false
    function rescan() {
        if (lsblkProc.running || gioProc.running) { rescanQueued = true; return }
        lsblkProc.running = true; gioProc.running = true
        if (!mountsProc.running) mountsProc.running = true
        if (!supportProc.running) supportProc.running = true
        if (watchClosely && !networkProc.running) networkProc.running = true
    }
    function rescanIfQueued() { if (rescanQueued) { rescanQueued = false; Qt.callLater(rescan) } }
    function deviceByPath(path) { return devices.find(device => device.path === String(path)) || null }
    function healthKey(device) { return device.path + "|" + device.serial }
    function volumeByPath(path) {
        for (let d = 0; d < devices.length; ++d)
            for (let v = 0; v < devices[d].volumes.length; ++v)
                if (devices[d].volumes[v].fsPath === String(path) || devices[d].volumes[v].path === String(path)) return devices[d].volumes[v]
        return null
    }
    function deviceOfVolume(volume) {
        if (!volume) return null
        for (let d = 0; d < devices.length; ++d)
            if (devices[d].path === volume.fsPath || devices[d].volumes.some(candidate => candidate.fsPath === volume.fsPath)) return devices[d]
        return null
    }
    function filesystemTarget(path) {
        const volume = volumeByPath(path)
        if (volume) return volume
        const device = deviceByPath(path)
        return device ? {path: path, fsPath: path, name: device.name, title: device.title, label: "", fstype: "",
            uuid: "", sizeBytes: device.sizeBytes, mounted: device.mountedCount > 0, encrypted: false, unlocked: false} : null
    }
    function identityOf(volume) {
        const device = deviceOfVolume(volume)
        return volume.uuid ? "uuid:" + volume.uuid : device && device.serial ? "serial:" + device.serial : ""
    }
    function readOnlyFor(volume) { return Model.isReadOnly(mountFlags, volume) }
    function volumeMeta(volume) { return Model.volumeMeta(volume, readOnlyFor(volume)) }
    function activityFor(device) { return device ? activity[device.name] || null : null }
    function hookFor(device) { return device ? hooks[device.key] || null : null }
    function isDeviceBusy(device) { const entry = activityFor(device), hook = hookFor(device); return !!(entry && entry.busy || hook && hook.active) }
    function activityLabel(device) { return Model.activityLabel(activityFor(device)) }

    function applySnapshot(raw) {
        let next
        try {
            const all = Model.parse(raw)
            next = all.filter(device => device.removable && !device.isSystem)
            systemDevices = all.filter(device => !device.removable || device.isSystem)
        }
        catch (error) {
            lastError = "Could not read removable drives"
            return
        }
        const diff = Model.deviceDiff(_previousDevices, next)
        if (diff.removed.length) {
            const currentHealth = Object.assign({}, health), checked = Object.assign({}, _healthChecked)
            const temperatures = Object.assign({}, temperatureHistory), history = Object.assign({}, activityHistory)
            for (const device of diff.removed) {
                const key = healthKey(device)
                delete currentHealth[key]; delete checked[key]; delete temperatures[key]; delete history[key]
            }
            health = currentHealth; _healthChecked = checked; temperatureHistory = temperatures; activityHistory = history
        }
        if (busyAction !== "eject") {
            const expected = Object.assign({}, _expectedRemovals)
            for (const device of next) if (device.mountedCount) delete expected[device.path]
            _expectedRemovals = expected
        }
        devices = next
        if (watchClosely || healthAlertsEnabled) Qt.callLater(autoProbeHealth)
        _previousDevices = next
        loaded = true
        if (_seenSnapshot) announceChanges(diff)
        _seenSnapshot = true
        for (const device of next)
            if (_pendingHooks[device.key] && (device.mountedCount || !device.volumes.some(volume => Model.isMountable(volume)))) runHook(device)
        if (_openAfterPath) {
            const pending = volumeByPath(_openAfterPath)
            if (pending && pending.mounted) { _openAfterPath = ""; openVolume(pending) }
        }
    }

    function announceChanges(diff) {
        for (let i = 0; i < diff.added.length; ++i) {
            notify(diff.added[i].title + " connected", Model.connectedSummary(diff.added[i]))
            automountDevice(diff.added[i])
            if (Model.clean(Model.driveSetting(store, diff.added[i], "onConnect"))) setPendingHook(diff.added[i].key, true)
        }
        for (let i = 0; i < diff.removed.length; ++i) {
            const device = diff.removed[i]
            setPendingHook(device.key, false)
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
        const visible = devices.concat(watchClosely && store.showSystem ? systemDevices.filter(device => device.tran) : [])
        if (statsProc.running || visible.length === 0) return
        const command = ["head", "-v", "-n", "1"]
        for (const device of visible) command.push("/sys/block/" + device.name + "/stat")
        statsProc.command = command
        statsProc.running = true
    }

    function applyStats(raw) {
        const next = Model.buildActivity(_samples, Model.parseBlockStats(raw), Date.now())
        activity = next.activity
        _samples = next.samples
        if (watchClosely) {
            const history = Object.assign({}, activityHistory)
            for (const device of devices.concat(store.showSystem ? systemDevices.filter(item => item.tran) : [])) {
                const rate = next.activity[device.name]
                if (rate) history[healthKey(device)] = (history[healthKey(device)] || []).slice(-47).concat(rate.readRate + rate.writeRate)
            }
            activityHistory = history
        }
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

    function setPendingHook(key, pending) {
        const next = Object.assign({}, _pendingHooks)
        if (pending) next[key] = true; else delete next[key]
        _pendingHooks = next
    }

    function runHook(device) {
        setPendingHook(device.key, false)
        const mounted = Model.mountedVolumes([device])
        hooks = Object.assign({}, hooks, {[device.key]: Model.parseHookProgress("")})
        Quickshell.execDetached(["bash", "-c", "mkdir -p \"${1%/*}\" && : > \"$1\" || exit; bash -c \"$4\" removable-drives \"$2\" \"$3\" \"$1\"; echo \"exit=$?\" >> \"$1\"",
            "removable-drives", hookDir + "/" + Model.hookName(device.key), device.path, mounted.length ? mounted[0].mountpoint : "",
            Model.driveSetting(store, device, "onConnect")])
    }

    function runAction(command, path, action, successMessage, stdin) {
        if (busy) return false
        lastError = ""; actionStatus = ""; blockers = []; blockedFsPath = ""
        _stderr = ""; _stdout = ""; _successMessage = successMessage; _stdin = stdin || ""
        busyPath = path; busyAction = action
        actionProc.command = command
        actionProc.stdinEnabled = true
        actionProc.running = true
        return true
    }

    function mountCommand(volume, readOnly) {
        return ["udisksctl", "mount", "--no-user-interaction", "-b", volume.fsPath].concat(readOnly ? ["-o", "ro"] : [])
    }

    function mount(volume, openAfter) {
        if (!Model.isMountable(volume)) return false
        const device = deviceOfVolume(volume), readOnly = !!device && Model.driveSetting(store, device, "readOnly") === true
        _openAfterPath = openAfter ? volume.fsPath : ""
        return runAction(mountCommand(volume, readOnly), volume.fsPath, "mount", "Mounted " + volume.title + (readOnly ? " read-only" : ""))
    }

    function automountDevice(device) {
        const volumes = device.volumes.filter(volume => Model.isMountable(volume))
        if (!automount || !volumes.length) return
        if (Model.driveSetting(store, device, "autoOpen") ?? store.openOnMount === true) _openAfterPath = volumes[0].fsPath
        const readOnly = Model.driveSetting(store, device, "readOnly") === true
        for (const volume of volumes) Quickshell.execDetached(mountCommand(volume, readOnly))
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

    function filesystemAction(action, volume, type, label, expectedIdentity, zero) {
        const device = deviceOfVolume(volume)
        if (!device || device.isSystem || !device.removable || busy) return lastError = "Drive is unavailable"
        if (isDeviceBusy(device)) return lastError = "Wait for writes to finish"
        if (action === "repair" && (!checkedVolume || checkedVolume.path !== volume.fsPath
            || checkedVolume.uuid !== volume.uuid || checkedVolume.verdict !== false))
            return lastError = "Check this filesystem before repairing it"
        if (action === "format" && volume.mounted) return lastError = "Unmount before formatting"
        if (action === "format" && volume.encrypted && volume.unlocked) return lastError = "Lock the encrypted volume first"
        if (action === "format" && !["exfat", "vfat", "ntfs", "ext4", "btrfs"].includes(type))
            return lastError = "Choose a filesystem"
        if ((action === "label" || action === "format") && !Model.validLabel(action === "label" ? volume.fstype : type, label))
            return lastError = "Invalid or overlong filesystem label"
        const identity = identityOf(volume)
        if (!identity) return lastError = "A drive serial or volume UUID is required"
        if (expectedIdentity && expectedIdentity !== identity) return lastError = "Drive changed; reopen filesystem tools"
        if (action === "check") checkedVolume = null
        runAction([helper, action, volume.fsPath, identity, type || "", label || "", zero === true ? "1" : "0"], volume.fsPath, action,
            action === "label" ? "Renamed " + volume.title : action === "format" ? "Formatted " + volume.title
                : action === "ntfsfix" ? "NTFS checked and mounted" : action === "trash" ? "Emptied drive trash" : "")
        return "ok"
    }

    function activateVolume(volume) {
        if (volume && volume.mounted) openVolume(volume)
        else mount(volume, true)
    }

    function toggleMount(volume) {
        if (volume && volume.mounted) unmount(volume, false)
        else mount(volume, false)
    }

    function unlock(volume, passphrase) {
        if (!volume || !volume.encrypted || volume.unlocked) return "This volume is not locked"
        if (!passphrase) return "Enter the passphrase first"
        const device = deviceOfVolume(volume), readOnly = !!device && Model.driveSetting(store, device, "readOnly") === true
        const script = "set -e\nkey=\"${XDG_RUNTIME_DIR:-/dev/shm}/removable-drives.$$.key\"\ntrap 'rm -f \"$key\"' EXIT\numask 077\n"
            + "IFS= read -r pass; printf %s \"$pass\" > \"$key\"; unset pass\n"
            + "out=$(udisksctl unlock --no-user-interaction -b \"$1\" --key-file \"$key\"); mapper=${out##* as }\n"
            + "udisksctl mount --no-user-interaction -b \"${mapper%.}\" ${2:+-o ro} >/dev/null"
        return runAction(["bash", "-c", script, "removable-drives", volume.path, readOnly ? "1" : ""], volume.fsPath, "unlock",
            "Unlocked " + volume.title, passphrase + "\n") ? "ok" : "Another action is running"
    }

    function lock(volume) {
        if (!volume || !volume.encrypted || !volume.unlocked) return "This volume is not unlocked"
        const script = "set -e\n[ -z \"$2\" ] || udisksctl unmount --no-user-interaction -b \"$2\" >/dev/null\nudisksctl lock --no-user-interaction -b \"$1\" >/dev/null"
        return runAction(["bash", "-c", script, "removable-drives", volume.path, volume.mounted ? volume.fsPath : ""], volume.fsPath, "lock",
            "Locked " + volume.title) ? "ok" : "Another action is running"
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
        let script = "set -e\n", titles = [], expected = Object.assign({}, _expectedRemovals)
        for (let d = 0; d < targets.length; ++d) {
            const device = targets[d]
            titles.push(device.title); expected[device.path] = true
            for (let v = 0; v < device.volumes.length; ++v) {
                const volume = device.volumes[v]
                if (volume.mounted && store.cleanTrashOnEject === true)
                    script += Model.shellQuote(helper) + " trash " + Model.shellQuote(volume.fsPath) + " " + Model.shellQuote(identityOf(volume)) + " || true\n"
                if (volume.mounted) script += "udisksctl unmount --no-user-interaction -b " + Model.shellQuote(volume.fsPath) + "\n"
                if (volume.encrypted && volume.unlocked) script += "udisksctl lock --no-user-interaction -b " + Model.shellQuote(volume.path) + "\n"
            }
            script += "udisksctl power-off --no-user-interaction -b " + Model.shellQuote(device.path) + " || true\n"
        }
        _expectedRemovals = expected
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
    function openVolume(volume) { if (volume && volume.mounted) openPath(volume.mountpoint) }
    function openPath(path) {
        if (path) Quickshell.execDetached(store.fileManager ? ["sh", "-c", store.fileManager + " \"$1\"", "sh", path] : ["xdg-open", path])
    }
    function unmountNetwork(share) {
        if (!share || !share.mountpoint) return
        const script = "fusermount3 -u \"$1\" 2>/dev/null || gio mount -u \"$1\" 2>/dev/null || umount \"$1\""
        runAction(["bash", "-c", script, "drives", share.mountpoint], share.mountpoint, "unmount-network", "Unmounted " + share.source)
    }
    function openTerminal(path, usage) {
        if (!path) return
        const command = usage ? "exec dua i \"$1\"" : "cd \"$1\" && exec \"${SHELL:-/bin/bash}\""
        Quickshell.execDetached(["hyprshell", "launch/terminal-present", "--hypr-profile", "tui", "--app-id", usage ? "org.tui.Dua" : "org.hypr.DriveTerminal", "--title", usage ? "Disk usage" : "Drive terminal", "--", "bash", "-c", command, "drives", path])
    }
    function probeHealth(device) {
        if (!device) return
        if (healthProc.running) return
        _healthChecked = Object.assign({}, _healthChecked, {[healthKey(device)]: Date.now()})
        healthProc.command = [helper, "health", device.path, device.serial]
        healthProc.running = true
    }
    function autoProbeHealth() {
        if ((!watchClosely && !healthAlertsEnabled) || healthProc.running) return
        const interval = watchClosely ? 60000 : 300000
        const device = devices.concat(store.showSystem || healthAlertsEnabled ? systemDevices : []).find(item =>
            item.tran && Date.now() - (_healthChecked[healthKey(item)] || 0) > interval)
        if (device) probeHealth(device)
    }
    function healthFor(device) { return health[healthKey(device)] || null }
    function recordHealth(device, result) {
        const key = healthKey(device)
        health = Object.assign({}, health, {[key]: result})
        const temperature = parseFloat(result.temperature)
        if (temperature > 0) temperatureHistory = Object.assign({}, temperatureHistory,
            {[key]: (temperatureHistory[key] || []).slice(-47).concat(temperature)})
    }
    function openFirstMounted() { const volumes = Model.mountedVolumes(devices); if (volumes.length) openVolume(volumes[0]) }
    function copyPath(volume) { if (volume && volume.mounted) { Quickshell.execDetached(["wl-copy", volume.mountpoint]); actionStatus = "Copied " + volume.mountpoint } }

    function setDriveSetting(device, name, value) {
        if (!device) return
        store = Model.withDriveSetting(store, device, name, value)
        storeFile.setText(JSON.stringify(store, null, 2) + "\n")
    }

    function setOption(name, enabled) {
        store = Object.assign({}, store, {[name]: enabled})
        storeFile.setText(JSON.stringify(store, null, 2) + "\n")
        if (name === "showSystem" && enabled) autoProbeHealth()
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
        onExited: code => { if (code !== 0) root.lastError = "lsblk failed"; root.rescanIfQueued() }
    }
    Process { id: statsProc; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStats(text) } }
    Process { id: mountsProc; command: ["cat", "/proc/mounts"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.mountFlags = Model.parseMountFlags(text) } }
    Process { id: networkProc; command: ["findmnt", "-J", "-l", "-o", "TARGET,SOURCE,FSTYPE,OPTIONS"]; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.networkShares = Model.parseNetworkMounts(text) } }
    Process {
        id: healthProc
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            const device = root.devices.concat(root.systemDevices).find(item =>
                item.path === healthProc.command[2] && item.serial === healthProc.command[3])
            if (device) root.recordHealth(device, Model.parseHealth(text))
            Qt.callLater(root.autoProbeHealth)
        } }
    }
    Process { id: blockersProc; stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.blockers = Model.parseBlockers(text) } }
    Process {
        id: actionProc
        stdinEnabled: true
        onStarted: { if (root._stdin) write(root._stdin); root._stdin = ""; stdinEnabled = false }
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._stdout = text }
        stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._stderr = text }
        onExited: code => {
            const action = root.busyAction, path = root.busyPath
            root.busyAction = ""; root.busyPath = ""
            if (code === 0) {
                root.actionStatus = root._successMessage
                if (action === "check") {
                    const verdict = /^\((true|false),\)/.exec(root._stdout.trim())
                    root.checkedVolume = {path: path, uuid: (root.volumeByPath(path) || {}).uuid || "", verdict: verdict ? verdict[1] === "true" : null}
                    root.actionStatus = verdict ? (verdict[1] === "true" ? "No filesystem errors found" : "Filesystem errors found; repair is available") : "Check returned no verdict"
                } else if (action === "repair") {
                    const verdict = /^\((true|false),\)/.exec(root._stdout.trim())
                    root.actionStatus = verdict && verdict[1] === "true" ? "Filesystem repaired" : "Repair did not finish cleanly"
                    root.checkedVolume = null
                }
                if (action === "eject") root.notify("Safe to remove", root._successMessage.replace(/^Safe to remove /, ""))
                if (action === "format") root.notify("Formatted", root._successMessage)
                if (action === "ntfsfix") Qt.callLater(() => root.mount(root.volumeByPath(path), false))
            } else if (code === 75) {
                root.actionStatus = root._successMessage || "Filesystem action completed"
                root.lastError = "Volume could not be remounted"
            } else {
                root._openAfterPath = ""
                root.lastError = Model.formatError(root._stderr) || action + " failed"
                if (/busy/i.test(root.lastError)) root.probeBlockers(root.mountedPathsFor(path))
            }
            root.rescan()
        }
    }
    Process {
        id: gioProc; command: ["gio", "mount", "-li"]; onExited: root.rescanIfQueued()
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.portables = Model.parseGioMounts(text) }
    }
    Process { command: ["gio", "mount", "-o"]; running: true; stdout: SplitParser { onRead: root.rescan() } }
    Process {
        id: supportProc
        command: ["bash", Quickshell.env("HOME") + "/.local/lib/hypr/system/removable.sh", "--probe-support"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.support = Model.parseSupport(text) }
    }
    Process {
        id: monitorProc
        command: ["stdbuf", "-oL", "udevadm", "monitor", "--udev", "--subsystem-match=block", "--subsystem-match=usb"]
        running: true
        stdout: SplitParser { onRead: line => { if (/(add|remove|change|bind|unbind)/.test(String(line))) root.rescan() } }
        onExited: monitorRestart.restart()
    }

    Instantiator {
        model: root.devices.filter(device => Model.clean(Model.driveSetting(root.store, device, "onConnect")))
        delegate: FileView {
            required property var modelData
            path: root.hookDir + "/" + Model.hookName(modelData.key); watchChanges: true; printErrors: false
            onFileChanged: reload()
            onLoaded: root.hooks = Object.assign({}, root.hooks, {[modelData.key]: Model.parseHookProgress(text())})
        }
    }

    FileView {
        id: storeFile
        path: root.storePath; watchChanges: true; printErrors: false; atomicWrites: true
        onLoaded: root.store = Model.parseStore(text())
        onFileChanged: reload()
        onLoadFailed: root.store = Model.parseStore("")
    }

    Timer { id: monitorRestart; interval: 3000; onTriggered: if (!monitorProc.running) monitorProc.running = true }
    Timer { interval: 1000; running: root.devices.length > 0 || root.watchClosely && root.store.showSystem && root.systemDevices.length > 0; repeat: true; triggeredOnStart: true; onTriggered: root.sampleActivity() }
    Timer { interval: 8000; running: root.watchClosely; repeat: true; onTriggered: root.rescan() }
    Timer { interval: 60000; running: root.watchClosely || root.healthAlertsEnabled; repeat: true; onTriggered: root.autoProbeHealth() }
    onWatchCloselyChanged: if (watchClosely) { rescan(); autoProbeHealth() } else activityHistory = ({})
    onHealthAlertsEnabledChanged: if (healthAlertsEnabled) { rescan(); autoProbeHealth() }

    property IpcHandler ipc: IpcHandler {
        target: "removable-drives"
        function refresh(): string { root.rescan(); return "ok" }
        function list(): string { return JSON.stringify(root.devices) }
        function phones(): string { return JSON.stringify(root.portables) }
        function status(): string {
            return JSON.stringify({devices: root.deviceCount, mounted: root.mountedCount, busy: root.anyBusy, writeRate: Math.round(root.totalWriteRate),
                pendingEject: root.pendingEjectPath, working: root.busy, healthy: root.checkedVolume ? root.checkedVolume.verdict : null,
                hooks: root.devices.filter(device => root.hookFor(device)).map(device => Object.assign({device: device.path}, root.hookFor(device))),
                health: root.devices.map(device => ({device: device.path, state: Model.healthVerdict(root.healthFor(device))}))})
        }
        function network(): string { return JSON.stringify(root.networkShares) }
        function label(path: string, name: string): string { return root.filesystemAction("label", root.volumeByPath(path), "", name, "") }
        function check(path: string): string { return root.filesystemAction("check", root.volumeByPath(path), "", "", "") }
        function format(path: string, fstype: string, name: string): string { return root.filesystemAction("format", root.filesystemTarget(path), fstype, name, "") }
        function lock(path: string): string { return root.lock(root.volumeByPath(path)) }
        function smart(path: string): string {
            const device = root.deviceByPath(path)
            if (!device) return "unknown device: " + path
            const health = root.healthFor(device)
            return JSON.stringify(Object.assign({supported: Model.healthVerdict(health) !== "unsupported"}, health))
        }
        function setTab(tab: string): string { if (!["local", "network"].includes(tab)) return "unknown tab: " + tab; root.uiRequest("activeTab", tab); return "ok" }
        function expandDevice(path: string): string { root.uiRequest("expandedDevicePath", path); return "ok" }
        function expandVolume(path: string): string {
            const volume = root.volumeByPath(path), device = root.deviceOfVolume(volume)
            if (!device) return "unknown volume: " + path
            root.uiRequest("expandedDevicePath", device.path); root.uiRequest("expandedVolumePath", volume.fsPath); return "ok"
        }
        function eject(path: string): string { const device = root.deviceByPath(path); if (!device) return "unknown device: " + path; root.eject(device); return "ok" }
        function ejectAll(): string { if (!root.devices.length) return "no drives attached"; root.ejectAll(); return "ok" }
        function mount(path: string): string { const volume = root.volumeByPath(path); return volume && root.mount(volume, false) ? "ok" : "unable to mount: " + path }
        function unmount(path: string): string { const volume = root.volumeByPath(path); return volume && root.unmount(volume, false) ? "ok" : "unable to unmount: " + path }
        function mountReadOnly(path: string): string { return root.mountReadOnly(root.volumeByPath(path)) }
        function open(path: string): string { const volume = root.volumeByPath(path); if (!volume || !volume.mounted) return "not mounted: " + path; root.openVolume(volume); return "ok" }
    }

    Component.onCompleted: rescan()
}
