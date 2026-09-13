.pragma library

function keywordAction(bookmarks, value) {
  var input = String(value || "").trim(), space = input.search(/\s/)
  if (space < 1) return null
  var keyword = input.substring(0, space).toLowerCase(), terms = input.substring(space).trim()
  if (!terms) return null
  for (var i = 0; i < bookmarks.length; i++) {
    var bookmark = bookmarks[i], url = String(bookmark.url || "")
    if (String(bookmark.keyword || "").toLowerCase() === keyword && parameterizedUrl(url))
      return { bookmark: bookmark, terms: terms }
  }
  return null
}

function resolvedUrl(bookmark, action) {
  if (!action || action.bookmark.id !== bookmark.id) return bookmark.url
  var terms = action.terms, encoded = encodeURIComponent(terms)
  return String(bookmark.url).replace(/%s/g, encoded).replace(/%S/g, terms)
    .replace(/\{searchTerms\}/g, encoded)
}

function title(bookmark) {
  var value = String(bookmark && bookmark.title || "").trim()
  if (value) return value
  var url = String(bookmark && bookmark.url || ""), match = url.match(/^https?:\/\/([^\/?#]+)/i)
  return match ? match[1] : url
}

function parameterizedUrl(url) {
  var value = String(url || "")
  return value.indexOf("%s") !== -1 || value.indexOf("%S") !== -1
    || value.indexOf("{searchTerms}") !== -1
}

function tags(bookmarks) {
  var byName = {}, items = []
  for (var i = 0; i < bookmarks.length; i++) {
    var values = bookmarks[i].tags || [], seen = {}
    for (var j = 0; j < values.length; j++) {
      var name = String(values[j] || "").trim(), key = name.toLowerCase()
      if (!key || seen[key]) continue
      seen[key] = true
      if (byName[key]) byName[key].count++
      else items.push(byName[key] = { tag: name, count: 1 })
    }
  }
  return items.sort(function(a, b) {
    return b.count - a.count || a.tag.toLowerCase().localeCompare(b.tag.toLowerCase())
  })
}

function matchingTags(items, value) {
  var search = String(value || "").trim().toLowerCase()
  if (!search) return items
  var prefix = [], substring = []
  for (var i = 0; i < items.length; i++) {
    var tag = items[i].tag.toLowerCase()
    if (tag.indexOf(search) === 0) prefix.push(items[i])
    else if (tag.indexOf(search) !== -1) substring.push(items[i])
  }
  return prefix.concat(substring)
}

function keywords(bookmarks) {
  var seen = {}, items = []
  for (var i = 0; i < bookmarks.length; i++) {
    var bookmark = bookmarks[i], keyword = String(bookmark.keyword || "").trim()
    var key = keyword.toLowerCase()
    if (!key || seen[key]) continue
    seen[key] = true
    items.push({ keyword: keyword, bookmark: bookmark, parameterized: parameterizedUrl(bookmark.url) })
  }
  return items.sort(function(a, b) {
    return a.keyword.toLowerCase().localeCompare(b.keyword.toLowerCase())
  })
}

function matchingKeywords(items, value) {
  var search = String(value || "").trim().toLowerCase()
  if (!search) return items
  var prefix = [], substring = []
  for (var i = 0; i < items.length; i++) {
    var item = items[i], keyword = item.keyword.toLowerCase()
    var searchable = (item.keyword + " " + title(item.bookmark) + " " + item.bookmark.url).toLowerCase()
    if (keyword.indexOf(search) === 0) prefix.push(item)
    else if (searchable.indexOf(search) !== -1) substring.push(item)
  }
  return prefix.concat(substring)
}

function parsedSearch(value) {
  var source = String(value || "").trim().toLowerCase(), normal = [], tags = []
  source = source ? source.split(/\s+/) : []
  for (var i = 0; i < source.length; i++)
    (source[i].charAt(0) === "#" ? tags : normal).push(source[i].replace(/^#/, ""))
  return { normalTokens: normal, tagTokens: tags, normalSearch: normal.join(" ") }
}

function tagPrefixMatch(bookmark, prefix) {
  for (var i = 0; i < bookmark.tags.length; i++)
    if (String(bookmark.tags[i]).toLowerCase().indexOf(prefix) === 0) return true
  return false
}

function relevance(bookmark, search, tokens, tagTokens) {
  var titleText = String(bookmark.title || "").toLowerCase()
  var keyword = String(bookmark.keyword || "").toLowerCase()
  var url = String(bookmark.url || "").toLowerCase(), score = 0
  if (search) {
    if (keyword === search) score += 500
    if (titleText === search) score += 450
    else if (titleText.indexOf(search) === 0) score += 300
    if (keyword && keyword.indexOf(search) === 0) score += 280
    if (url.indexOf(search) !== -1) score += 100
  }
  for (var i = 0; i < tokens.length; i++) {
    if (titleText.indexOf(tokens[i]) === 0) score += 30
    else if (titleText.indexOf(tokens[i]) !== -1) score += 20
    if (keyword === tokens[i]) score += 25
  }
  for (var j = 0; j < tagTokens.length; j++) {
    if (!tagTokens[j]) continue
    for (var k = 0; k < bookmark.tags.length; k++) {
      var tag = String(bookmark.tags[k]).toLowerCase()
      if (tag === tagTokens[j]) { score += 90; break }
      if (tag.indexOf(tagTokens[j]) === 0) { score += 45; break }
    }
  }
  return score
}

function filteredBookmarks(bookmarks, value, action, usageStore) {
  if (action) return [action.bookmark]
  var parsed = parsedSearch(value), search = parsed.normalSearch, tagTokens = parsed.tagTokens
  var ranked = [], now = Date.now()
  for (var i = 0; i < bookmarks.length; i++) {
    var bookmark = bookmarks[i]
    var searchable = (String(bookmark.title || "") + " " + bookmark.url + " "
      + bookmark.tags.join(" ") + " " + String(bookmark.keyword || "")).toLowerCase()
    var matches = parsed.normalTokens.every(function(token) { return searchable.indexOf(token) !== -1 })
      && tagTokens.every(function(tag) { return tagPrefixMatch(bookmark, tag) })
    if (!matches) continue
    ranked.push({
      bookmark: bookmark,
      relevance: search || tagTokens.length ? relevance(bookmark, search, parsed.normalTokens, tagTokens) : 0,
      usage: usageStore.usageScoreAt(bookmark, now),
      originalIndex: i
    })
  }
  ranked.sort(function(a, b) {
    return b.relevance - a.relevance
      || (Math.abs(a.usage - b.usage) > 0.0000001 ? b.usage - a.usage : a.originalIndex - b.originalIndex)
  })
  return ranked.map(function(item) { return item.bookmark })
}
