.pragma library
.import "CalendarMath.js" as CalendarMath

function historyGroups(items, locale) {
  function day(date) { return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime() }
  var today = day(new Date()), groups = []
  for (var item of items) {
    var when = new Date(item.played_at || 0)
    var days = Math.round((today - day(when)) / CalendarMath.MS_PER_DAY)
    var label = days <= 0 ? "Today" : days === 1 ? "Yesterday"
      : days < 7 ? when.toLocaleDateString(locale, "dddd")
      : when.toLocaleDateString(locale, "d MMMM")
    if (!groups.length || groups[groups.length - 1].label !== label)
      groups.push({ label: label, items: [] })
    groups[groups.length - 1].items.push(item)
  }
  return groups
}

function isCliampPlayer(player) {
  var key = player ? String(player.dbusName || player.identity || "").toLowerCase() : ""
  return key.indexOf(".mpv.cliamp") !== -1 || key === "cliamp"
}

function artSource(path) {
  var value = String(path || "").replace("/hqdefault.jpg", "/mqdefault.jpg")
  return /^(https?|file):\/\//.test(value) ? value : (value ? "file://" + value : "")
}

function queueContext(override, player) {
  if (override) return override
  var key = player ? String(player.dbusName || player.identity || "").toLowerCase() : ""
  if (key.indexOf("mpd") !== -1) return "mpd"
  var url = player ? String((player.metadata || {})["xesam:url"] || "") : ""
  return url.indexOf("list=") !== -1 && /youtu(?:be\.com|\.be)\//.test(url) ? url : ""
}

function hasUpcoming(mirror) {
  var current = mirror.entries.findIndex(function(entry) { return entry.playlist_id === mirror.current })
  return mirror.entries.length > current + 1 || mirror.looping && mirror.entries.length > 1
}
function displayQueue(source, items, playing) {
  var queue = items || []
  if (source !== "cliamp" || !playing || playing.state === "stopped" || playing.title === "No track loaded")
    return queue
  return [{
    current: true, url: playing.url, title: playing.title,
    artist: playing.artist, thumb: playing.art
  }].concat(queue)
}

function likeKey(url, title, artist) {
  var target = String(url || "").trim()
  return target ? "url:" + target
    : "meta:" + String(title || "").trim().toLowerCase() + "::" + String(artist || "").trim().toLowerCase()
}
