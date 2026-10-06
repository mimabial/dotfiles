pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import ".." as Shell

Column {
  id: root
  required property var controller
  property alias urlInput: urlInput
  property bool queueFocusPending: false
  property bool queueRefreshFocus: false
  property int focusedQueueIndex: -1

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  component Placeholder: Text {
    width: parent.width
    height: Style.space(40)
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    color: root.controller.dim
    font.family: root.controller.fontFamily
    font.pixelSize: Style.font.caption
  }

  component ListHeader: Item {
    id: header
    property alias text: label.text
    property bool backable: false
    default property alias actions: actionRow.data
    signal back()
    width: parent.width
    implicitHeight: backButton.implicitHeight

    PanelActionButton {
      id: backButton
      visible: header.backable
      anchors.verticalCenter: parent.verticalCenter
      iconText: "\uf060"
      tooltipText: "Back"
      onClicked: header.back()
    }
    Text {
      id: label
      anchors.left: header.backable ? backButton.right : parent.left
      anchors.right: actionRow.left
      anchors.leftMargin: Style.spacing.sm
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      elide: Text.ElideMiddle
      color: Color.accent
      font.family: root.controller.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Row {
      id: actionRow
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  function selectTab(tab) {
    if (tab === "queue") return root.showQueue()
    root.controller.selectedTab = tab
    if (tab === "recents") root.controller.loadHistory()
    else if (tab === "playlists") root.controller.loadPlaylists()
    else if (tab === "files") root.controller.loadFiles(root.controller.filesPath)
  }

  function showQueue() {
    root.controller.selectedTab = "queue"
    root.queueFocusPending = true
    root.queueRefreshFocus = true
    // focusCurrentQueueItem is what clears queueFocusPending, and the viewport is
    // hidden until it does, so it has to run whether or not there is a row to scroll to
    Qt.callLater(root.focusCurrentQueueItem)
    root.controller.loadQueue()
  }

  function currentQueueIndex() {
    const queue = root.controller.queueList || []
    for (let i = 0; i < queue.length; ++i)
      if (queue[i] && queue[i].current === true) return i
    return -1
  }

  function queueUpdated() {
    if (!root.queueRefreshFocus) return
    root.queueRefreshFocus = false
    const index = root.currentQueueIndex()
    if (root.queueFocusPending || index !== root.focusedQueueIndex) {
      root.queueFocusPending = true
      Qt.callLater(root.focusCurrentQueueItem)
    }
  }

  function focusCurrentQueueItem() {
    if (!root.queueFocusPending) return
    if (root.controller.selectedTab !== "queue") {
      root.queueFocusPending = false
      return
    }
    const index = root.currentQueueIndex()
    const queueRow = index >= 0 ? queueRepeater.itemAt(index) : null
    if (queueRow) {
      const rowY = queueRow.mapToItem(listCol, 0, 0).y
      const maxY = Math.max(0, trackViewport.contentHeight - trackViewport.height)
      trackViewport.contentY = Math.max(0, Math.min(rowY + queueRow.height / 2 - trackViewport.height / 2, maxY))
      root.focusedQueueIndex = index
    }
    root.queueFocusPending = false
  }

  BorderSurface {
    id: searchBox
    width: parent.width
    implicitHeight: Style.space(26)
    radius: Style.cornerRadius
    color: Color.popups.background
    borderSpec: Border.controlSpec(urlInput.activeFocus ? "focused" : "normal", root.controller.foreground, Color.accent)
    clip: true

    Item {
      anchors.fill: parent
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)

      PanelActionButton {
        id: searchAction
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        iconText: root.controller.isSearching ? "\uf110" : "\uf002"
        tooltipText: "Search"
        foreground: root.controller.foreground; hoverColor: Color.accent; fontFamily: root.controller.fontFamily
        enabled: root.controller.urlInputText.trim().length > 0 && !root.controller.isSearching
        onClicked: root.controller.searchTracks(root.controller.urlInputText)
      }

      TextInput {
        id: urlInput
        anchors.left: searchAction.right
        anchors.leftMargin: Style.space(2)
        anchors.right: clearBtn.visible ? clearBtn.left : parent.right
        anchors.rightMargin: clearBtn.visible ? Style.space(4) : 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.controller.urlInputText
        onTextChanged: root.controller.urlInputText = text
        color: root.controller.foreground
        font.family: root.controller.fontFamily
        font.pixelSize: Style.font.caption
        selectByMouse: true
        clip: true
        onAccepted: root.controller.searchTracks(text)

        Text {
          visible: !urlInput.text && !urlInput.activeFocus
          text: "Search songs, artists, or paste URL..."
          color: root.controller.dim
          font.family: root.controller.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          elide: Text.ElideRight
        }
      }

      Text {
        id: clearBtn
        visible: urlInput.text.length > 0
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "\uf00d"
        color: clearMouse.containsMouse ? Color.accent : root.controller.dim
        font.family: root.controller.fontFamily
        font.pixelSize: Style.font.caption

        MouseArea {
          id: clearMouse
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { urlInput.text = ""; root.controller.clearSearch() }
        }
      }
    }
  }

  Item {
    width: parent.width
    implicitHeight: tabRow.implicitHeight

    Row {
      id: tabRow
      spacing: Style.spacing.sm

      Repeater {
        model: ["search", "recents", "queue", "playlists", "files", "sources"]
        delegate: Shell.PopupTab {
          required property string modelData
          visible: modelData !== "search" || root.controller.searchQuery !== ""
          shell: root.controller.shell
          text: modelData
          selected: root.controller.selectedTab === modelData
          onClicked: root.selectTab(modelData)
        }
      }
    }

    PanelActionButton {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      iconText: "\uf011"
      tooltipText: root.controller.isRunning ? "Stop background daemon" : "Daemon idle"
      foreground: root.controller.isRunning ? root.controller.foreground : root.controller.dim
      hoverColor: root.controller.urgent
      onClicked: { if (root.controller.isRunning) root.controller.stopDaemon(); else root.controller.play() }
    }
  }

  Flickable {
    id: trackViewport
    width: parent.width
    implicitHeight: Style.space(168)
    // hidden only while there is a row to scroll to, so a stuck flag cannot blank the panel
    opacity: root.controller.selectedTab === "queue" && root.queueFocusPending && root.currentQueueIndex() >= 0 ? 0 : 1
    contentWidth: width
    contentHeight: listCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: listCol
      width: parent.width
      spacing: Style.space(3)

      Placeholder {
        visible: root.controller.selectedTab === "sources" && root.controller.media.sourcePlayers.length === 0
        text: "No media sources available"
      }
      Repeater {
        model: root.controller.selectedTab === "sources" ? root.controller.media.sourcePlayers : []
        delegate: MediaRow {
          id: sourceRow
          required property var modelData
          controller: root.controller
          thumb: modelData.trackArtUrl || ""
          title: modelData.identity || root.controller.media.playerKey(modelData)
          subtitle: [modelData.trackTitle, root.controller.media.displayArtist(modelData)].filter(Boolean).join(" · ")
          isCurrent: root.controller.media.player === modelData
          onActivated: root.controller.media.select(modelData)

          RowGlyph {
            controller: root.controller
            enabled: sourceRow.modelData.isPlaying ? sourceRow.modelData.canPause : sourceRow.modelData.canPlay || sourceRow.modelData.canTogglePlaying
            text: sourceRow.modelData.isPlaying ? "\uead1" : "\ueb2c"
            lit: sourceRow.isCurrent
            onActivated: root.controller.media.playPause(sourceRow.modelData)
          }
          RowGlyph {
            controller: root.controller
            enabled: root.controller.media.canNext(sourceRow.modelData)
            text: "󰒭"
            onActivated: root.controller.media.next(sourceRow.modelData)
          }
        }
      }

      Placeholder {
        visible: root.controller.selectedTab === "search" && (root.controller.isSearching || root.controller.searchResults.length === 0)
        text: (root.controller.isSearching ? "Searching for \"" : "No tracks found for \"") + root.controller.searchQuery + "\""
      }
      Repeater {
        model: root.controller.selectedTab === "search" && !root.controller.isSearching ? root.controller.searchResults : []
        delegate: TrackRow { controller: root.controller; meta: modelData.duration || "" }
      }

      Placeholder {
        visible: root.controller.selectedTab === "recents" && root.controller.historyList.length === 0
        text: "Nothing played yet"
      }
      Repeater {
        model: root.controller.selectedTab === "recents" ? root.controller.historyGroups : []
        delegate: Column {
          id: hGroup
          required property var modelData
          width: parent.width
          spacing: listCol.spacing

          Text {
            leftPadding: Style.spacing.sm
            text: hGroup.modelData.label
            color: Color.accent
            font.family: root.controller.fontFamily
            font.pixelSize: Style.font.caption * 0.8
            font.bold: true
          }
          Repeater {
            model: hGroup.modelData.items
            delegate: TrackRow {
              controller: root.controller
              url: modelData.path || ""
              meta: modelData.duration_secs ? root.controller.media.time(modelData.duration_secs) : ""
            }
          }
        }
      }

      ListHeader {
        visible: root.controller.selectedTab === "queue" && root.controller.queueList.length > 0
        text: (root.controller.queueSource === "mpd" ? "MPD Queue" : root.controller.queueSource === "youtube" ? "YouTube Playlist" : "Queue")
          + " (" + root.controller.queueList.length + " tracks)"
        PanelActionButton {
          visible: root.controller.queueSource === "cliamp"
          iconText: "\uf1f8"
          tooltipText: "Clear queue"
          hoverColor: root.controller.urgent
          onClicked: root.controller.clearQueue()
        }
      }
      Placeholder {
        visible: root.controller.selectedTab === "queue" && root.controller.queueList.length === 0
        text: root.controller.queueSource === "mpd" ? "MPD queue is empty"
          : root.controller.queueSource === "youtube" ? "No playlist entries found"
          : "Queue is empty\nClick '+' on any song to add to queue"
      }
      Repeater {
        id: queueRepeater
        model: root.controller.selectedTab === "queue" ? root.controller.queueList : []
        delegate: TrackRow { controller: root.controller; queued: true; number: index + 1 }
      }

      ListHeader {
        visible: root.controller.selectedTab === "playlists" && root.controller.activePlaylist !== null
        backable: true
        text: root.controller.activePlaylist ? root.controller.activePlaylist.name + " (" + (root.controller.activePlaylist.tracks || []).length + ")" : ""
        onBack: root.controller.closePlaylist()
        PanelActionButton {
          iconText: "\ueb2c"
          tooltipText: "Play all"
          onClicked: root.controller.playPlaylist(root.controller.activePlaylist)
        }
        PanelActionButton {
          visible: root.controller.activePlaylist && !root.controller.activePlaylist.system
          iconText: "\uf1f8"
          tooltipText: "Delete playlist"
          hoverColor: root.controller.urgent
          onClicked: root.controller.deletePlaylist(root.controller.activePlaylist.name)
        }
      }
      Placeholder {
        visible: root.controller.selectedTab === "playlists" && root.controller.activePlaylist !== null
          && (root.controller.activePlaylist.tracks || []).length === 0
        text: "No tracks found in this playlist"
      }
      Repeater {
        model: root.controller.selectedTab === "playlists" && root.controller.activePlaylist ? root.controller.activePlaylist.tracks || [] : []
        delegate: TrackRow {
          controller: root.controller
          number: index + 1
          meta: modelData.plays ? modelData.plays + "×" : modelData.duration || ""
        }
      }
      Placeholder {
        visible: root.controller.selectedTab === "playlists" && root.controller.activePlaylist === null
          && (root.controller.isImportingPl || root.controller.plImportError !== "")
        text: root.controller.isImportingPl ? "Importing playlist tracks..." : root.controller.plImportError
        color: root.controller.isImportingPl ? root.controller.dim : root.controller.urgent
      }
      Repeater {
        model: root.controller.selectedTab === "playlists" ? root.controller.playlistsList : []
        // hidden rather than unloaded: playing a system playlist opens it from inside its own row
        delegate: MediaRow {
          id: plRow
          required property var modelData
          visible: root.controller.activePlaylist === null
          controller: root.controller
          glyph: modelData.name === "Liked" ? "\uf004" : modelData.name === "Most Played" ? "\uf091" : modelData.system ? "\uf017" : "\uf0ca"
          title: modelData.name || "Playlist"
          subtitle: modelData.count + " tracks"
          onActivated: root.controller.openPlaylist(modelData)

          RowGlyph {
            controller: root.controller
            enabled: !plRow.modelData.system
            text: "\uf1f8"
            hot: root.controller.urgent
            onActivated: root.controller.deletePlaylist(plRow.modelData.name)
          }
          RowGlyph {
            controller: root.controller
            text: "\ueb2c"
            onActivated: {
              if (!plRow.modelData.system) return root.controller.playPlaylist(plRow.modelData)
              root.controller.openPlaylist(plRow.modelData)
              root.controller.playPlaylist(root.controller.activePlaylist)
            }
          }
        }
      }

      ListHeader {
        visible: root.controller.selectedTab === "files" && !root.controller.filesAtRoot
        backable: true
        text: root.controller.filesPath
        onBack: root.controller.loadFiles(root.controller.filesParent)
      }
      Placeholder {
        visible: root.controller.selectedTab === "files" && root.controller.filesList.length === 0
        text: root.controller.filesAtRoot ? "No audio in the music library" : "Nothing here"
      }
      Repeater {
        model: root.controller.selectedTab === "files" ? root.controller.filesList : []
        delegate: TrackRow { controller: root.controller }
      }
    }
  }
}
