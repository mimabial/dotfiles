pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "BitwardenModel.js" as Model

// The vault, once per shell; every bar's popup is a view of it. Secrets reach
// bw through the environment or stdin, never argv. Both runtime files live in
// XDG_RUNTIME_DIR, so neither survives logout nor ever touches the disk.
Item {
    id: root
    required property var shell
    // "" until probed, then bw's "unauthenticated" | "locked" | "unlocked", or "missing"
    property string status: ""
    property string email: ""
    property string session: ""
    property string error: ""
    property string notice: ""
    property int pending: 0
    readonly property bool busy: pending > 0
    property var items: []
    property var folders: []
    readonly property var folderNames: folders.reduce((names, folder) => Object.assign(names, { [folder.id]: folder.name }), ({}))
    property var unlockMethods: ["pin"]
    property int pinFailures: 0
    property string copied: ""
    readonly property alias settings: settingsAdapter
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string unlockFile: runtimeDir + "/bitwarden-unlock"
    readonly property string pinCipher: "openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -a -A -pass env:PIN"
    readonly property string prompt: pam.active ? pam.message : ""

    // A job whose session changed underneath it answers for a vault that is gone.
    function sh(script, args, done, env) {
        const asked = session
        const job = jobComponent.createObject(root, {
            command: ["bash", "-c", script, "bitwarden"].concat(args || []),
            environment: Object.assign({ BW_SESSION: session || null, BW_NOINTERACTION: "true" }, env || {})
        })
        // counted down after `done`, so a job it chains keeps `busy` up without a gap
        job.exited.connect(code => {
            try { if (done && asked === session) done(code, job.stdout.text, job.stderr.text) }
            finally { --pending; job.destroy() }
        })
        ++pending
        job.running = true
    }
    function bw(args, done, env) { sh('bw "$@"', args, done, env) }
    function failed(code, err) {
        if (!code) return false
        error = Model.lastLine(err) || "bw exited with " + code
        if (/locked|not logged in/i.test(error)) probe()
        return true
    }
    Component { id: jobComponent; Process { stdout: StdioCollector {} stderr: StdioCollector {} } }

    function adopt(key) {
        session = key
        if (key) status = "unlocked"
        else {
            items = []; folders = []
            if (status === "unlocked") status = "locked"
        }
        touch()
        if (shell.popupName === "bitwarden") prepare()
    }
    function forget() {
        sessionFile.setText("")
        totpFollowUp.stop()
        clearClipboard()
        adopt("")
    }
    function prepare() {
        touch()
        if (status === "unlocked") { if (!items.length) load() }
        else if (status === "locked") scan()
        else probe()
    }
    function release() { if (pam.active) pam.abort(); notice = ""; touch() }
    function probe() {
        bw(["status"], (code, out) => {
            if (code === 127) { status = "missing"; return }
            const state = JSON.parse(out)
            email = state.userEmail || ""
            if (state.status !== "unlocked" && session) forget()
            status = state.status
            if (status === "unlocked") load()
            else if (status === "locked" && shell.popupName === "bitwarden") scan()
        })
    }
    function load() {
        bw(["list", "items"], (code, out, err) => {
            if (!failed(code, err)) items = JSON.parse(out).sort((a, b) => a.name.localeCompare(b.name))
        })
        bw(["list", "folders"], (code, out) => { if (!code) folders = JSON.parse(out).filter(folder => folder.id) })
    }
    function sync() { bw(["sync"], (code, out, err) => { if (!failed(code, err)) load() }) }
    function lock() {
        if (!session) return
        bw(["lock"])
        forget()
    }
    function logout() {
        bw(["logout"], () => { forget(); disarm(); status = "unauthenticated"; email = "" })
    }
    function terminal(title, script, args) {
        Quickshell.execDetached(["hyprshell", "launch/terminal-present", "--app-id", "org.hypr.Bitwarden", "--title", title, "--",
            "bash", "-c", script + " && quickshell ipc call bitwarden reload", "bitwarden"].concat(args || []))
    }
    // bw keeps its prompts on stderr, so --raw hands only the session key over.
    function authenticate(verb, server) {
        terminal("Bitwarden " + verb, '[ -z "$2" ] || bw config server "$2" || exit; umask 077; bw "$1" --raw > "$3"',
            [verb, server, sessionFile.path])
    }
    function install() { terminal("Install Bitwarden CLI", "hyprshell pm add bitwarden-cli") }

    // `stored` unlocks from the armed secret; `arm` stores the password that just
    // proved itself, so a quick unlock never holds a stale one.
    function unlock(env, stored, arm) {
        error = ""
        const decode = settings.quickUnlock === "pin" ? pinCipher + " -d" : "cat"
        const script = stored
            ? '[ -s "$1" ] || exit 3; BW_PASSWORD="$(' + decode + ' < "$1")" || exit 5; export BW_PASSWORD; bw unlock --passwordenv BW_PASSWORD --raw'
            : 'bw unlock --passwordenv BW_PASSWORD --raw || exit 1'
                + (arm ? '; (umask 077; printf %s "$BW_PASSWORD" | ' + (arm === "pin" ? pinCipher : "cat") + ' > "$1") || exit 4' : "")
        sh(script, [unlockFile], (code, out, err) => {
            if (code === 0 || code === 4) {
                sessionFile.setText(out.trim())
                adopt(out.trim())
                pinFailures = 0
                if (arm) settings.quickUnlock = code ? "" : arm
                if (code) error = "Unlocked, but quick unlock could not be armed"
                return
            }
            error = code === 3 ? "Unlock with your master password once to arm quick unlock"
                : code === 5 ? "Wrong PIN" : Model.lastLine(err) || "Unlock failed"
            if (stored && code !== 3 && (settings.quickUnlock !== "pin" || ++pinFailures >= 3)) {
                sh('rm -f "$1"', [unlockFile])
                pinFailures = 0
                error += " — quick unlock disarmed, use your master password"
            }
        }, env)
    }
    function disarm() { sh('rm -f "$1"', [unlockFile]); settings.quickUnlock = ""; pinFailures = 0 }
    function scan() { if (!pam.active && ["fingerprint", "fido2"].includes(settings.quickUnlock)) pam.start() }
    function detectUnlockMethods() {
        sh('fprintd-list "$USER" 2>/dev/null | grep -q " - #" && echo fingerprint; [ -s /etc/fido2/fido2 ] && echo fido2', [],
            (code, out) => unlockMethods = ["pin"].concat(out.split("\n").filter(Boolean)))
    }

    function touch() {
        if (session && settings.autoLockMinutes > 0) idleLock.restart()
        else idleLock.stop()
    }
    function copy(value, label) {
        if (!value) return
        copied = value
        sh('printf %s "$VALUE" | wl-copy --sensitive >/dev/null 2>&1', [], null, { VALUE: value })
        if (settings.clearClipboardSeconds > 0) clipboardClear.restart()
        notice = label + " copied"
        touch()
    }
    function clearClipboard() {
        clipboardClear.stop()
        if (copied) sh('[ "$(wl-paste -n 2>/dev/null)" = "$VALUE" ] && wl-copy --clear', [], null, { VALUE: copied })
        copied = ""
    }
    function totp(item, done) { bw(["get", "totp", item.id], (code, out, err) => { if (!failed(code, err)) done(out.trim()) }) }
    function copyTotp(item) { totp(item, code => copy(code, "TOTP code")) }
    function copyPassword(item) {
        copy(Model.read(item, "login.password"), "Password")
        if (!Model.read(item, "login.totp") || settings.autoCopyTotpSeconds <= 0) return
        totpFollowUp.item = item
        totpFollowUp.restart()
    }

    function save(item, done) {
        sh('printf %s "$ITEM" | base64 -w0 | bw ' + (item.id ? 'edit item "$1"' : "create item"), item.id ? [item.id] : [], (code, out, err) => {
            if (failed(code, err)) return
            const saved = JSON.parse(out)
            items = items.filter(entry => entry.id !== saved.id).concat([saved]).sort((a, b) => a.name.localeCompare(b.name))
            done(saved)
        }, { ITEM: JSON.stringify(item) })
    }
    function remove(item) {
        bw(["delete", "item", item.id], (code, out, err) => { if (!failed(code, err)) items = items.filter(entry => entry.id !== item.id) })
    }
    function createSend(payload) {
        sh('printf %s "$SEND" | base64 -w0 | bw send create', [], (code, out, err) => {
            if (!failed(code, err)) copy(JSON.parse(out).accessUrl, "Send link")
        }, { SEND: JSON.stringify(payload) })
    }
    function download(item, attachment) {
        sh('dir="$(xdg-user-dir DOWNLOAD 2>/dev/null)"; dir="${dir:-$HOME/Downloads}"; mkdir -p "$dir" && bw get attachment "$1" --itemid "$2" --output "$dir/" >/dev/null && printf %s "$dir/$3"',
            [attachment.id, item.id, attachment.fileName], (code, out, err) => { if (!failed(code, err)) notice = "Saved " + out })
    }
    function generate(options, done) { bw(Model.generateArgs(options), (code, out, err) => { if (!failed(code, err)) done(out.trim()) }) }

    FileView {
        id: sessionFile
        path: root.runtimeDir + "/bitwarden-session"
        printErrors: false
        onLoaded: root.adopt(text().trim())
        onLoadFailed: root.adopt("")
    }
    FileView {
        path: root.shell.home + "/.local/state/quickshell/bitwarden.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()
        JsonAdapter {
            id: settingsAdapter
            property int autoLockMinutes: 15
            property int clearClipboardSeconds: 30
            property int autoCopyTotpSeconds: 3
            property bool closeOnCopy: true
            property bool lockWithScreen: true
            property bool suggest: true
            // "" | "pin" | "fingerprint" | "fido2"
            property string quickUnlock: ""
        }
    }
    PamContext {
        id: pam
        configDirectory: Quickshell.shellDir + "/pam"
        config: "bitwarden-" + root.settings.quickUnlock
        onCompleted: result => {
            if (result === PamResult.Success) root.unlock({}, true)
            else root.error = "Not verified"
        }
        onError: error => root.error = PamError.toString(error)
    }
    Timer { id: idleLock; interval: Math.max(1, root.settings.autoLockMinutes) * 60000; onTriggered: root.lock() }
    Timer { id: clipboardClear; interval: root.settings.clearClipboardSeconds * 1000; onTriggered: root.clearClipboard() }
    Timer { id: totpFollowUp; property var item; interval: root.settings.autoCopyTotpSeconds * 1000; onTriggered: root.copyTotp(item) }

    IpcHandler {
        target: "bitwarden"
        function lock(): void { root.lock() }
        function screenLocked(): void { if (root.settings.lockWithScreen) root.lock() }
        // the terminal login/install hand-off: re-read the session and show the result
        function reload(): void {
            root.status = ""
            sessionFile.reload()
            if (root.shell.popupName !== "bitwarden") root.shell.togglePopup("bitwarden", true)
        }
    }
}
