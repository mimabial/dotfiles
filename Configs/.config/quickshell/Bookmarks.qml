import QtQuick
import Quickshell
import Quickshell.Io
import "Commons" as Commons
import "Ui" as Ui

Item {
  id: root

  required property var shell
  required property Item anchorItem
  property bool popupEnabled: true
  readonly property bool opened: popup.open
  property string query: ""
  property int viewMode: 0
  property string tagQuery: ""
  property string keywordQuery: ""
  property int selectedIndex: 0
  property bool deleteConfirmOpen: false
  property var deleteTarget: null
  property bool fileDialogOpen: false
  property bool quickAdding: false
  property bool quickAddCanceled: false
  property string statusMessage: ""
  property var browserTarget: null
  property string copyTargetTitle: ""
  property bool networkEnrichmentEnabled: false
  property bool networkSettingStateReady: false
  property bool networkDialogOpen: false
  property string networkSettingOperation: ""
  property var quickAddResult: null
  property string quickAddResponseError: ""
  property var copyResponse: null
  property var networkStatusResponse: null
  property var networkSettingResponse: null
  property var firefoxSyncResponse: null
  property bool firefoxSyncPending: false
  property string importPickerPath: ""

  readonly property string helperPath:
    Quickshell.env("HOME") + "/.local/lib/hypr/bookmarks/bookmark_helper.py"

  readonly property string settingsPath:
    store.dataDir + "/settings.json"

  readonly property int maxQuickAddOutputCharacters: 512 * 1024

  onShellChanged: {
    Commons.Style.shell = root.shell
    Commons.Color.shell = root.shell
  }

  readonly property var keywordAction:
    root.opened && root.viewMode === 0
      ? root.resolveKeywordAction(root.query)
      : null

  readonly property var filteredBookmarks:
    root.opened && root.viewMode === 0
      ? root.bookmarksForQuery(root.query)
      : []

  readonly property var allTags:
    root.opened && root.viewMode === 1 ? root.collectTags() : []

  readonly property var filteredTags:
    root.opened && root.viewMode === 1 ? root.tagsForQuery(root.tagQuery) : []

  readonly property var allKeywords:
    root.opened && root.viewMode === 2 ? root.collectKeywords() : []

  readonly property var filteredKeywords:
    root.opened && root.viewMode === 2
      ? root.keywordsForQuery(root.keywordQuery)
      : []

  readonly property var activeResults:
    !root.opened
      ? []
      : root.viewMode === 1
      ? root.filteredTags
      : root.viewMode === 2
        ? root.filteredKeywords
        : root.filteredBookmarks

  readonly property int activeTotal:
    root.viewMode === 1
      ? root.allTags.length
      : root.viewMode === 2
        ? root.allKeywords.length
        : store.bookmarks.length

  readonly property string viewName:
    root.viewMode === 1
      ? "Tags"
      : root.viewMode === 2
        ? "Keywords"
        : "Bookmarks"

  function parseSmallHelperResponse(data) {
    var output = String(data || "")
    if (output.length > 64 * 1024)
      throw new Error("Helper returned too much data")
    return JSON.parse(output)
  }

  function syncFirefox() {
    if (!root.opened)
      return
    if (!store.storageReady || !store.loaded || store.saving) {
      root.firefoxSyncPending = true
      return
    }
    if (store.pendingUsageOpens) {
      root.firefoxSyncPending = true
      store.flushUsage()
      return
    }
    if (firefoxSyncProcess.running)
      return
    root.firefoxSyncPending = false
    root.firefoxSyncResponse = null
    root.statusMessage = "Syncing Firefox…"
    firefoxSyncProcess.command = [
      "python3", root.helperPath,
      "firefox-sync", store.dataPath
    ]
    firefoxSyncProcess.running = true
  }

  function resolveKeywordAction(value) {
    var input = String(value || "").trim()
    var space = input.search(/\s/)
    if (space < 1)
      return null
    var keyword = input.substring(0, space).toLowerCase()
    var terms = input.substring(space).trim()
    if (!terms)
      return null
    for (var i = 0; i < store.bookmarks.length; i++) {
      var bookmark = store.bookmarks[i]
      var template = String(bookmark.url || "")
      if (String(bookmark.keyword || "").toLowerCase() === keyword
          && (template.indexOf("%s") !== -1
              || template.indexOf("%S") !== -1
              || template.indexOf("{searchTerms}") !== -1)) {
        return {bookmark: bookmark, terms: terms}
      }
    }
    return null
  }

  function resolvedUrl(bookmark) {
    if (!root.keywordAction || root.keywordAction.bookmark.id !== bookmark.id)
      return bookmark.url
    var terms = root.keywordAction.terms
    var encoded = encodeURIComponent(terms)
    return String(bookmark.url)
      .replace(/%s/g, encoded)
      .replace(/%S/g, terms)
      .replace(/\{searchTerms\}/g, encoded)
  }

  function displayTitle(bookmark) {
    var title = String(bookmark && bookmark.title || "").trim()
    if (title)
      return title
    var match = String(bookmark && bookmark.url || "").match(/^https?:\/\/([^\/?#]+)/i)
    return match ? match[1] : String(bookmark && bookmark.url || "")
  }

  function isParameterized(bookmark) {
    var url = String(bookmark && bookmark.url || "")
    return url.indexOf("%s") !== -1
      || url.indexOf("%S") !== -1
      || url.indexOf("{searchTerms}") !== -1
  }

  function collectTags() {
    var byName = {}
    var items = []

    for (var i = 0; i < store.bookmarks.length; i++) {
      var tags = store.bookmarks[i].tags || []
      var seenOnBookmark = {}
      for (var j = 0; j < tags.length; j++) {
        var name = String(tags[j] || "").trim()
        var key = name.toLowerCase()
        if (!key || seenOnBookmark[key])
          continue
        seenOnBookmark[key] = true
        if (byName[key]) {
          byName[key].count += 1
        } else {
          var item = {tag: name, count: 1}
          byName[key] = item
          items.push(item)
        }
      }
    }

    items.sort(function(first, second) {
      if (first.count !== second.count)
        return second.count - first.count
      return first.tag.toLowerCase().localeCompare(second.tag.toLowerCase())
    })
    return items
  }

  function tagsForQuery(value) {
    var search = String(value || "").trim().toLowerCase()
    if (!search)
      return root.allTags

    var prefix = []
    var substring = []
    for (var i = 0; i < root.allTags.length; i++) {
      var item = root.allTags[i]
      var tag = item.tag.toLowerCase()
      if (tag.indexOf(search) === 0)
        prefix.push(item)
      else if (tag.indexOf(search) !== -1)
        substring.push(item)
    }
    return prefix.concat(substring)
  }

  function collectKeywords() {
    var seen = {}
    var items = []

    for (var i = 0; i < store.bookmarks.length; i++) {
      var bookmark = store.bookmarks[i]
      var keyword = String(bookmark.keyword || "").trim()
      var key = keyword.toLowerCase()
      if (!key || seen[key])
        continue
      seen[key] = true
      items.push({
        keyword: keyword,
        bookmark: bookmark,
        parameterized: root.isParameterized(bookmark)
      })
    }

    items.sort(function(first, second) {
      return first.keyword.toLowerCase().localeCompare(
        second.keyword.toLowerCase()
      )
    })
    return items
  }

  function keywordsForQuery(value) {
    var search = String(value || "").trim().toLowerCase()
    if (!search)
      return root.allKeywords

    var prefix = []
    var substring = []
    for (var i = 0; i < root.allKeywords.length; i++) {
      var item = root.allKeywords[i]
      var keyword = item.keyword.toLowerCase()
      var searchable = (
        item.keyword + " "
        + root.displayTitle(item.bookmark) + " "
        + item.bookmark.url
      ).toLowerCase()
      if (keyword.indexOf(search) === 0)
        prefix.push(item)
      else if (searchable.indexOf(search) !== -1)
        substring.push(item)
    }
    return prefix.concat(substring)
  }

  function currentQuery() {
    if (root.viewMode === 1)
      return root.tagQuery
    if (root.viewMode === 2)
      return root.keywordQuery
    return root.query
  }

  function setCurrentQuery(value) {
    if (root.viewMode === 1)
      root.tagQuery = value
    else if (root.viewMode === 2)
      root.keywordQuery = value
    else
      root.query = value
  }

  function modePlaceholder() {
    if (root.viewMode === 1)
      return "Search tags…"
    if (root.viewMode === 2)
      return "Search keywords…"
    return "Search bookmarks…"
  }

  function cycleView(amount) {
    root.viewMode = ((root.viewMode + amount) % 3 + 3) % 3
    root.selectedIndex = 0
    bookmarkList.positionViewAtBeginning()
  }

  function selectedResult() {
    if (
      root.selectedIndex < 0
      || root.selectedIndex >= root.activeResults.length
    ) {
      return null
    }
    return root.activeResults[root.selectedIndex]
  }

  function applyPickerSelection(append) {
    var item = root.selectedResult()
    if (!item || root.viewMode === 0)
      return

    var token = root.viewMode === 1
      ? "#" + item.tag
      : item.keyword
    var previous = root.query.trim()
    root.query = append && previous
      ? previous + " " + token
      : token

    if (!append && root.viewMode === 2 && item.parameterized)
      root.query += " "

    if (root.viewMode === 1)
      root.tagQuery = ""
    else
      root.keywordQuery = ""
    root.viewMode = 0
    root.selectedIndex = 0
    bookmarkList.positionViewAtBeginning()
  }

  function parseSearch(value) {
    var input = String(value || "").trim().toLowerCase()
    var source = input ? input.split(/\s+/) : []
    var normalTokens = []
    var tagTokens = []
    for (var i = 0; i < source.length; i++) {
      if (source[i].charAt(0) === "#")
        tagTokens.push(source[i].substring(1))
      else
        normalTokens.push(source[i])
    }
    return {
      normalTokens: normalTokens,
      tagTokens: tagTokens,
      normalSearch: normalTokens.join(" ")
    }
  }

  function tagPrefixMatch(bookmark, prefix) {
    for (var i = 0; i < bookmark.tags.length; i++) {
      if (String(bookmark.tags[i]).toLowerCase().indexOf(prefix) === 0)
        return true
    }
    return false
  }

  function searchRelevance(bookmark, search, tokens, tagTokens) {
    var title = String(bookmark.title || "").toLowerCase()
    var keyword = String(bookmark.keyword || "").toLowerCase()
    var url = String(bookmark.url || "").toLowerCase()
    var score = 0

    if (search) {
      if (keyword === search)
        score += 500
      if (title === search)
        score += 450
      else if (title.indexOf(search) === 0)
        score += 300
      if (keyword && keyword.indexOf(search) === 0)
        score += 280
      if (url.indexOf(search) !== -1)
        score += 100
    }

    for (var i = 0; i < tokens.length; i++) {
      if (title.indexOf(tokens[i]) === 0)
        score += 30
      else if (title.indexOf(tokens[i]) !== -1)
        score += 20
      if (keyword === tokens[i])
        score += 25
    }

    for (var j = 0; j < tagTokens.length; j++) {
      if (!tagTokens[j])
        continue
      for (var k = 0; k < bookmark.tags.length; k++) {
        var tag = String(bookmark.tags[k]).toLowerCase()
        if (tag === tagTokens[j]) {
          score += 90
          break
        }
        if (tag.indexOf(tagTokens[j]) === 0) {
          score += 45
          break
        }
      }
    }
    return score
  }

  function bookmarksForQuery(value) {
    if (root.keywordAction)
      return [root.keywordAction.bookmark]

    var parsed = root.parseSearch(value)
    var search = parsed.normalSearch
    var tokens = parsed.normalTokens
    var tagTokens = parsed.tagTokens
    var now = Date.now()
    var ranked = []

    for (var i = 0; i < store.bookmarks.length; i++) {
      var bookmark = store.bookmarks[i]
      var searchable = (
        String(bookmark.title || "") + " "
        + bookmark.url + " "
        + bookmark.tags.join(" ") + " "
        + String(bookmark.keyword || "")
      ).toLowerCase()
      var matches = true

      for (var j = 0; j < tokens.length; j++) {
        if (searchable.indexOf(tokens[j]) === -1) {
          matches = false
          break
        }
      }
      for (var k = 0; matches && k < tagTokens.length; k++) {
        if (!root.tagPrefixMatch(bookmark, tagTokens[k]))
          matches = false
      }
      if (!matches)
        continue

      ranked.push({
        bookmark: bookmark,
        relevance: search || tagTokens.length
          ? root.searchRelevance(bookmark, search, tokens, tagTokens)
          : 0,
        usage: store.usageScoreAt(bookmark, now),
        originalIndex: i
      })
    }

    ranked.sort(function(first, second) {
      if (first.relevance !== second.relevance)
        return second.relevance - first.relevance
      if (Math.abs(first.usage - second.usage) > 0.0000001)
        return second.usage - first.usage
      return first.originalIndex - second.originalIndex
    })

    var results = []
    for (var resultIndex = 0; resultIndex < ranked.length; resultIndex++)
      results.push(ranked[resultIndex].bookmark)
    return results
  }

  onActiveResultsChanged: {
    root.selectedIndex = Math.max(
      0,
      Math.min(
        root.selectedIndex,
        root.activeResults.length - 1
      )
    )
  }

  function open(payloadJson) {
    root.query = ""
    root.viewMode = 0
    root.tagQuery = ""
    root.keywordQuery = ""
    root.selectedIndex = 0
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    root.fileDialogOpen = false
    root.statusMessage = ""
    root.quickAddCanceled = quickAddProcess.running
    root.browserTarget = null
    root.copyTargetTitle = ""
    root.networkDialogOpen = false
    editor.close()
    importer.close()
    browserPicker.close()
    root.shell.popupName = "bookmarks"

    root.refocusList()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("")
  }

  function close() {
    statusTimer.stop()
    if (importPickerProcess.running)
      importPickerProcess.running = false
    root.fileDialogOpen = false
    if (quickAddProcess.running) {
      root.quickAddCanceled = true
      quickAddProcess.running = false
    } else {
      root.quickAdding = false
    }
    root.quickAddResult = null
    root.quickAddResponseError = ""
    if (root.shell.popupName === "bookmarks")
      root.shell.closePopup()
    root.query = ""
    root.viewMode = 0
    root.tagQuery = ""
    root.keywordQuery = ""
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    root.statusMessage = ""
    root.browserTarget = null
    root.copyTargetTitle = ""
    root.networkDialogOpen = false
    editor.close()
    importer.close()
    browserPicker.close()
  }

  function dismiss() {
    root.close()
  }

  onOpenedChanged: {
    if (root.opened) {
      root.refocusList()
      root.syncFirefox()
    } else {
      root.close()
    }
  }

  function selectedBookmark() {
    if (root.viewMode !== 0)
      return null

    if (
      root.selectedIndex < 0
      || root.selectedIndex >= root.filteredBookmarks.length
    ) {
      return null
    }

    return root.filteredBookmarks[root.selectedIndex]
  }

  function refocusList() {
    Qt.callLater(function() {
      if (
        root.opened
        && !editor.opened
        && !importer.opened
        && !browserPicker.opened
        && !root.networkDialogOpen
        && !root.deleteConfirmOpen
      ) {
        keyCatcher.forceActiveFocus()
      }
    })
  }

  function selectBookmarkById(id) {
    for (var i = 0; i < root.filteredBookmarks.length; i++) {
      if (root.filteredBookmarks[i].id === id) {
        root.selectedIndex = i
        return
      }
    }

    root.selectedIndex = 0
  }

  function mutationAvailable(requireIdle) {
    if (!store.canMutate) {
      root.showStatus(
        store.error || (store.loaded
          ? "Bookmark storage is read-only"
          : "Bookmarks are still loading…")
      )
      return false
    }
    if (requireIdle && store.saving) {
      root.showStatus("Finishing the current save…")
      return false
    }
    if (requireIdle && root.quickAdding) {
      root.showStatus("Finishing the clipboard bookmark…")
      return false
    }
    return true
  }

  function beginAdd() {
    if (!root.mutationAvailable(true))
      return
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    editor.openForCreate()
  }

  function beginEdit() {
    if (!root.mutationAvailable(true))
      return
    var bookmark = root.selectedBookmark()

    if (bookmark) {
      editor.openForEdit(bookmark)
    }
  }

  function saveEditor(
    bookmarkId,
    title,
    url,
    tags,
    keyword,
    favicon
  ) {
    if (!root.mutationAvailable(false)) {
      editor.validationError = store.error || "Bookmark storage is not writable"
      return
    }
    var selectedId = bookmarkId
    var saved = false

    if (bookmarkId) {
      saved = store.updateBookmark(bookmarkId, title, url, tags, keyword)
    } else {
      selectedId = store.addBookmark(title, url, tags, keyword, favicon)
      saved = Boolean(selectedId)
    }

    if (!saved) {
      editor.validationError = store.error || "Could not save that bookmark"
      return
    }

    editor.close()
    root.viewMode = 0
    root.query = ""
    root.selectBookmarkById(selectedId)
    root.refocusList()
  }

  function requestDelete() {
    if (!root.mutationAvailable(true))
      return
    var bookmark = root.selectedBookmark()

    if (!bookmark)
      return

    root.deleteTarget = bookmark
    root.deleteConfirmOpen = true
    deleteConfirm.selectedIndex = 1
  }

  function cancelDelete() {
    root.deleteConfirmOpen = false
    root.deleteTarget = null
    root.refocusList()
  }

  function confirmDelete() {
    var bookmark = root.deleteTarget

    root.deleteConfirmOpen = false
    root.deleteTarget = null

    if (bookmark && !store.removeBookmark(bookmark.id))
      root.showStatus(store.error || "Could not delete that bookmark")

    root.refocusList()
  }

  function moveSelection(amount) {
    var count = root.activeResults.length

    if (!count)
      return

    root.selectedIndex =
      ((root.selectedIndex + amount) % count + count) % count

    bookmarkList.positionViewAtIndex(
      root.selectedIndex,
      ListView.Contain
    )
  }

  function activateSelected(openInNewWindow) {
    var bookmark = root.selectedBookmark()

    if (!bookmark)
      return

    root.activateBookmark(bookmark, openInNewWindow, null)
  }

  function activateBookmark(bookmark, openInNewWindow, browser) {
    if (!bookmark)
      return

    var url = root.resolvedUrl(bookmark)
    var command

    if (browser && browser.desktopPath) {
      command = [
        "uwsm-app",
        "--",
        "gio",
        "launch",
        String(browser.desktopPath),
        url
      ]
    } else {
      command = ["hyprshell", "launch/browser"]
      if (openInNewWindow)
        command.push("--new-window")
      command.push(url)
    }

    Quickshell.execDetached(command)
    store.recordOpen(bookmark.id)

    root.dismiss()
  }

  function openBrowserPicker() {
    var bookmark = root.selectedBookmark()
    if (!bookmark)
      return
    root.browserTarget = bookmark
    browserPicker.openFor(root.displayTitle(bookmark))
  }

  function activateCurrent(openInNewWindow, append) {
    if (root.viewMode === 0)
      root.activateSelected(openInNewWindow)
    else
      root.applyPickerSelection(append)
  }

  function showStatus(message) {
    root.statusMessage = message
    statusTimer.restart()
  }

  function copySelectedUrl() {
    var bookmark = root.selectedBookmark()
    if (!bookmark || copyProcess.running)
      return
    root.copyTargetTitle = root.displayTitle(bookmark)
    copyProcess.command = [
      "python3", root.helperPath, "copy", root.resolvedUrl(bookmark)
    ]
    copyProcess.running = true
  }

  function refreshNetworkSetting() {
    if (!store.storageReady || networkStatusProcess.running)
      return
    root.networkSettingStateReady = false
    networkStatusProcess.command = [
      "python3", root.helperPath,
      "network-enrichment", "status", root.settingsPath
    ]
    networkStatusProcess.running = true
  }

  function quickAddFromClipboard() {
    if (root.quickAdding || !root.mutationAvailable(true))
      return
    root.quickAdding = true
    root.quickAddCanceled = false
    root.showStatus(
      root.networkEnrichmentEnabled
        ? "Reading clipboard and fetching optional web details…"
        : "Reading clipboard…"
    )
    var clipboardCommand = [
      "python3",
      root.helperPath,
      root.networkEnrichmentEnabled ? "clipboard-enrich" : "clipboard",
      store.dataPath
    ]
    if (root.networkEnrichmentEnabled)
      clipboardCommand.push(root.settingsPath)
    quickAddProcess.command = clipboardCommand
    quickAddProcess.running = false
    quickAddProcess.running = true
  }

  function openNetworkSettings() {
    if (!root.networkSettingStateReady) {
      root.showStatus("Web-details preference is still loading…")
      return
    }
    networkDialog.errorMessage = ""
    networkDialog.selectedIndex = 0
    root.networkDialogOpen = true
  }

  function closeNetworkSettings() {
    root.networkDialogOpen = false
    if (editor.opened)
      editor.refocus()
    else
      root.refocusList()
  }

  function requestNetworkSetting(enabled) {
    if (networkSettingProcess.running)
      return
    root.networkSettingOperation = enabled ? "enable" : "disable"
    networkDialog.errorMessage = ""
    networkSettingProcess.command = [
      "python3", root.helperPath,
      "network-enrichment", root.networkSettingOperation,
      root.settingsPath
    ]
    networkSettingProcess.running = true
  }

  function openImportPicker() {
    if (!root.mutationAvailable(true))
      return
    root.fileDialogOpen = true
    importPickerProcess.command = [
      "zenity",
      "--file-selection",
      "--title=Import bookmarks",
      "--filename=" + Quickshell.env("HOME") + "/",
      "--file-filter=Bookmark files | *.html *.htm *.json",
      "--file-filter=All files | *"
    ]
    importPickerProcess.running = false
    importPickerProcess.running = true
  }

  function finishImport(items) {
    var outcome = store.importBookmarks(items)
    if (outcome.blocked) {
      root.showStatus(store.error || "Bookmark storage is not writable")
      root.refocusList()
      return
    }
    root.viewMode = 0
    root.query = ""
    root.selectedIndex = 0
    if (outcome.added || outcome.updated) {
      root.showStatus(
        "Imported " + outcome.added + " new · updated " + outcome.updated
        + " · backup created"
      )
    } else {
      root.showStatus("Nothing changed · every URL was already saved")
    }
    root.refocusList()
  }

  Timer {
    id: statusTimer
    interval: 5000
    repeat: false
    onTriggered: root.statusMessage = ""
  }

  Process {
    id: quickAddProcess
    running: false
    command: ["true"]

    onStarted: {
      root.quickAddResult = null
      root.quickAddResponseError = ""
    }

    stdout: SplitParser {
      onRead: function(data) {
        try {
          var output = String(data || "")
          if (output.length > root.maxQuickAddOutputCharacters)
            throw new Error("Clipboard helper returned too much data")
          root.quickAddResult = JSON.parse(output)
        } catch (exception) {
          root.quickAddResponseError = String(
            exception.message || "Could not add clipboard bookmark"
          )
        }
      }
    }

    onExited: function(exitCode) {
      root.quickAdding = false
      if (root.quickAddCanceled) {
        root.quickAddCanceled = false
        root.quickAddResult = null
        root.quickAddResponseError = ""
        return
      }
      var result = root.quickAddResult
      var responseError = root.quickAddResponseError
      root.quickAddResult = null
      root.quickAddResponseError = ""
      if (result) {
        if (exitCode !== 0 || !result.ok) {
          root.showStatus(String(result.error || "Could not add clipboard bookmark"))
        } else if (result.duplicate) {
          root.viewMode = 0
          root.query = ""
          root.selectBookmarkById(result.id)
          root.showStatus("That URL is already bookmarked")
        } else {
          editor.openForClipboard(result.item)
        }
      } else {
        root.showStatus(responseError || "Could not add clipboard bookmark")
      }
      root.refocusList()
    }

    onRunningChanged: {
      if (!running && root.quickAdding) {
        var canceled = root.quickAddCanceled
        root.quickAdding = false
        root.quickAddCanceled = false
        root.quickAddResult = null
        root.quickAddResponseError = ""
        if (!canceled && root.opened) {
          root.showStatus("Could not start the clipboard helper")
          root.refocusList()
        }
      }
    }
  }

  Process {
    id: copyProcess
    running: false
    command: ["true"]

    onStarted: root.copyResponse = null

    stdout: SplitParser {
      onRead: function(data) {
        try {
          root.copyResponse = root.parseSmallHelperResponse(data)
        } catch (exception) {
          root.copyResponse = {ok: false, error: "Could not copy URL"}
        }
      }
    }

    onExited: function(exitCode) {
      var message = "Copied " + root.copyTargetTitle + " URL"
      var result = root.copyResponse
      root.copyResponse = null
      if (!result || exitCode !== 0 || !result.ok)
        message = String(result && result.error || "Could not copy URL")
      root.copyTargetTitle = ""
      if (root.opened) {
        root.showStatus(message)
        root.refocusList()
      }
    }

    onRunningChanged: {
      if (!running && root.copyTargetTitle) {
        root.copyResponse = null
        root.copyTargetTitle = ""
        if (root.opened) {
          root.showStatus("Could not start the clipboard helper")
          root.refocusList()
        }
      }
    }
  }

  Process {
    id: networkStatusProcess
    running: false
    command: ["true"]

    onStarted: root.networkStatusResponse = null

    stdout: SplitParser {
      onRead: function(data) {
        try {
          root.networkStatusResponse = root.parseSmallHelperResponse(data)
        } catch (exception) {
          root.networkStatusResponse = {
            ok: false,
            error: "Could not inspect web-details preference"
          }
        }
      }
    }

    onExited: function(exitCode) {
      var result = root.networkStatusResponse
      root.networkStatusResponse = null
      if (result && exitCode === 0 && result.ok) {
        root.networkEnrichmentEnabled = result.enabled === true
        root.networkSettingStateReady = true
      } else {
        root.networkEnrichmentEnabled = false
        root.networkSettingStateReady = false
        if (root.opened)
          root.showStatus(String(result && result.error || "Could not inspect web-details preference"))
      }
    }
  }
  Process {
    id: networkSettingProcess
    running: false
    command: ["true"]

    onStarted: root.networkSettingResponse = null

    stdout: SplitParser {
      onRead: function(data) {
        try {
          root.networkSettingResponse = root.parseSmallHelperResponse(data)
        } catch (exception) {
          root.networkSettingResponse = {
            ok: false,
            error: "Could not save web-details preference"
          }
        }
      }
    }

    onExited: function(exitCode) {
      try {
        var result = root.networkSettingResponse
        root.networkSettingResponse = null
        if (!result)
          throw new Error("Could not save web-details preference")
        if (exitCode !== 0 || !result.ok)
          throw new Error(String(result.error || "Could not save web-details preference"))
        root.networkEnrichmentEnabled = result.enabled === true
        root.networkSettingStateReady = true
        root.networkDialogOpen = false
        if (root.opened) {
          root.showStatus(
            root.networkEnrichmentEnabled
              ? "Web details enabled for future pasted URLs"
              : "Web details disabled · pasting will not access the network"
          )
          if (editor.opened)
            editor.refocus()
          else
            root.refocusList()
        }
      } catch (exception) {
        networkDialog.errorMessage = String(
          exception.message || "Could not save web-details preference"
        )
      }
      root.networkSettingOperation = ""
    }

    onRunningChanged: {
      if (!running && root.networkSettingOperation) {
        root.networkSettingResponse = null
        root.networkSettingOperation = ""
        networkDialog.errorMessage = "Could not start the settings helper"
      }
    }
  }

  Process {
    id: importPickerProcess
    running: false
    command: ["true"]

    onStarted: root.importPickerPath = ""

    stdout: SplitParser {
      onRead: function(data) {
        var path = String(data || "").trim()
        root.importPickerPath = path.length <= 4096 ? path : ""
      }
    }

    onExited: function(exitCode) {
      root.fileDialogOpen = false
      var path = root.importPickerPath
      root.importPickerPath = ""
      if (exitCode === 0 && path)
        importer.begin(path)
      else {
        root.refocusList()
      }
    }

    onRunningChanged: {
      if (!running && root.fileDialogOpen) {
        root.importPickerPath = ""
        root.fileDialogOpen = false
        if (root.opened) {
          root.showStatus("Could not open import picker · install Zenity")
          root.refocusList()
        }
      }
    }
  }

  BookmarkStore {
    id: store
    externallyBusy: firefoxSyncProcess.running
    onStorageReadyChanged: {
      if (storageReady) {
        root.refreshNetworkSetting()
        if (root.opened)
          root.syncFirefox()
      }
    }
    onSavingChanged: {
      if (!saving && root.firefoxSyncPending && root.opened)
        Qt.callLater(root.syncFirefox)
    }
    onLoadedChanged: {
      if (loaded && root.firefoxSyncPending && root.opened)
        Qt.callLater(root.syncFirefox)
    }
  }

  Process {
    id: firefoxSyncProcess
    running: false
    command: ["true"]

    stdout: SplitParser {
      onRead: function(data) {
        try {
          root.firefoxSyncResponse = root.parseSmallHelperResponse(data)
        } catch (exception) {
          root.firefoxSyncResponse = {
            ok: false,
            error: "Invalid Firefox sync response"
          }
        }
      }
    }

    onExited: function(exitCode) {
      var response = root.firefoxSyncResponse
      root.firefoxSyncResponse = null
      if (exitCode !== 0 || !response || !response.ok) {
        root.showStatus(
          "Firefox sync failed"
          + (response && response.error ? " · " + response.error : "")
        )
        return
      }
      var stats = response.stats || ({})
      var changes = Number(stats.changed || 0)
      root.showStatus(
        changes
          ? "Firefox synced · "
            + Number(stats.new || 0) + " added · "
            + Number(stats.updated || 0) + " updated · "
            + Number(stats.removed || 0) + " removed"
          : "Firefox bookmarks are up to date"
      )
      store.reload()
    }
  }

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    shell: root.shell
    popupName: "bookmarks"
    popupEnabled: root.popupEnabled
    contentWidth: Style.px(560)
    contentHeight: Style.px(620)

    Item {
      id: card
      anchors.fill: parent
      readonly property real contentTopInset: 0
      readonly property real contentRightInset: 0
      readonly property real contentBottomInset: 0
      readonly property real contentLeftInset: 0

      Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem

        Keys.onPressed: function(event) {
          if (root.networkDialogOpen) {
            if (networkDialog.handleKey(event))
              event.accepted = true
            return
          }

          if (root.deleteConfirmOpen) {
            if (deleteConfirm.handleKey(event))
              event.accepted = true

            return
          }

          if (browserPicker.opened) {
            if (browserPicker.handleKey(event))
              event.accepted = true
            return
          }

          if (editor.opened || importer.opened)
            return

          if (
            event.key === Qt.Key_Tab
            && event.modifiers === Qt.ControlModifier
            && root.viewMode === 0
          ) {
            root.openBrowserPicker()
            event.accepted = true
          } else if (
            (
              event.key === Qt.Key_Tab
              && (
                event.modifiers === Qt.NoModifier
                || event.modifiers === Qt.ShiftModifier
              )
            )
            || event.key === Qt.Key_Backtab
          ) {
            root.cycleView(
              event.key === Qt.Key_Backtab
                || event.modifiers === Qt.ShiftModifier
                ? -1
                : 1
            )
            event.accepted = true
          } else if (
            event.key === Qt.Key_C
            && event.modifiers === Qt.ControlModifier
            && root.viewMode === 0
          ) {
            root.copySelectedUrl()
            event.accepted = true
          } else if (
            event.key === Qt.Key_V
            && event.modifiers === Qt.ControlModifier
          ) {
            root.quickAddFromClipboard()
            event.accepted = true
          } else if (
            event.key === Qt.Key_I
            && event.modifiers === Qt.ControlModifier
          ) {
            root.openImportPicker()
            event.accepted = true
          } else if (
            event.key === Qt.Key_Comma
            && event.modifiers === Qt.ControlModifier
          ) {
            root.openNetworkSettings()
            event.accepted = true
          } else if (
            event.key === Qt.Key_N
            && event.modifiers === Qt.ControlModifier
          ) {
            root.beginAdd()
            event.accepted = true
          } else if (
            event.key === Qt.Key_E
            && event.modifiers === Qt.ControlModifier
            && root.viewMode === 0
          ) {
            root.beginEdit()
            event.accepted = true
          } else if (
            event.key === Qt.Key_T
            && event.modifiers === Qt.ControlModifier
            && root.viewMode === 0
          ) {
            root.activateSelected(true)
            event.accepted = true
          } else if (
            event.key === Qt.Key_Delete
            && root.viewMode === 0
          ) {
            root.requestDelete()
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            if (root.currentQuery()) {
              root.setCurrentQuery("")
              root.selectedIndex = 0
            } else if (root.viewMode !== 0) {
              root.viewMode = 0
              root.selectedIndex = 0
            } else {
              root.dismiss()
            }

            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.moveSelection(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.moveSelection(1)
            event.accepted = true
          } else if (
            event.key === Qt.Key_Return
            || event.key === Qt.Key_Enter
          ) {
            root.activateCurrent(
              false,
              root.viewMode !== 0
                && (event.modifiers & Qt.ControlModifier) !== 0
            )
            event.accepted = true
          } else if (Commons.Util.editsFilter(event, root.currentQuery())) {
            root.setCurrentQuery(
              Commons.Util.editedFilter(event, root.currentQuery())
            )
            root.selectedIndex = 0
            event.accepted = true
          } else if (
            event.text
            && event.text.length === 1
            && event.text.charCodeAt(0) >= 32
            && event.text.charCodeAt(0) !== 127
            && (
              event.modifiers === Qt.NoModifier
              || event.modifiers === Qt.ShiftModifier
            )
          ) {
            root.setCurrentQuery(root.currentQuery() + event.text)
            root.selectedIndex = 0
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent

        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        spacing: Commons.Style.spacing.md

        Item {
          width: parent.width
          height: Commons.Style.space(42)

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: keyCatcher.forceActiveFocus()
          }

          Text {
            anchors.left: parent.left
            anchors.right: countText.left
            anchors.rightMargin: Commons.Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter

            text: root.currentQuery() || root.modePlaceholder()
            textFormat: Text.PlainText
            color: Commons.Color.menu.text
            opacity: root.currentQuery() ? 1 : 0.58

            font.family: Commons.Style.font.menuFamily
            font.pixelSize: Commons.Style.font.heading

            elide: Text.ElideRight
          }

          Text {
            id: countText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            text:
              root.viewName
              + " · "
              + root.activeResults.length
              + " / "
              + root.activeTotal

            color: Commons.Color.menu.text
            opacity: 0.48

            font.family: Commons.Style.font.menuFamily
            font.pixelSize: Commons.Style.font.caption
          }
        }

        Item {
          width: parent.width

          height:
            parent.height
            - Commons.Style.space(42)
            - Commons.Style.space(48)
            - parent.spacing * 2

          ListView {
            id: bookmarkList

            anchors.fill: parent
            model: root.activeResults

            clip: true
            spacing: Commons.Style.spacing.xs
            boundsBehavior: Flickable.StopAtBounds

            delegate: Ui.BorderSurface {
              id: row

              required property int index
              required property var modelData

              readonly property bool selected:
                row.index === root.selectedIndex

              readonly property bool bookmarkMode:
                root.viewMode === 0

              readonly property bool tagMode:
                root.viewMode === 1

              readonly property bool keywordMode:
                root.viewMode === 2

              readonly property var bookmark:
                row.bookmarkMode
                  ? row.modelData
                  : row.keywordMode
                    ? row.modelData.bookmark
                    : null

              readonly property bool keywordResult:
                row.bookmarkMode
                  && root.keywordAction
                  && root.keywordAction.bookmark.id === row.bookmark.id

              width: ListView.view.width
              height: Commons.Style.space(62)

              radius: Commons.Style.cornerRadius

              color:
                row.selected
                  ? Commons.Color.menu.selectedBackground
                  : "transparent"

              borderSpec:
                row.selected
                  ? Commons.Border.surfaceSpec(
                      "menu",
                      "selected-border",
                      Commons.Color.menu.selectedBorder,
                      0
                    )
                  : Commons.Border.none()

              Item {
                id: bookmarkIcon

                anchors.left: parent.left
                anchors.leftMargin: Commons.Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter

                width: Commons.Style.space(30)
                height: Commons.Style.space(30)

                Image {
                  id: faviconImage
                  anchors.centerIn: parent
                  width: Commons.Style.space(24)
                  height: Commons.Style.space(24)
                  visible: row.bookmarkMode
                  source: row.bookmarkMode
                    ? String(row.bookmark.favicon || "")
                    : ""
                  sourceSize.width: 64
                  sourceSize.height: 64
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  cache: false
                }

                Text {
                  anchors.fill: parent
                  visible:
                    !row.bookmarkMode
                    || faviconImage.status !== Image.Ready
                  text:
                    row.tagMode
                      ? "#"
                      : row.keywordMode
                        ? "K"
                        : ""

                  color:
                    row.selected
                      ? Commons.Color.menu.selectedText
                      : Commons.Color.menu.text

                  font.family: Commons.Style.font.menuFamily
                  font.pixelSize:
                    row.bookmarkMode
                      ? Commons.Style.font.iconLarge
                      : Commons.Style.font.heading

                  horizontalAlignment: Text.AlignHCenter
                  verticalAlignment: Text.AlignVCenter
                }
              }

              Column {
                anchors.left: bookmarkIcon.right
                anchors.leftMargin: Commons.Style.spacing.sm
                anchors.right: parent.right
                anchors.rightMargin: Commons.Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter

                spacing: Commons.Style.spacing.xs

                Text {
                  width: parent.width
                  text:
                    row.bookmarkMode
                      ? root.displayTitle(row.bookmark)
                      : row.tagMode
                        ? "#" + row.modelData.tag
                        : row.modelData.keyword
                  textFormat: Text.PlainText

                  color:
                    row.selected
                      ? Commons.Color.menu.selectedText
                      : Commons.Color.menu.text

                  font.family: Commons.Style.font.menuFamily
                  font.pixelSize: Commons.Style.font.heading
                  font.weight: Font.Medium
                  opacity:
                    row.bookmarkMode && !row.bookmark.title
                      ? 0.68
                      : 1

                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width

                  text:
                    row.tagMode
                      ? row.modelData.count
                        + (row.modelData.count === 1 ? " bookmark" : " bookmarks")
                      : row.keywordMode
                        ? root.displayTitle(row.bookmark)
                          + (
                            row.modelData.parameterized
                              ? "  ·  accepts search terms"
                              : ""
                          )
                        : row.keywordResult
                          ? "Search for “" + root.keywordAction.terms + "”"
                          : row.bookmark.url
                            + (
                              row.bookmark.tags.length
                                ? "  ·  " + row.bookmark.tags.join(" · ")
                                : ""
                            )
                            + (
                              row.bookmark.keyword
                                ? "  ·  " + row.bookmark.keyword
                                : ""
                            )
                  textFormat: Text.PlainText

                  color: Commons.Color.menu.text
                  opacity: 0.52

                  font.family: Commons.Style.font.menuFamily
                  font.pixelSize: Commons.Style.font.bodySmall

                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onEntered:
                  root.selectedIndex = row.index

                onClicked: {
                  root.selectedIndex = row.index
                  root.activateCurrent(false, false)
                }
              }
            }
          }

          Column {
            anchors.centerIn: parent
            spacing: Commons.Style.spacing.sm
            visible: root.activeResults.length === 0

            Text {
              width: Commons.Style.space(360)

              text:
                store.error
                  ? ""
                  : root.viewMode === 1
                    ? "#"
                    : root.viewMode === 2
                      ? "K"
                      : ""
              color:
                store.error
                  ? Commons.Color.urgent
                  : Commons.Color.menu.selectedText

              font.family: Commons.Style.font.menuFamily
              font.pixelSize: Commons.Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
            }

            Text {
              width: Commons.Style.space(360)

              text:
                store.error
                  ? store.error
                  : root.currentQuery()
                    ? "No matching " + root.viewName.toLowerCase()
                    : root.viewMode === 1
                      ? "No tags yet"
                      : root.viewMode === 2
                        ? "No keywords yet"
                        : "No bookmarks yet"
              textFormat: Text.PlainText

              color: Commons.Color.menu.text
              opacity: 0.7

              font.family: Commons.Style.font.menuFamily
              font.pixelSize: Commons.Style.font.title

              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }

        Text {
          width: parent.width
          height: Commons.Style.space(48)

          text:
            store.error
              ? store.error
              : store.saving
                ? "Saving…"
                : root.statusMessage
                  ? root.statusMessage
                  : root.viewMode === 1
                    ? "Enter Set  Ctrl+Enter Append  ↑↓ Select\nTab Keywords  Shift+Tab Bookmarks"
                    : root.viewMode === 2
                      ? "Enter Set  Ctrl+Enter Append  ↑↓ Select\nTab Bookmarks  Shift+Tab Tags"
                      : "Enter Open  Ctrl+C Copy  Ctrl+T Window  Ctrl+Tab Browser\nTab Tags  Ctrl+V Paste  Ctrl+I Import  Ctrl+N Add  Ctrl+E Edit  Ctrl+, Web"
          textFormat: Text.PlainText

          color: store.error ? Commons.Color.urgent : Commons.Color.menu.text
          opacity: store.error ? 1 : 0.48

          font.family: Commons.Style.font.menuFamily
          font.pixelSize: Commons.Style.font.caption
          lineHeight: 1.35

          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }

      BookmarkEditor {
        id: editor

        z: 10

        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        urlValidator: function(value) {
          return store.normalizeUrl(value)
        }

        webDetailsEnabled: root.networkEnrichmentEnabled

        onSubmitted: function(
          bookmarkId,
          title,
          url,
          tags,
          keyword,
          favicon
        ) {
          root.saveEditor(bookmarkId, title, url, tags, keyword, favicon)
        }

        onCanceled: root.refocusList()
        onWebDetailsSettingsRequested: root.openNetworkSettings()
      }

      BookmarkImport {
        id: importer

        z: 15
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        helperPath: root.helperPath
        dataPath: store.dataPath

        onConfirmed: function(items) {
          root.finishImport(items)
        }

        onCanceled: root.refocusList()
      }

      BrowserPicker {
        id: browserPicker

        z: 18
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        helperPath: root.helperPath

        onSelected: function(browser) {
          var bookmark = root.browserTarget
          root.browserTarget = null
          root.activateBookmark(bookmark, false, browser)
        }

        onCanceled: {
          root.browserTarget = null
          root.refocusList()
        }
      }

      Ui.ConfirmDialog {
        id: deleteConfirm

        z: 20
        anchors.fill: parent

        opened: root.deleteConfirmOpen
        // Ui.ConfirmDialog renders its message with Text.AutoText. Keep this
        // strictly static so imported or fetched fields never reach that sink.
        message: "Delete the selected bookmark?"

        cancelText: "Cancel"
        confirmText: "Delete"

        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Util.alpha(Commons.Color.menu.background, 0.76)
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: Commons.Style.font.menuFamily

        onCanceled: root.cancelDelete()
        onConfirmed: root.confirmDelete()
      }

      NetworkEnrichmentDialog {
        id: networkDialog

        z: 30
        anchors.fill: parent
        opened: root.networkDialogOpen
        webEnabled: root.networkEnrichmentEnabled
        busy: networkSettingProcess.running
        background: Commons.Color.menu.background
        foreground: Commons.Color.menu.text
        scrim: Commons.Util.alpha(Commons.Color.menu.background, 0.76)
        selectedBackground: Commons.Color.menu.selectedBackground
        selectedText: Commons.Color.menu.selectedText
        fontFamily: Commons.Style.font.menuFamily

        onCanceled: root.closeNetworkSettings()
        onSettingRequested: function(enabled) {
          root.requestNetworkSetting(enabled)
        }
      }
    }
  }
}
