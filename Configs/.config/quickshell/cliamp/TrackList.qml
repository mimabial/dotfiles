import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Search input + tabs + scrollable track list
Column {
  id: root
  property var p  // Panel root
  property alias urlInput: urlInput
  property bool queueFocusPending: false
  property bool queueRefreshFocus: false
  property int focusedQueueIndex: -1

  width: parent ? parent.width : 0
  spacing: Style.space(6)

  function showQueue() {
    root.queueFocusPending = true
    root.queueRefreshFocus = true
    if (root.currentQueueIndex() >= 0) {
      root.p.selectedTab = "queue"
      Qt.callLater(root.focusCurrentQueueItem)
    }
    root.p.loadQueue()
  }

  function currentQueueIndex() {
    const queue = root.p.queueList || []
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
      root.p.selectedTab = "queue"
      Qt.callLater(root.focusCurrentQueueItem)
    }
  }

  function focusCurrentQueueItem() {
    if (!root.queueFocusPending) return
    if (root.p.selectedTab !== "queue") {
      root.queueFocusPending = false
      return
    }
    for (let i = 0; i < queueRepeater.count; ++i) {
      const row = queueRepeater.itemAt(i)
      if (!row || !row.isCurrent) continue
      const rowY = row.mapToItem(listCol, 0, 0).y
      const maxY = Math.max(0, trackViewport.contentHeight - trackViewport.height)
      trackViewport.contentY = Math.max(0, Math.min(rowY + row.height / 2 - trackViewport.height / 2, maxY))
      root.focusedQueueIndex = i
      root.queueFocusPending = false
      return
    }
    root.queueFocusPending = false
  }

  // Search / URL Input Bar
  Row {
    width: parent.width
    spacing: Style.space(4)

    BorderSurface {
      id: searchBox
      width: parent.width - Style.space(36)
      implicitHeight: Style.space(26)
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.controlSpec(urlInput.activeFocus ? "focused" : "normal", root.p.foreground, Color.accent)
      clip: true

      Item {
        anchors.fill: parent
        anchors.leftMargin: Style.space(6)
        anchors.rightMargin: Style.space(6)

        Text {
          id: searchIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "\uf002"
          color: root.p.dim
          font.family: root.p.fontFamily
          font.pixelSize: Style.font.caption
        }

        TextInput {
          id: urlInput
          anchors.left: searchIcon.right
          anchors.leftMargin: Style.space(6)
          anchors.right: clearBtn.visible ? clearBtn.left : parent.right
          anchors.rightMargin: clearBtn.visible ? Style.space(4) : 0
          anchors.verticalCenter: parent.verticalCenter
          text: root.p.urlInputText
          onTextChanged: root.p.urlInputText = text
          color: root.p.foreground
          font.family: root.p.fontFamily
          font.pixelSize: Style.font.caption
          selectByMouse: true
          clip: true
          onAccepted: root.p.searchTracks(text)

          Text {
            visible: !urlInput.text && !urlInput.activeFocus
            text: "Search songs, artists, or paste URL..."
            color: root.p.dim
            font.family: root.p.fontFamily
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
          color: clearMouse.containsMouse ? Color.accent : root.p.dim
          font.family: root.p.fontFamily
          font.pixelSize: Style.font.caption

          MouseArea {
            id: clearMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { urlInput.text = ""; root.p.clearSearch() }
          }
        }
      }
    }

    PanelActionButton {
      iconText: root.p.isSearching ? "\uf110" : "\uf002"
      tooltipText: "Search"
      foreground: root.p.foreground; hoverColor: Color.accent; fontFamily: root.p.fontFamily
      enabled: root.p.urlInputText.trim().length > 0 && !root.p.isSearching
      onClicked: root.p.searchTracks(root.p.urlInputText)
    }
  }

  // Styled Pill Tabs + Daemon Status
  Row {
    width: parent.width
    spacing: Style.space(4)

    // Search Tab Pill
    BorderSurface {
      visible: root.p.selectedTab === "search" || root.p.searchResults.length > 0 || root.p.isSearching
      implicitHeight: Style.space(22)
      implicitWidth: searchTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.p.selectedTab === "search" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.p.selectedTab === "search" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: searchTabText
        anchors.centerIn: parent
        text: "Search (" + root.p.searchResults.length + ")"
        color: root.p.selectedTab === "search" ? Color.accent : root.p.dim
        font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.p.selectedTab === "search"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: root.p.selectedTab = "search"
      }
    }

    // Recents Tab Pill
    BorderSurface {
      implicitHeight: Style.space(22)
      implicitWidth: recentsTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.p.selectedTab === "history" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.p.selectedTab === "history" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: recentsTabText
        anchors.centerIn: parent
        text: "Recents (" + root.p.historyList.length + ")"
        color: root.p.selectedTab === "history" ? Color.accent : root.p.dim
        font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.p.selectedTab === "history"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: { root.p.selectedTab = "history"; root.p.loadHistory() }
      }
    }

    // Queue Tab Pill
    BorderSurface {
      implicitHeight: Style.space(22)
      implicitWidth: queueTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.p.selectedTab === "queue" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.p.selectedTab === "queue" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: queueTabText
        anchors.centerIn: parent
        text: "Queue (" + (root.p.queueList ? root.p.queueList.length : root.p.queueCount) + ")"
        color: root.p.selectedTab === "queue" ? Color.accent : root.p.dim
        font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.p.selectedTab === "queue"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: root.showQueue()
      }
    }

    // Playlists Tab Pill
    BorderSurface {
      implicitHeight: Style.space(22)
      implicitWidth: plTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.p.selectedTab === "playlists" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.p.selectedTab === "playlists" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: plTabText
        anchors.centerIn: parent
        text: "Playlists (" + root.p.playlistsList.length + ")"
        color: root.p.selectedTab === "playlists" ? Color.accent : root.p.dim
        font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.p.selectedTab === "playlists"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: { root.p.selectedTab = "playlists"; root.p.loadPlaylists() }
      }
    }

    Item { width: Style.space(4) }

    // Daemon status icon
    PanelActionButton {
      iconText: "\uf011"
      tooltipText: root.p.isRunning ? "Stop background daemon" : "Daemon idle"
      foreground: root.p.isRunning ? root.p.foreground : root.p.dim
      hoverColor: root.p.urgent; fontFamily: root.p.fontFamily
      onClicked: { if (root.p.isRunning) root.p.stopDaemon(); else root.p.play() }
    }
  }

  // Scrollable Track / Playlist Container
  Flickable {
    id: trackViewport
    width: parent.width
    implicitHeight: Style.space(168)
    opacity: root.p.selectedTab === "queue" && root.queueFocusPending ? 0 : 1
    contentWidth: width
    contentHeight: listCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: listCol
      width: parent.width
      spacing: Style.space(3)

      // ==========================================
      // SEARCH TAB CONTENT
      // ==========================================
      Item {
        visible: root.p.selectedTab === "search" && root.p.isSearching
        width: parent.width; implicitHeight: Style.space(40)
        Row {
          anchors.centerIn: parent; spacing: Style.space(8)
          Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf110"; color: Color.accent; font.family: root.p.fontFamily; font.pixelSize: Style.font.bodySmall; RotationAnimator on rotation { running: root.p.isSearching; from: 0; to: 360; duration: 1000; loops: Animation.Infinite } }
          Text { anchors.verticalCenter: parent.verticalCenter; text: "Searching for \"" + root.p.searchQuery + "\"..."; color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption }
        }
      }

      Item {
        visible: root.p.selectedTab === "search" && !root.p.isSearching && root.p.searchResults.length === 0 && root.p.searchQuery !== ""
        width: parent.width; implicitHeight: Style.space(40)
        Text { anchors.centerIn: parent; text: "No tracks found for \"" + root.p.searchQuery + "\""; color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption }
      }

      Repeater {
        model: (root.p.selectedTab === "search" && !root.p.isSearching) ? root.p.searchResults : []
        delegate: BorderSurface {
          required property var modelData
          id: sRow
          readonly property bool isCurrent: (root.p.currentUrl === modelData.url) || (root.p.currentTrack === modelData.title && root.p.currentTrack !== "No track loaded")
          width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
          color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : (sRowMouse.containsMouse ? Style.hoverFillFor(root.p.foreground, Color.accent) : "transparent")
          borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

          MouseArea {
            id: sRowMouse
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: { if (modelData.url) root.p.playUrl(modelData.url, modelData.title, modelData.artist) }
          }

          Row {
            anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

            // Thumbnail
            BorderSurface {
              width: Style.space(24); height: Style.space(24); radius: Style.space(3)
              color: root.p.surface; borderSpec: Border.none()
              anchors.verticalCenter: parent.verticalCenter

              Image {
                visible: modelData.thumb !== undefined && modelData.thumb !== ""
                anchors.fill: parent
                source: root.p.artSource(modelData.thumb)
                fillMode: Image.PreserveAspectCrop; sourceSize.width: 48; sourceSize.height: 48
              }
              Text {
                visible: !modelData.thumb
                anchors.centerIn: parent; text: "\uf001"; color: sRow.isCurrent ? Color.accent : root.p.dim
                font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
              }
            }

            // Play / Loading status icon
            Text {
              visible: root.p.loadingVid === modelData.url
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf110"; color: Color.accent; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
              RotationAnimator on rotation { running: visible; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
            }

            Text {
              visible: root.p.loadingVid !== modelData.url
              anchors.verticalCenter: parent.verticalCenter
              text: sRow.isCurrent && root.p.isPlaying ? "\uf04c" : "\uf04b"
              color: sRow.isCurrent ? Color.accent : (sRowMouse.containsMouse ? Color.accent : root.p.dim)
              font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
            }

            // Title & Artist
            Column {
              width: parent.width - Style.space(90)
              anchors.verticalCenter: parent.verticalCenter; spacing: 1

              Text {
                width: parent.width; textFormat: Text.PlainText
                text: modelData.title || "Track"
                color: sRow.isCurrent ? Color.accent : root.p.foreground
                font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                elide: Text.ElideRight
              }
              Text {
                visible: modelData.artist !== ""
                width: parent.width; textFormat: Text.PlainText
                text: modelData.artist || ""
                color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.82
                elide: Text.ElideRight
              }
            }

            // Add to Queue button
            Text {
              z: 2
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf067"
              color: sQueueMouse.containsMouse ? Color.accent : root.p.dim
              font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
              MouseArea {
                id: sQueueMouse
                anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.p.queueUrl(modelData.url, modelData.title, modelData.artist)
              }
            }

            // Duration
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.duration || ""
              color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // ==========================================
      // RECENTS TAB CONTENT
      // ==========================================
      Repeater {
        model: root.p.selectedTab === "history" ? root.p.historyList : []
        delegate: BorderSurface {
          required property var modelData
          id: hRow
          readonly property bool isCurrent: (root.p.currentUrl === modelData.path) || (root.p.currentTrack === modelData.title && root.p.currentTrack !== "No track loaded")
          width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
          color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : (hRowMouse.containsMouse ? Style.hoverFillFor(root.p.foreground, Color.accent) : "transparent")
          borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

          MouseArea {
            id: hRowMouse
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: { if (modelData.path) root.p.playUrl(modelData.path, modelData.title, modelData.artist) }
          }

          Row {
            anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

            // Thumbnail
            BorderSurface {
              width: Style.space(24); height: Style.space(24); radius: Style.space(3)
              color: root.p.surface; borderSpec: Border.none()
              anchors.verticalCenter: parent.verticalCenter

              Image {
                visible: modelData.thumb !== undefined && modelData.thumb !== ""
                anchors.fill: parent
                source: root.p.artSource(modelData.thumb)
                fillMode: Image.PreserveAspectCrop; sourceSize.width: 48; sourceSize.height: 48
              }
              Text {
                visible: !modelData.thumb
                anchors.centerIn: parent; text: "\uf001"; color: hRow.isCurrent ? Color.accent : root.p.dim
                font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
              }
            }

            // Play / Loading icon
            Text {
              visible: root.p.loadingVid === modelData.path
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf110"; color: Color.accent; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
              RotationAnimator on rotation { running: visible; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
            }

            Text {
              visible: root.p.loadingVid !== modelData.path
              anchors.verticalCenter: parent.verticalCenter
              text: hRow.isCurrent && root.p.isPlaying ? "\uf04c" : "\uf04b"
              color: hRow.isCurrent ? Color.accent : (hRowMouse.containsMouse ? Color.accent : root.p.dim)
              font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
            }

            // Title & Artist
            Column {
              width: parent.width - Style.space(90)
              anchors.verticalCenter: parent.verticalCenter; spacing: 1

              Text {
                width: parent.width; textFormat: Text.PlainText
                text: modelData.title || "Track"
                color: hRow.isCurrent ? Color.accent : root.p.foreground
                font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                elide: Text.ElideRight
              }
              Text {
                visible: modelData.artist !== ""
                width: parent.width; textFormat: Text.PlainText
                text: modelData.artist || ""
                color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.82
                elide: Text.ElideRight
              }
            }

            // Add to Queue button
            Text {
              z: 2
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf067"
              color: hQueueMouse.containsMouse ? Color.accent : root.p.dim
              font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
              MouseArea {
                id: hQueueMouse
                anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.p.queueUrl(modelData.path, modelData.title, modelData.artist)
              }
            }

            // Duration
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: {
                var s = modelData.duration_secs || 0
                var m = Math.floor(s / 60), sec = s % 60
                return (m > 0 || sec > 0) ? (m + ":" + (sec < 10 ? "0" + sec : sec)) : ""
              }
              color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // ==========================================
      // QUEUE TAB CONTENT
      // ==========================================
      Column {
        visible: root.p.selectedTab === "queue"
        width: parent.width
        spacing: Style.space(4)

        // Queue Header Bar
        BorderSurface {
          visible: root.p.queueList && root.p.queueList.length > 0
          width: parent.width; implicitHeight: Style.space(28); radius: Style.cornerRadius
          color: Color.popups.background
          borderSpec: Border.controlSpec("normal", root.p.foreground, Color.accent)

          Row {
            anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)
            Text {
              width: parent.width - Style.space(80); anchors.verticalCenter: parent.verticalCenter
              text: (root.p.queueSource === "mpd" ? "MPD Queue" : root.p.queueSource === "youtube" ? "YouTube Playlist" : "Queue")
                + " (" + root.p.queueList.length + " tracks)"
              color: Color.accent; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
              elide: Text.ElideRight
            }

            BorderSurface {
              visible: root.p.queueSource === "cliamp"
              implicitHeight: Style.space(20); implicitWidth: clearQText.implicitWidth + Style.space(10)
              radius: Style.cornerRadius
              color: clearQMouse.containsMouse ? root.p.shell.alpha(root.p.urgent, 0.25) : "transparent"
              borderSpec: Border.none()
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: clearQText; anchors.centerIn: parent
                text: "\uf1f8 Clear"
                color: clearQMouse.containsMouse ? root.p.urgent : root.p.dim
                font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.85
              }
              MouseArea {
                id: clearQMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.p.clearQueue()
              }
            }
          }
        }

        // Empty state
        Text {
          visible: !root.p.queueList || root.p.queueList.length === 0
          text: root.p.queueSource === "mpd" ? "MPD queue is empty"
            : root.p.queueSource === "youtube" ? "No playlist entries found"
            : "Queue is empty\nClick '+' on any song to add to queue"
          color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter; width: parent.width
        }

        // Queued tracks
        Repeater {
          id: queueRepeater
          model: root.p.selectedTab === "queue" ? root.p.queueList : []
          delegate: BorderSurface {
            required property int index
            required property var modelData
            id: qRow
            readonly property bool isCurrent: modelData.current === true
            width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
            color: isCurrent ? root.p.shell.alpha(Color.accent, 0.14)
              : qRowMouse.containsMouse ? Style.hoverFillFor(root.p.foreground, Color.accent) : "transparent"
            borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

            MouseArea {
              id: qRowMouse
              anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: root.p.playQueueItem(modelData, index)
            }

            Row {
              anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

              Text {
                width: Style.space(18); horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: qRow.isCurrent ? (root.p.playbackState === "playing" ? "\uf04c" : "\uf04b")
                  : (index + 1) < 10 ? ("0" + (index + 1)) : String(index + 1)
                color: qRow.isCurrent ? Color.accent : root.p.dim
                font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
              }

              // Thumbnail
              BorderSurface {
                width: Style.space(24); height: Style.space(24); radius: Style.space(3)
                color: root.p.surface; borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Image {
                  visible: modelData.thumb !== undefined && modelData.thumb !== ""
                  anchors.fill: parent
                  source: root.p.artSource(modelData.thumb)
                  fillMode: Image.PreserveAspectCrop; sourceSize.width: 48; sourceSize.height: 48
                }
                Text {
                  visible: !modelData.thumb
                  anchors.centerIn: parent; text: "\uf001"; color: root.p.dim
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
                }
              }

              // Title & Artist
              Column {
                width: parent.width - Style.space(80); anchors.verticalCenter: parent.verticalCenter; spacing: 1

                Text {
                  width: parent.width; textFormat: Text.PlainText
                  text: modelData.title || "Track"
                  color: qRow.isCurrent ? Color.accent : root.p.foreground
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  visible: modelData.artist !== ""
                  width: parent.width; textFormat: Text.PlainText
                  text: modelData.artist || ""
                  color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.82
                  elide: Text.ElideRight
                }
              }

              // Remove button
              BorderSurface {
                z: 2
                visible: root.p.queueSource === "cliamp" && !qRow.isCurrent
                width: Style.space(20); height: Style.space(20); radius: Style.cornerRadius
                color: qDelMouse.containsMouse ? root.p.shell.alpha(root.p.urgent, 0.25) : "transparent"
                borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent; text: "\uf00d"
                  color: qDelMouse.containsMouse ? root.p.urgent : root.p.dim
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.85
                }
                MouseArea {
                  id: qDelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.p.removeFromQueue(modelData.queueIndex === undefined ? index : modelData.queueIndex)
                }
              }
            }
          }
        }
      }

      // ==========================================
      // PLAYLISTS TAB CONTENT
      // ==========================================
      Column {
        visible: root.p.selectedTab === "playlists"
        width: parent.width
        spacing: Style.space(6)

        // ----------------------------------------------------
        // SUBVIEW 1: ACTIVE PLAYLIST TRACKS BROWSER
        // ----------------------------------------------------
        Column {
          visible: root.p.activePlaylist !== null
          width: parent.width
          spacing: Style.space(4)

          // Header Card with Back, Title, Play All, Delete
          BorderSurface {
            width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
            color: Color.popups.background
            borderSpec: Border.controlSpec("normal", root.p.foreground, Color.accent)

            Row {
              anchors.fill: parent; anchors.margins: Style.space(6); spacing: Style.space(8)

              // Back button
              BorderSurface {
                width: Style.space(22); height: Style.space(20); radius: Style.cornerRadius
                color: backMouse.containsMouse ? root.p.shell.hoverFill(1) : root.p.shell.alpha(root.p.foreground, 0.06)
                borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent; text: "\uf060"
                  color: backMouse.containsMouse ? Color.accent : root.p.foreground
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.p.closePlaylist()
                }
              }

              // Title + Count
              Text {
                width: parent.width - Style.space(130)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: (root.p.activePlaylist ? root.p.activePlaylist.name : "") + " (" + ((root.p.activePlaylist && root.p.activePlaylist.tracks) ? root.p.activePlaylist.tracks.length : 0) + ")"
                color: Color.accent; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                elide: Text.ElideRight
              }

              // Play All Button
              BorderSurface {
                implicitHeight: Style.space(20)
                implicitWidth: playAllText.implicitWidth + Style.space(10)
                radius: Style.cornerRadius
                color: playAllMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2)
                borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: playAllText; anchors.centerIn: parent
                  text: "\uf04b Play All"
                  color: playAllMouse.containsMouse ? Color.menu.selectedText : Color.accent
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.85; font.bold: true
                }
                MouseArea {
                  id: playAllMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.p.playPlaylist(root.p.activePlaylist)
                }
              }

              // Delete button
              BorderSurface {
                visible: root.p.activePlaylist && !root.p.activePlaylist.system
                width: Style.space(20); height: Style.space(20); radius: Style.cornerRadius
                color: delPlMouse.containsMouse ? root.p.shell.alpha(root.p.urgent, 0.25) : "transparent"
                borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent; text: "\uf1f8"
                  color: delPlMouse.containsMouse ? root.p.urgent : root.p.dim
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: delPlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.p.deletePlaylist(root.p.activePlaylist.name)
                }
              }
            }
          }

          // Empty playlist notice
          Text {
            visible: root.p.activePlaylist && (!root.p.activePlaylist.tracks || root.p.activePlaylist.tracks.length === 0)
            text: "No tracks found in this playlist"
            color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter; width: parent.width
          }

          // Individual tracks inside active playlist
          Repeater {
            model: (root.p.activePlaylist && root.p.activePlaylist.tracks) ? root.p.activePlaylist.tracks : []
            delegate: BorderSurface {
              required property int index
              required property var modelData
              id: plTrackRow
              readonly property bool isCurrent: (root.p.currentUrl === modelData.url) || (root.p.currentTrack === modelData.title && root.p.currentTrack !== "No track loaded")
              width: parent.width; implicitHeight: Style.space(28); radius: Style.cornerRadius
              color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12) : (plTrackRowMouse.containsMouse ? Style.hoverFillFor(root.p.foreground, Color.accent) : "transparent")
              borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

              MouseArea {
                id: plTrackRowMouse
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.p.playUrl(modelData.url, modelData.title, modelData.artist)
              }

              Row {
                anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

                // Track Number
                Text {
                  width: Style.space(18); horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                  text: (index + 1) < 10 ? ("0" + (index + 1)) : String(index + 1)
                  color: plTrackRow.isCurrent ? Color.accent : root.p.dim
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
                }

                // Play icon
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: plTrackRow.isCurrent && root.p.isPlaying ? "\uf04c" : "\uf04b"
                  color: plTrackRow.isCurrent ? Color.accent : (plTrackRowMouse.containsMouse ? Color.accent : root.p.dim)
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
                }

                // Title & Artist
                Column {
                  width: parent.width - Style.space(90); anchors.verticalCenter: parent.verticalCenter; spacing: 1
                  Text {
                    width: parent.width; textFormat: Text.PlainText
                    text: modelData.title || "Track"
                    color: plTrackRow.isCurrent ? Color.accent : root.p.foreground
                    font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: modelData.artist !== ""
                    width: parent.width; textFormat: Text.PlainText
                    text: modelData.artist || ""
                    color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
                    elide: Text.ElideRight
                  }
                }

                // Add to Queue Button
                Text {
                  z: 2
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uf067"
                  color: plQueueMouse.containsMouse ? Color.accent : root.p.dim
                  font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
                  MouseArea {
                    id: plQueueMouse
                    anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.p.queueUrl(modelData.url, modelData.title, modelData.artist)
                  }
                }

                // Duration
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.duration || ""
                  color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }

        // ----------------------------------------------------
        // SUBVIEW 2: PLAYLISTS OVERVIEW & IMPORT BAR
        // ----------------------------------------------------
        Column {
          visible: root.p.activePlaylist === null
          width: parent.width
          spacing: Style.space(4)

          // Importing status banner
          BorderSurface {
            visible: root.p.isImportingPl
            width: parent.width; implicitHeight: Style.space(28); radius: Style.cornerRadius
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
            borderSpec: Border.flat(Color.accent, 1)

            Row {
              anchors.centerIn: parent; spacing: Style.space(6)
              Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf110"; color: Color.accent; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; RotationAnimator on rotation { running: root.p.isImportingPl; from: 0; to: 360; duration: 1000; loops: Animation.Infinite } }
              Text { anchors.verticalCenter: parent.verticalCenter; text: "Importing playlist tracks..."; color: root.p.foreground; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            }
          }

          // Import error notice
          Text {
            visible: root.p.plImportError !== ""
            text: root.p.plImportError
            color: root.p.urgent; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
          }

          // List of Playlists
          Repeater {
            model: root.p.playlistsList
            delegate: BorderSurface {
              required property var modelData
              id: plCard
              width: parent.width; implicitHeight: Style.space(34); radius: Style.cornerRadius
              color: plCardMouse.containsMouse ? Style.hoverFillFor(root.p.foreground, Color.accent) : Color.popups.background
              borderSpec: Border.controlSpec("normal", root.p.foreground, Color.accent)

              // Main row click opens playlist
              MouseArea {
                id: plCardMouse
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.p.openPlaylist(modelData)
              }

              Row {
                anchors.fill: parent; anchors.margins: Style.space(6); spacing: Style.space(8)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.system ? "\uf017" : "\uf0ca"
                  color: Color.accent; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption
                }

                Column {
                  width: parent.width - Style.space(90); anchors.verticalCenter: parent.verticalCenter; spacing: 1
                  Text {
                    width: parent.width; textFormat: Text.PlainText
                    text: modelData.name || "Playlist"
                    color: root.p.foreground; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    text: modelData.count + " tracks"
                    color: root.p.dim; font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.85
                  }
                }

                // Quick Play All button
                BorderSurface {
                  z: 2
                  width: Style.space(22); height: Style.space(22); radius: Style.cornerRadius
                  color: plPlayMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                  borderSpec: Border.none()
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent; text: "\uf04b"
                    color: plPlayMouse.containsMouse ? Color.menu.selectedText : Color.accent
                    font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.8
                  }
                  MouseArea {
                    id: plPlayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (modelData.system) {
                        root.p.openPlaylist(modelData)
                        root.p.playPlaylist(root.p.activePlaylist)
                      } else {
                        root.p.playPlaylist(modelData)
                      }
                    }
                  }
                }

                // Delete playlist button
                BorderSurface {
                  z: 2
                  visible: !modelData.system
                  width: Style.space(22); height: Style.space(22); radius: Style.cornerRadius
                  color: plDelMouse.containsMouse ? root.p.shell.alpha(root.p.urgent, 0.25) : "transparent"
                  borderSpec: Border.none()
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent; text: "\uf1f8"
                    color: plDelMouse.containsMouse ? root.p.urgent : root.p.dim
                    font.family: root.p.fontFamily; font.pixelSize: Style.font.caption * 0.85
                  }
                  MouseArea {
                    id: plDelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.p.deletePlaylist(modelData.name)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
