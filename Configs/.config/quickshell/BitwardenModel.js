.pragma library

var TYPES = {
    1: { label: "Login", icon: "\u{f0306}", part: "login" },
    2: { label: "Note", icon: "\u{f039e}", part: "secureNote" },
    3: { label: "Card", icon: "\u{f0fef}", part: "card" },
    4: { label: "Identity", icon: "\u{f05d2}", part: "identity" },
    5: { label: "SSH key", icon: "\u{f08c0}", part: "sshKey" }
}
var LOGIN_TYPE = 1
var CUSTOM_FIELD_TYPE = { text: 0, hidden: 1 }

// One schema drives both the detail view and the edit form, so a field added
// here appears in both. Flags: s = secret, m = multiline.
const FIELDS = {
    1: [["login.username", "Username"], ["login.password", "Password", "s"],
        ["login.totp", "Authenticator key", "s"], ["login.uris", "Websites", "m"]],
    2: [],
    3: [["card.cardholderName", "Cardholder"], ["card.brand", "Brand"], ["card.number", "Number", "s"],
        ["card.expMonth", "Expiry month"], ["card.expYear", "Expiry year"], ["card.code", "Security code", "s"]],
    4: [["identity.title", "Title"], ["identity.firstName", "First name"], ["identity.lastName", "Last name"],
        ["identity.username", "Username"], ["identity.company", "Company"], ["identity.email", "Email"],
        ["identity.phone", "Phone"], ["identity.ssn", "Social security number", "s"],
        ["identity.passportNumber", "Passport number", "s"], ["identity.licenseNumber", "License number", "s"],
        ["identity.address1", "Address"], ["identity.address2", "Address 2"], ["identity.city", "City"],
        ["identity.state", "State"], ["identity.postalCode", "Postal code"], ["identity.country", "Country"]],
    5: [["sshKey.publicKey", "Public key", "m"], ["sshKey.keyFingerprint", "Fingerprint"],
        ["sshKey.privateKey", "Private key", "sm"]]
}

function type(item) { return TYPES[item.type] || TYPES[2] }
function editable(item) { return item.type !== 5 }

function read(item, path) {
    const value = path.split(".").reduce((node, key) => node ? node[key] : undefined, item)
    if (Array.isArray(value)) return value.map(entry => entry.uri).filter(Boolean).join("\n")
    return value === null || value === undefined ? "" : String(value)
}

function write(item, path, text) {
    const keys = path.split("."), last = keys.pop()
    const node = keys.reduce((parent, key) => parent[key] || (parent[key] = {}), item)
    const kept = Array.isArray(node[last]) ? node[last] : []
    node[last] = last === "uris" ? text.split("\n").map(uri => uri.trim()).filter(Boolean)
            .map(uri => kept.find(entry => entry.uri === uri) || { uri: uri, match: null })
        : text === "" ? null : text
}

function schema(itemType) {
    return (FIELDS[itemType] || []).concat([["notes", "Notes", "m"]])
        .map(([path, label, flags]) => ({ path: path, label: label, secret: /s/.test(flags), multiline: /m/.test(flags) }))
}

function details(item) {
    return schema(item.type).map(field => Object.assign({}, field, { value: read(item, field.path), totp: field.path === "login.totp", secret: field.secret && field.path !== "login.totp" }))
        .concat((item.fields || []).map(field => ({ label: field.name || "Field", value: field.value === null ? "" : String(field.value), secret: field.type === CUSTOM_FIELD_TYPE.hidden, multiline: false, totp: false })))
        .filter(field => field.value !== "")
}

function subtitle(item) {
    switch (item.type) {
    case 1: return read(item, "login.username") || host(read(item, "login.uris").split("\n")[0])
    case 3: return [read(item, "card.brand"), read(item, "card.number").slice(-4)].filter(Boolean).join(" •••• ")
    case 4: return [read(item, "identity.firstName"), read(item, "identity.lastName")].filter(Boolean).join(" ") || read(item, "identity.email")
    case 5: return read(item, "sshKey.keyFingerprint")
    }
    return type(item).label
}

function host(uri) { return String(uri || "").replace(/^[a-z][a-z0-9+.-]*:\/\//i, "").split(/[/:?#]/)[0].replace(/^www\./, "") }

function searchText(item, folderName) {
    return [item.name, subtitle(item), read(item, "login.uris"), read(item, "identity.email"), folderName].join(" ").toLowerCase()
}

function filter(items, needle, itemType, folderNames) {
    const words = needle.toLowerCase().split(/\s+/).filter(Boolean)
    return items.filter(item => (!itemType || item.type === itemType)
        && words.every(word => searchText(item, folderNames[item.folderId]).includes(word)))
}

// Browsers end a title with " - App name" and name their class after it, so the
// suffix is dropped and the class must match whole: otherwise "Google Chrome"
// suggests every Google login.
function suggestions(items, title, appClass) {
    const page = String(title || "").replace(/\s[-—–]\s[^-—–]+$/, "").toLowerCase(), app = String(appClass || "").toLowerCase()
    const keyword = uri => { const labels = host(uri).split("."); return labels[Math.max(0, labels.length - 2)] }
    return items.filter(item => item.type === LOGIN_TYPE && [item.name].concat(read(item, "login.uris").split("\n").map(keyword))
        .map(word => String(word || "").toLowerCase()).some(word => word.length > 2 && (page.includes(word) || word === app)))
}

function blank(itemType) {
    const item = { type: itemType, name: "", notes: null, favorite: false, folderId: null, fields: [], reprompt: 0 }
    item[TYPES[itemType].part] = itemType === 2 ? { type: 0 } : itemType === 1 ? { uris: [] } : {}
    return item
}

function send(name, text, days, maxViews, password) {
    return {
        object: "send", type: 0, name: name || "Untitled Send", notes: null, file: null,
        text: { text: text, hidden: false }, maxAccessCount: maxViews > 0 ? maxViews : null,
        deletionDate: new Date(Date.now() + Math.max(1, days) * 86400000).toISOString(), expirationDate: null,
        password: password || null, emails: null, disabled: false, hideEmail: false
    }
}

function generateArgs(options) {
    return options.passphrase
        ? ["generate", "--passphrase", "--words", String(options.words), "--separator", options.separator]
            .concat(options.capitalize ? ["--capitalize"] : [], options.number ? ["--includeNumber"] : [])
        : ["generate", "--length", String(options.length)]
            .concat(["upper", "lower", "number", "special"].filter(key => options[key]).map(key => "-" + key[0]))
}

function totpPeriod(secret) { const match = /[?&]period=(\d+)/.exec(secret); return match ? Number(match[1]) : 30 }

function lastLine(text) { return String(text || "").trim().split("\n").pop() }
