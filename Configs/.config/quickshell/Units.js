.pragma library

var SECONDS_PER_MINUTE = 60
var SECONDS_PER_HOUR = 60 * SECONDS_PER_MINUTE
var SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR
var BYTE_UNITS = ["B", "KB", "MB", "GB", "TB", "PB"]

function bytesParts(bytes) {
    var scaled = Number(bytes)
    if (!isFinite(scaled) || scaled < 0) scaled = 0
    var unitIndex = 0
    while (scaled >= 1024 && unitIndex < BYTE_UNITS.length - 1) { scaled /= 1024; unitIndex++ }
    var text
    if (unitIndex <= 1 || scaled >= 100) text = String(Math.round(scaled))
    else text = scaled.toFixed(1)
    return { value: text, unit: BYTE_UNITS[unitIndex] }
}

function bytesText(bytes) {
    var parts = bytesParts(bytes)
    return parts.value + " " + parts.unit
}

function spanText(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    var days = Math.floor(total / SECONDS_PER_DAY)
    var hours = Math.floor(total % SECONDS_PER_DAY / SECONDS_PER_HOUR)
    var minutes = Math.floor(total % SECONDS_PER_HOUR / SECONDS_PER_MINUTE)
    if (days) return days + "d " + hours + "h"
    if (hours) return hours + "h " + minutes + "m"
    return minutes ? minutes + "m" : ""
}

function largestUnitText(seconds) {
    if (seconds >= SECONDS_PER_DAY) return Math.floor(seconds / SECONDS_PER_DAY) + "d"
    if (seconds >= SECONDS_PER_HOUR) return Math.floor(seconds / SECONDS_PER_HOUR) + "h"
    return seconds >= SECONDS_PER_MINUTE ? Math.floor(seconds / SECONDS_PER_MINUTE) + "m" : ""
}

function clockText(seconds) {
    var total = Math.max(0, Math.floor(seconds))
    var hours = Math.floor(total / SECONDS_PER_HOUR), minutes = Math.floor(total % SECONDS_PER_HOUR / SECONDS_PER_MINUTE)
    var secondsText = String(total % SECONDS_PER_MINUTE).padStart(2, "0")
    return hours ? hours + ":" + String(minutes).padStart(2, "0") + ":" + secondsText : minutes + ":" + secondsText
}
