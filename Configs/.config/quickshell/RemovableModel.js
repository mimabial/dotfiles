.pragma library

function codepoint(code) {
    if (String.fromCodePoint) return String.fromCodePoint(code)
    const offset = code - 0x10000
    return String.fromCharCode(0xD800 + (offset >> 10), 0xDC00 + (offset & 0x3FF))
}

var GLYPH_USB = codepoint(0xF129F)
var GLYPH_SD = codepoint(0xF0479)
var GLYPH_DISK = codepoint(0xF02CA)
var GLYPH_EJECT = codepoint(0xF01EA)
var GLYPH_FOLDER = codepoint(0xF0770)
var GLYPH_MOUNT = codepoint(0xF0120)
var GLYPH_UNMOUNT = codepoint(0xF011D)
var GLYPH_LOCKED = codepoint(0xF033E)
var GLYPH_ALERT = codepoint(0xF0028)
var GLYPH_REFRESH = codepoint(0xF0450)
var GLYPH_PHONE = codepoint(0xF09A7)
var GLYPH_CAMERA = codepoint(0xF0100)
var GLYPH_PENCIL = codepoint(0xF03EB)
var GLYPH_COPY = codepoint(0xF018F)
var GLYPH_READONLY = codepoint(0xF0250)

var UNMOUNTABLE = ["swap", "LVM2_member", "linux_raid_member", "zfs_member", "ddf_raid_member", "isw_raid_member"]
var SYSTEM_MOUNTS = ["/", "/boot", "/boot/efi", "/efi", "/home", "/var", "/usr", "/nix", "/nix/store", "[SWAP]"]
var PORTABLE_URI = /^(mtp|gphoto2|afc):\/\//
var PHONE_NAME = /iphone|ipad|android|phone|pixel|galaxy|oneplus|xiaomi|nexus|redmi/i

