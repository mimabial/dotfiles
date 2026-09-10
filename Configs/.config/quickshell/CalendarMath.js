.pragma library

function isoDay(date) { return Qt.formatDate(date, "yyyy-MM-dd") }
function fromIsoDay(value) { return new Date(String(value) + "T12:00:00") }
function sameDay(left, right) {
    return left.getFullYear() === right.getFullYear()
        && left.getMonth() === right.getMonth() && left.getDate() === right.getDate()
}
function startOfWeek(date, firstWeekday) {
    const start = new Date(date.getFullYear(), date.getMonth(), date.getDate())
    start.setDate(start.getDate() - ((start.getDay() - firstWeekday + 7) % 7))
    return start
}
function isoWeek(date) {
    const day = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    day.setUTCDate(day.getUTCDate() - ((day.getUTCDay() + 6) % 7) + 3)
    const firstThursday = new Date(Date.UTC(day.getUTCFullYear(), 0, 4))
    firstThursday.setUTCDate(firstThursday.getUTCDate() - ((firstThursday.getUTCDay() + 6) % 7) + 3)
    return 1 + Math.round((day - firstThursday) / 604800000)
}
function relativeDayLabel(value, today) {
    const todayIso = isoDay(today)
    if (value === todayIso) return "Today"
    const gap = Math.round((fromIsoDay(value) - fromIsoDay(todayIso)) / 86400000)
    return gap === 1 ? "Tomorrow" : gap === -1 ? "Yesterday" : ""
}
function isWeekend(value) {
    const weekday = fromIsoDay(value).getDay()
    return weekday === 0 || weekday === 6
}
function previousDay(value) {
    if (!value) return ""
    const date = fromIsoDay(value)
    date.setDate(date.getDate() - 1)
    return isoDay(date)
}
function rawDate(value) {
    const text = String(value)
    return text.length < 8 ? "" : text.slice(0, 4) + "-" + text.slice(4, 6) + "-" + text.slice(6, 8)
}
function rawTime(value) {
    const text = String(value)
    const separator = text.indexOf("T")
    return separator < 0 ? "" : text.slice(separator + 1, separator + 3) + ":" + text.slice(separator + 3, separator + 5)
}
function enteredValue(value) {
    const compact = String(value).replace(/\s/g, "")
    return /\d/.test(compact) ? compact : ""
}
