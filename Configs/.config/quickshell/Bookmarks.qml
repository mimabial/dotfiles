pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "Commons" as Commons
import "Ui" as Ui
import "BookmarkModel.js" as BookmarkModel

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
      ? BookmarkModel.keywordAction(store.bookmarks, root.query)
      : null

  readonly property var filteredBookmarks:
    root.opened && root.viewMode === 0
      ? BookmarkModel.filteredBookmarks(store.bookmarks, root.query, root.keywordAction,
          store)
      : []

  readonly property var allTags:
    root.opened && root.viewMode === 1 ? BookmarkModel.tags(store.bookmarks) : []

  readonly property var filteredTags:
    root.opened && root.viewMode === 1 ? BookmarkModel.matchingTags(root.allTags, root.tagQuery) : []

  readonly property var allKeywords:
    root.opened && root.viewMode === 2 ? BookmarkModel.keywords(store.bookmarks) : []

  readonly property var filteredKeywords:
    root.opened && root.viewMode === 2
      ? BookmarkModel.matchingKeywords(root.allKeywords, root.keywordQuery)
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
    if (bookmarkBackend.firefoxSyncProcess.running)
      return
    root.firefoxSyncPending = false
    root.firefoxSyncResponse = null
    root.statusMessage = "Syncing Firefox…"
    bookmarkBackend.firefoxSyncProcess.command = [
      "python3", root.helperPath,
      "firefox-sync", store.dataPath
    ]
    bookmarkBackend.firefoxSyncProcess.running = true
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
    root.quickAddCanceled = bookmarkBackend.quickAddProcess.running
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
    bookmarkBackend.statusTimer.stop()
    if (bookmarkBackend.importPickerProcess.running)
      bookmarkBackend.importPickerProcess.running = false
    root.fileDialogOpen = false
    if (bookmarkBackend.quickAddProcess.running) {
      root.quickAddCanceled = true
      bookmarkBackend.quickAddProcess.running = false
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

    var url = BookmarkModel.resolvedUrl(bookmark, root.keywordAction)
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
    browserPicker.openFor(BookmarkModel.title(bookmark))
  }

  function activateCurrent(openInNewWindow, append) {
    if (root.viewMode === 0)
      root.activateSelected(openInNewWindow)
    else
      root.applyPickerSelection(append)
  }

  function showStatus(message) {
    root.statusMessage = message
    bookmarkBackend.statusTimer.restart()
  }

  function copySelectedUrl() {
    var bookmark = root.selectedBookmark()
    if (!bookmark || bookmarkBackend.copyProcess.running)
      return
    root.copyTargetTitle = BookmarkModel.title(bookmark)
    bookmarkBackend.copyProcess.command = [
      "python3", root.helperPath, "copy", BookmarkModel.resolvedUrl(bookmark, root.keywordAction)
    ]
    bookmarkBackend.copyProcess.running = true
  }

  function refreshNetworkSetting() {
    if (!store.storageReady || bookmarkBackend.networkStatusProcess.running)
      return
    root.networkSettingStateReady = false
    bookmarkBackend.networkStatusProcess.command = [
      "python3", root.helperPath,
      "network-enrichment", "status", root.settingsPath
    ]
    bookmarkBackend.networkStatusProcess.running = true
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
    bookmarkBackend.quickAddProcess.command = clipboardCommand
    bookmarkBackend.quickAddProcess.running = false
    bookmarkBackend.quickAddProcess.running = true
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
    if (bookmarkBackend.networkSettingProcess.running)
      return
    root.networkSettingOperation = enabled ? "enable" : "disable"
    networkDialog.errorMessage = ""
    bookmarkBackend.networkSettingProcess.command = [
      "python3", root.helperPath,
      "network-enrichment", root.networkSettingOperation,
      root.settingsPath
    ]
    bookmarkBackend.networkSettingProcess.running = true
  }

  function openImportPicker() {
    if (!root.mutationAvailable(true))
      return
    root.fileDialogOpen = true
    bookmarkBackend.importPickerProcess.command = [
      "zenity",
      "--file-selection",
      "--title=Import bookmarks",
      "--filename=" + Quickshell.env("HOME") + "/",
      "--file-filter=Bookmark files | *.html *.htm *.json",
      "--file-filter=All files | *"
    ]
    bookmarkBackend.importPickerProcess.running = false
    bookmarkBackend.importPickerProcess.running = true
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

  BookmarkBackend { id: bookmarkBackend; controller: root; store: store; editor: editor; importer: importer; networkDialog: networkDialog }

  BookmarkStore {
    id: store
    externallyBusy: bookmarkBackend.firefoxSyncProcess.running
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
                      ? BookmarkModel.title(row.bookmark)
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
                        ? BookmarkModel.title(row.bookmark)
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
        busy: bookmarkBackend.networkSettingProcess.running
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