function exact(value) { return String(value === undefined || value === null ? "" : value) }
function clean(value) { return exact(value).replace(/\s+/g, " ").replace(/^ | $/g, "") }
function plain(value) { return clean(value).replace(/[<>]/g, "") }
function shellQuote(value) { return "'" + exact(value).replace(/'/g, "'\\''") + "'" }

function formatBytes(bytes) {
    let value = Number(bytes)
    if (!isFinite(value) || value <= 0) return ""
    const units = ["B", "KB", "MB", "GB", "TB", "PB"]
    let unit = 0
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; ++unit }
    if (unit === 0) return Math.round(value) + " B"
    return (value >= 100 ? value.toFixed(0) : value.toFixed(1)) + " " + units[unit]
}

function formatFsType(value) {
    const fs = clean(value)
    const names = ({vfat: "FAT32", exfat: "exFAT", ntfs: "NTFS", ntfs3: "NTFS", crypto_LUKS: "LUKS", hfsplus: "HFS+", apfs: "APFS"})
    return names[fs] || fs.toUpperCase()
}

function isVirtual(name) { return /^(zram|loop|ram|dm-|md|sr|fd)/.test(exact(name)) }
function isCandidateDisk(node) { return !!node && node.type === "disk" && !isVirtual(node.name) && (node.rm === true || node.hotplug === true) }

function holdsSystemMount(node) {
    if (!node) return false
    if (SYSTEM_MOUNTS.includes(exact(node.mountpoint))) return true
    const mounts = node.mountpoints || []
    for (let i = 0; i < mounts.length; ++i)
        if (mounts[i] && SYSTEM_MOUNTS.includes(exact(mounts[i]))) return true
    const children = node.children || []
    for (let i = 0; i < children.length; ++i)
        if (holdsSystemMount(children[i])) return true
    return false
}

function deviceGlyph(device) {
    if (/^mmcblk/.test(exact(device.name))) return GLYPH_SD
    return clean(device.tran) === "usb" ? GLYPH_USB : GLYPH_DISK
}

function deviceTitle(node) {
    const vendor = clean(node.vendor), model = clean(node.model)
    if (vendor && model.toLowerCase().indexOf(vendor.toLowerCase()) < 0) return clean(vendor + " " + model)
    return model || vendor || clean(node.name)
}

function buildVolume(part, index) {
    let holder = null
    const children = part.children || []
    for (let i = 0; i < children.length; ++i)
        if (children[i] && ["crypt", "lvm"].includes(children[i].type)) { holder = children[i]; break }
    const fsNode = holder || part
    const encrypted = clean(part.fstype) === "crypto_LUKS"
    const fstype = clean(fsNode.fstype), mountpoint = exact(fsNode.mountpoint)
    const label = clean(fsNode.label) || clean(part.label) || clean(part.partlabel)
    return {
        path: exact(part.path), fsPath: exact(fsNode.path), name: exact(part.name),
        uuid: exact(fsNode.uuid) || exact(part.uuid), index: index,
        label: label, title: label || clean(part.name), fstype: fstype,
        fstypeLabel: formatFsType(fstype), sizeBytes: Number(part.size || 0),
        mountpoint: mountpoint, mounted: mountpoint !== "", encrypted: encrypted,
        unlocked: encrypted && holder !== null, fsavail: Number(fsNode.fsavail || 0),
        fssize: Number(fsNode.fssize || 0), fsused: Number(fsNode.fsused || 0)
    }
}

function isMountable(volume) {
    return !!volume && !volume.mounted && !(volume.encrypted && !volume.unlocked)
        && volume.fstype !== "" && !UNMOUNTABLE.includes(volume.fstype)
}

function buildDevice(node) {
    const children = node.children || [], parts = [], volumes = []
    for (let i = 0; i < children.length; ++i)
        if (children[i] && ["part", "crypt"].includes(children[i].type)) parts.push(children[i])
    if (parts.length === 0) {
        if (clean(node.fstype) || exact(node.mountpoint)) volumes.push(buildVolume(node, 1))
    } else {
        for (let i = 0; i < parts.length; ++i) volumes.push(buildVolume(parts[i], i + 1))
    }
    return {
        path: exact(node.path), name: exact(node.name), serial: exact(node.serial),
        title: deviceTitle(node), nickname: "", deviceName: deviceTitle(node), key: "",
        glyph: deviceGlyph(node), tran: clean(node.tran), sizeBytes: Number(node.size || 0),
        sizeText: formatBytes(node.size), volumes: volumes,
        mountedCount: volumes.filter(volume => volume.mounted).length
    }
}

function parse(raw) {
    const parsed = JSON.parse(String(raw || "{}")), devices = []
    const nodes = parsed.blockdevices || []
    for (let i = 0; i < nodes.length; ++i)
        if (isCandidateDisk(nodes[i]) && !holdsSystemMount(nodes[i])) devices.push(buildDevice(nodes[i]))
    return devices
}

function volumeMeta(volume, readOnly) {
    if (!volume) return ""
    if (volume.encrypted && !volume.unlocked) return "Encrypted · " + formatBytes(volume.sizeBytes)
    const parts = []
    if (volume.fstypeLabel) parts.push(volume.fstypeLabel)
    if (volume.mounted) {
        if (readOnly) parts.push("Read-only")
        parts.push(volume.fsavail > 0 ? formatBytes(volume.fsavail) + " free" : formatBytes(volume.sizeBytes))
        if (volume.mountpoint) parts.push(volume.mountpoint)
    } else {
        parts.push(formatBytes(volume.sizeBytes))
        if (isMountable(volume)) parts.push("Not mounted")
        else if (volume.fstype) parts.push("Not mountable")
    }
    return parts.filter(Boolean).join(" · ")
}

function mountedVolumes(devices) {
    const result = []
    for (let d = 0; d < (devices || []).length; ++d)
        for (let v = 0; v < devices[d].volumes.length; ++v)
            if (devices[d].volumes[v].mounted) result.push(devices[d].volumes[v])
    return result
}

function unescapeMountPath(value) {
    return exact(value).replace(/\\([0-7]{3})/g, (match, octal) => String.fromCharCode(parseInt(octal, 8)))
}

function parseMountFlags(raw) {
    const flags = {}, lines = String(raw || "").split("\n")
    for (let i = 0; i < lines.length; ++i) {
        const fields = lines[i].split(" ")
        if (fields.length >= 4) flags[unescapeMountPath(fields[1])] = {readOnly: fields[3].split(",").includes("ro")}
    }
    return flags
}

function isReadOnly(flags, volume) {
    if (!volume || !volume.mounted) return false
    const entry = flags ? flags[exact(volume.mountpoint)] : null
    return !!(entry && entry.readOnly)
}

function parseBlockStats(raw) {
    const result = {}, lines = String(raw || "").split("\n")
    let name = ""
    for (let i = 0; i < lines.length; ++i) {
        const header = lines[i].match(/^==>\s*\/sys\/block\/([^/]+)\/stat\s*<==/)
        if (header) { name = header[1]; continue }
        if (!name) continue
        const fields = clean(lines[i]).split(" ")
        if (fields.length >= 9) result[name] = {readSectors: Number(fields[2]), writeSectors: Number(fields[6]), inFlight: Number(fields[8])}
        name = ""
    }
    return result
}

function rateBetween(previous, current, elapsedMs) {
    if (previous === null || previous === undefined || !(elapsedMs > 0)) return 0
    const delta = Number(current) - Number(previous)
    return isFinite(delta) && delta > 0 ? delta * 512 / (elapsedMs / 1000) : 0
}

function buildActivity(previousSamples, stats, now) {
    const activity = {}, samples = {}
    for (const name in stats) {
        const current = stats[name], previous = previousSamples ? previousSamples[name] : null
        const elapsed = previous ? now - previous.at : 0
        const writeRate = rateBetween(previous ? previous.writeSectors : null, current.writeSectors, elapsed)
        const readRate = rateBetween(previous ? previous.readSectors : null, current.readSectors, elapsed)
        activity[name] = {writeRate: writeRate, readRate: readRate, inFlight: current.inFlight, busy: writeRate > 0 || current.inFlight > 0}
        samples[name] = {writeSectors: current.writeSectors, readSectors: current.readSectors, at: now}
    }
    return {activity: activity, samples: samples}
}

function formatRate(bytes) { return Number(bytes) >= 1024 ? formatBytes(bytes) + "/s" : "" }
function activityLabel(entry) {
    if (!entry) return ""
    return formatRate(entry.writeRate) ? "Writing " + formatRate(entry.writeRate)
        : formatRate(entry.readRate) ? "Reading " + formatRate(entry.readRate)
        : entry.busy ? "Busy" : ""
}

function advanceQuiet(stillBusy, ticks, required) {
    if (stillBusy) return {quietTicks: 0, run: false}
    const next = Number(ticks || 0) + 1
    return {quietTicks: next, run: next >= required}
}

function parseBlockers(raw) {
    const result = [], lines = String(raw || "").split("\n")
    for (let i = 0; i < lines.length; ++i) {
        const match = clean(lines[i]).match(/^(\d+)\s+(.+)$/)
        if (match) result.push({pid: Number(match[1]), name: match[2]})
    }
    return result
}

function describeBlockers(blockers) {
    const names = []
    for (let i = 0; i < (blockers || []).length; ++i)
        if (!names.includes(blockers[i].name)) names.push(blockers[i].name)
    return names.length <= 3 ? names.join(", ") : names.slice(0, 3).join(", ") + " and " + (names.length - 3) + " more"
}

function formatError(value) {
    let text = clean(value).replace(/^Call failed:\s*/, "")
    const match = text.match(/Error\.[A-Za-z]+:\s*(.*)$/)
    if (match) text = clean(match[1])
    return text.length > 180 ? text.slice(0, 177) + "…" : text
}

function deviceDiff(previous, current) {
    const before = {}, after = {}, added = [], removed = []
    for (let i = 0; i < (previous || []).length; ++i) before[previous[i].path] = previous[i]
    for (let i = 0; i < (current || []).length; ++i) after[current[i].path] = current[i]
    for (const path in after) if (!before[path]) added.push(after[path])
    for (const path in before) if (!after[path]) removed.push(before[path])
    return {added: added, removed: removed}
}

function connectedSummary(device) {
    if (!device) return ""
    return device.sizeText + " · " + device.volumes.length + (device.volumes.length === 1 ? " volume" : " volumes")
}

function driveKey(device) {
    if (!device) return ""
    if (exact(device.serial)) return "serial:" + exact(device.serial)
    for (let i = 0; i < device.volumes.length; ++i)
        if (exact(device.volumes[i].uuid)) return "uuid:" + exact(device.volumes[i].uuid)
    return "model:" + clean(device.title) + ":" + device.sizeBytes
}

function applyStore(devices, store) {
    const saved = store && store.drives ? store.drives : {}
    for (let i = 0; i < devices.length; ++i) {
        const key = driveKey(devices[i]), entry = saved[key] || {}, nickname = clean(entry.nickname)
        devices[i].key = key; devices[i].deviceName = devices[i].title; devices[i].nickname = nickname
        if (nickname) devices[i].title = nickname
    }
    return devices
}

function withNickname(store, device, nickname) {
    const next = {version: 1, drives: {}, notify: !(store && store.notify === false)}, source = store && store.drives ? store.drives : {}
    for (const key in source) next.drives[key] = Object.assign({}, source[key])
    const key = driveKey(device), value = clean(nickname), entry = Object.assign({}, next.drives[key] || {})
    if (value) entry.nickname = value; else delete entry.nickname
    if (Object.keys(entry).length) next.drives[key] = entry; else delete next.drives[key]
    return next
}

function withNotify(store, enabled) { return Object.assign({}, store, {notify: enabled === true}) }

function parseStore(raw) {
    try {
        const parsed = JSON.parse(String(raw || "").trim() || "{}")
        return {version: 1, drives: parsed && parsed.drives || {}, notify: !(parsed && parsed.notify === false)}
    } catch (error) { return {version: 1, drives: {}, notify: true} }
}

function isPortableType(value) { return /MTP|GPhoto2|Afc/i.test(exact(value)) }

function parseGioMounts(raw) {
    const found = [], mounts = {}, lines = String(raw || "").split("\n")
    let current = null
    function flush() {
        if (!current) return
        if ((isPortableType(current.type) || PORTABLE_URI.test(current.uri)) && clean(current.name)) {
            const uri = exact(current.uri), scheme = (uri.match(/^([a-z0-9]+):\/\//) || ["", ""])[1]
            const camera = scheme === "gphoto2" || /GPhoto2/i.test(current.type)
            found.push({name: clean(current.name), uri: uri, mounted: current.mounted,
                scheme: scheme, access: camera ? "Photos" : "Files",
                kind: PHONE_NAME.test(current.name) ? "phone" : camera ? "camera" : "phone"})
        }
        current = null
    }
    for (let i = 0; i < lines.length; ++i) {
        let match = lines[i].match(/^\s*(?:Volume|Drive)\(\d+\):\s*(.+?)\s*$/)
        if (match) { flush(); current = {name: match[1], type: "", uri: "", mounted: false}; continue }
        if (!current) continue
        match = lines[i].match(/^\s*Type:\s*(.+?)\s*$/)
        if (match) { if (!current.type) current.type = match[1]; continue }
        match = lines[i].match(/^\s*activation_root=(\S+)\s*$/)
        if (match) { if (!current.uri) current.uri = match[1]; continue }
        match = lines[i].match(/^\s*Mount\(\d+\):\s*(.*?)\s*->\s*(\S+)\s*$/)
        if (match) {
            const name = clean(match[1]); mounts[name] = match[2]
            if (name === clean(current.name)) { current.mounted = true; if (!current.uri) current.uri = match[2] }
        }
    }
    flush()
    for (let i = 0; i < found.length; ++i) {
        if (mounts[found[i].name]) { found[i].mounted = true; if (!found[i].uri) found[i].uri = mounts[found[i].name] }
        for (const name in mounts) if (found[i].uri && mounts[name] === found[i].uri) found[i].mounted = true
    }
    const merged = {}, ordered = []
    for (let i = 0; i < found.length; ++i) {
        const entry = found[i], existing = merged[entry.name]
        if (existing) {
            if (!existing.uri) existing.uri = entry.uri
            if (entry.mounted) existing.mounted = true
        } else { merged[entry.name] = entry; ordered.push(entry) }
    }
    return ordered.filter(entry => entry.uri)
}

function portableGlyph(entry) { return entry && entry.kind === "camera" ? GLYPH_CAMERA : GLYPH_PHONE }
function portableMeta(entry) { return entry ? (entry.access || "Files") + (entry.mounted ? " · mounted" : " · not mounted") : "" }

function parseSupport(raw) {
    const result = {backends: {}, devices: []}, lines = String(raw || "").split("\n")
    for (let i = 0; i < lines.length; ++i) {
        const line = clean(lines[i]), backend = line.match(/^backend\s+(\S+)$/), usb = line.match(/^usb\s+(\S+)\s*(.*)$/)
        if (backend) result.backends[backend[1]] = true
        else if (usb) { const fields = usb[1].split(","); result.devices.push({vendor: fields[0] || "", classes: fields.slice(1), name: clean(usb[2])}) }
    }
    return result
}

function supportHint(support) {
    if (!support) return ""
    for (let i = 0; i < (support.devices || []).length; ++i) {
        const device = support.devices[i]
        if (device.vendor === "05ac" && !support.backends.afc)
            return (device.name || "Apple device") + " needs usbmuxd, gvfs-afc and gvfs-gphoto2"
        if (device.classes.includes("06") && !support.backends.gphoto2 && !support.backends.mtp)
            return (device.name || "Camera") + " needs gvfs-gphoto2"
    }
    return ""
}
