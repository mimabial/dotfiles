pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

Column {
  id: root
  required property var controller
  property alias urlInput: urlInput
  property bool queueFocusPending: false
  property bool queueRefreshFocus: false
  property int focusedQueueIndex: -1

  width: parent ? parent.width : 0
  spacing: Style.space(6)

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

  Row {
    width: parent.width
    spacing: Style.space(4)

    BorderSurface {
      visible: root.controller.selectedTab === "search" || root.controller.searchResults.length > 0 || root.controller.isSearching
      implicitHeight: Style.space(22)
      implicitWidth: searchTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.controller.selectedTab === "search" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.controller.selectedTab === "search" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: searchTabText
        anchors.centerIn: parent
        text: "Search (" + root.controller.searchResults.length + ")"
        color: root.controller.selectedTab === "search" ? Color.accent : root.controller.dim
        font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.controller.selectedTab === "search"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: root.controller.selectedTab = "search"
      }
    }

    BorderSurface {
      implicitHeight: Style.space(22)
      implicitWidth: recentsTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.controller.selectedTab === "history" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.controller.selectedTab === "history" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: recentsTabText
        anchors.centerIn: parent
        text: "Recents (" + root.controller.historyList.length + ")"
        color: root.controller.selectedTab === "history" ? Color.accent : root.controller.dim
        font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.controller.selectedTab === "history"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: { root.controller.selectedTab = "history"; root.controller.loadHistory() }
      }
    }

    BorderSurface {
      implicitHeight: Style.space(22)
      implicitWidth: queueTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.controller.selectedTab === "queue" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.controller.selectedTab === "queue" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: queueTabText
        anchors.centerIn: parent
        text: "Queue (" + root.controller.queueList.length + ")"
        color: root.controller.selectedTab === "queue" ? Color.accent : root.controller.dim
        font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.controller.selectedTab === "queue"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: root.showQueue()
      }
    }

    BorderSurface {
      implicitHeight: Style.space(22)
      implicitWidth: plTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.controller.selectedTab === "playlists" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.controller.selectedTab === "playlists" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: plTabText
        anchors.centerIn: parent
        text: "Playlists (" + root.controller.playlistsList.length + ")"
        color: root.controller.selectedTab === "playlists" ? Color.accent : root.controller.dim
        font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.controller.selectedTab === "playlists"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: { root.controller.selectedTab = "playlists"; root.controller.loadPlaylists() }
      }
    }

    BorderSurface {
      implicitHeight: Style.space(22)
      implicitWidth: filesTabText.implicitWidth + Style.space(14)
      radius: Style.cornerRadius
      color: root.controller.selectedTab === "files" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.18) : "transparent"
      borderSpec: root.controller.selectedTab === "files" ? Border.flat(Color.accent, 1) : Border.none()

      Text {
        id: filesTabText
        anchors.centerIn: parent
        text: root.controller.filesList.length ? "Files (" + root.controller.filesList.length + ")" : "Files"
        color: root.controller.selectedTab === "files" ? Color.accent : root.controller.dim
        font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
        font.bold: root.controller.selectedTab === "files"
      }

      MouseArea {
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: { root.controller.selectedTab = "files"; root.controller.loadFiles(root.controller.filesPath) }
      }
    }

    Item { width: Style.space(4) }

    PanelActionButton {
      iconText: "\uf011"
      tooltipText: root.controller.isRunning ? "Stop background daemon" : "Daemon idle"
      foreground: root.controller.isRunning ? root.controller.foreground : root.controller.dim
      hoverColor: root.controller.urgent; fontFamily: root.controller.fontFamily
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

      Item {
        visible: root.controller.selectedTab === "search" && root.controller.isSearching
        width: parent.width; implicitHeight: Style.space(40)
        Row {
          anchors.centerIn: parent; spacing: Style.space(8)
          Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf110"; color: Color.accent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.bodySmall; RotationAnimator on rotation { running: root.controller.isSearching; from: 0; to: 360; duration: 1000; loops: Animation.Infinite } }
          Text { anchors.verticalCenter: parent.verticalCenter; text: "Searching for \"" + root.controller.searchQuery + "\"..."; color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption }
        }
      }

      Item {
        visible: root.controller.selectedTab === "search" && !root.controller.isSearching && root.controller.searchResults.length === 0 && root.controller.searchQuery !== ""
        width: parent.width; implicitHeight: Style.space(40)
        Text { anchors.centerIn: parent; text: "No tracks found for \"" + root.controller.searchQuery + "\""; color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption }
      }

      Repeater {
        model: (root.controller.selectedTab === "search" && !root.controller.isSearching) ? root.controller.searchResults : []
        delegate: BorderSurface {
          required property var modelData
          id: sRow
          readonly property bool isCurrent: (root.controller.currentUrl === modelData.url) || (root.controller.currentTrack === modelData.title && root.controller.currentTrack !== "No track loaded")
          width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
          color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : (sRowMouse.containsMouse ? Style.hoverFillFor(root.controller.foreground, Color.accent) : "transparent")
          borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

          MouseArea {
            id: sRowMouse
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.controller.playOrToggle(sRow.isCurrent, sRow.modelData.url, sRow.modelData.title, sRow.modelData.artist)
          }

          Row {
            anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

            BorderSurface {
              id: sThumb; width: Style.space(24); height: Style.space(24); radius: Style.space(3)
              color: root.controller.surface; borderSpec: Border.none()
              anchors.verticalCenter: parent.verticalCenter

              Image {
                visible: sRow.modelData.thumb !== undefined && sRow.modelData.thumb !== ""
                anchors.fill: parent
                source: root.controller.artSource(sRow.modelData.thumb)
                fillMode: Image.PreserveAspectCrop; sourceSize.width: 48; sourceSize.height: 48
              }
              Text {
                visible: !sRow.modelData.thumb
                anchors.centerIn: parent; text: "\uf001"; color: sRow.isCurrent ? Color.accent : root.controller.dim
                font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8
              }
            }

            Column {
              width: parent.width - sThumb.width - sTail.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter; spacing: 1

              Text {
                width: parent.width; textFormat: Text.PlainText
                text: sRow.modelData.title || "Track"
                color: sRow.isCurrent ? Color.accent : root.controller.foreground
                font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                elide: Text.ElideRight
              }
              Text {
                visible: sRow.modelData.artist !== ""
                width: parent.width; textFormat: Text.PlainText
                text: sRow.modelData.artist || ""
                color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.82
                elide: Text.ElideRight
              }
            }

            Row { id: sTail; z: 2; spacing: parent.spacing; anchors.verticalCenter: parent.verticalCenter
              Text {
                id: searchLoadingSpinner
                visible: root.controller.loadingVid === sRow.modelData.url
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf110"; color: Color.accent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                RotationAnimator on rotation { running: searchLoadingSpinner.visible; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
              }

              Text {
                z: 2
                visible: root.controller.loadingVid !== sRow.modelData.url
                anchors.verticalCenter: parent.verticalCenter
                text: sRow.isCurrent && root.controller.isPlaying ? "\uead1" : "\ueb2c"
                color: sRow.isCurrent ? Color.accent : (sPlayMouse.containsMouse ? Color.accent : root.controller.dim)
                font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * Style.iconScale(text)
                MouseArea {
                  id: sPlayMouse
                  anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.controller.playOrToggle(sRow.isCurrent, sRow.modelData.url, sRow.modelData.title, sRow.modelData.artist)
                }
              }

              Text {
                z: 2
                anchors.verticalCenter: parent.verticalCenter
                text: "\uea60"
                color: sQueueMouse.containsMouse ? Color.accent : root.controller.dim
                font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                MouseArea {
                  id: sQueueMouse
                  anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.controller.queueUrl(sRow.modelData.url, sRow.modelData.title, sRow.modelData.artist)
                }
              }

              RowLike { controller: root.controller; url: sRow.modelData.url || ""; title: sRow.modelData.title || ""; artist: sRow.modelData.artist || "" }

              Text {
                visible: text !== ""; anchors.verticalCenter: parent.verticalCenter
                text: sRow.modelData.duration || ""
                color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }

      Repeater {
        model: root.controller.selectedTab === "history" ? root.controller.historyGroups : []
        delegate: Column {
          id: hGroup
          required property var modelData
          width: parent.width; spacing: Style.space(3)

          Text {
            text: hGroup.modelData.label; color: Color.accent
            font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8; font.bold: true
          }

          Repeater {
            model: hGroup.modelData.items
            delegate: BorderSurface {
              required property var modelData
              id: hRow
              readonly property bool isCurrent: (root.controller.currentUrl === modelData.path) || (root.controller.currentTrack === modelData.title && root.controller.currentTrack !== "No track loaded")
              width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
              color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : (hRowMouse.containsMouse ? Style.hoverFillFor(root.controller.foreground, Color.accent) : "transparent")
              borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

              MouseArea {
                id: hRowMouse
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.controller.playOrToggle(hRow.isCurrent, hGroup.modelData.path, hGroup.modelData.title, hGroup.modelData.artist)
              }

              Row {
                anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

                BorderSurface {
                  id: hThumb; width: Style.space(24); height: Style.space(24); radius: Style.space(3)
                  color: root.controller.surface; borderSpec: Border.none()
                  anchors.verticalCenter: parent.verticalCenter

                  Image {
                    visible: hGroup.modelData.thumb !== undefined && hGroup.modelData.thumb !== ""
                    anchors.fill: parent
                    source: root.controller.artSource(hGroup.modelData.thumb)
                    fillMode: Image.PreserveAspectCrop; sourceSize.width: 48; sourceSize.height: 48
                  }
                  Text {
                    visible: !hGroup.modelData.thumb
                    anchors.centerIn: parent; text: "\uf001"; color: hRow.isCurrent ? Color.accent : root.controller.dim
                    font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8
                  }
                }

                Column {
                  width: parent.width - hThumb.width - hTail.width - parent.spacing * 2
                  anchors.verticalCenter: parent.verticalCenter; spacing: 1

                  Text {
                    width: parent.width; textFormat: Text.PlainText
                    text: hGroup.modelData.title || "Track"
                    color: hRow.isCurrent ? Color.accent : root.controller.foreground
                    font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: hGroup.modelData.artist !== ""
                    width: parent.width; textFormat: Text.PlainText
                    text: hGroup.modelData.artist || ""
                    color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.82
                    elide: Text.ElideRight
                  }
                }

                Row { id: hTail; z: 2; spacing: parent.spacing; anchors.verticalCenter: parent.verticalCenter
                  Text {
                    id: historyLoadingSpinner
                    visible: root.controller.loadingVid === hGroup.modelData.path
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf110"; color: Color.accent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                    RotationAnimator on rotation { running: historyLoadingSpinner.visible; from: 0; to: 360; duration: 1000; loops: Animation.Infinite }
                  }

                  Text {
                    z: 2
                    visible: root.controller.loadingVid !== hGroup.modelData.path
                    anchors.verticalCenter: parent.verticalCenter
                    text: hRow.isCurrent && root.controller.isPlaying ? "\uead1" : "\ueb2c"
                    color: hRow.isCurrent ? Color.accent : (hPlayMouse.containsMouse ? Color.accent : root.controller.dim)
                    font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * Style.iconScale(text)
                    MouseArea {
                      id: hPlayMouse
                      anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: root.controller.playOrToggle(hRow.isCurrent, hGroup.modelData.path, hGroup.modelData.title, hGroup.modelData.artist)
                    }
                  }

                  Text {
                    z: 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uea60"
                    color: hQueueMouse.containsMouse ? Color.accent : root.controller.dim
                    font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                    MouseArea {
                      id: hQueueMouse
                      anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: root.controller.queueUrl(hGroup.modelData.path, hGroup.modelData.title, hGroup.modelData.artist)
                    }
                  }

                  RowLike { controller: root.controller; url: hRow.modelData.path || ""; title: hRow.modelData.title || ""; artist: hRow.modelData.artist || "" }

                  Text {
                    visible: text !== ""; anchors.verticalCenter: parent.verticalCenter
                    text: {
                      var s = hGroup.modelData.duration_secs || 0
                      var m = Math.floor(s / 60), sec = s % 60
                      return (m > 0 || sec > 0) ? (m + ":" + (sec < 10 ? "0" + sec : sec)) : ""
                    }
                    color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }
      }

      Column {
        visible: root.controller.selectedTab === "queue"
        width: parent.width
        spacing: Style.space(4)

        BorderSurface {
          visible: root.controller.queueList && root.controller.queueList.length > 0
          width: parent.width; implicitHeight: Style.space(28); radius: Style.cornerRadius
          color: Color.popups.background
          borderSpec: Border.controlSpec("normal", root.controller.foreground, Color.accent)

          Row {
            anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)
            Text {
              width: parent.width - (clearQ.visible ? clearQ.width + parent.spacing : 0); anchors.verticalCenter: parent.verticalCenter
              text: (root.controller.queueSource === "mpd" ? "MPD Queue" : root.controller.queueSource === "youtube" ? "YouTube Playlist" : "Queue")
                + " (" + root.controller.queueList.length + " tracks)"
              color: Color.accent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
              elide: Text.ElideRight
            }

            BorderSurface {
              id: clearQ; visible: root.controller.queueSource === "cliamp"
              implicitHeight: Style.space(20); implicitWidth: clearQText.implicitWidth + Style.space(10)
              radius: Style.cornerRadius
              color: clearQMouse.containsMouse ? root.controller.shell.alpha(root.controller.urgent, 0.25) : "transparent"
              borderSpec: Border.none()
              anchors.verticalCenter: parent.verticalCenter

              Text {
                id: clearQText; anchors.centerIn: parent
                text: "\uf1f8 Clear"
                color: clearQMouse.containsMouse ? root.controller.urgent : root.controller.dim
                font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.85
              }
              MouseArea {
                id: clearQMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.controller.clearQueue()
              }
            }
          }
        }

        Text {
          visible: !root.controller.queueList || root.controller.queueList.length === 0
          text: root.controller.queueSource === "mpd" ? "MPD queue is empty"
            : root.controller.queueSource === "youtube" ? "No playlist entries found"
            : "Queue is empty\nClick '+' on any song to add to queue"
          color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter; width: parent.width
        }

        Repeater {
          id: queueRepeater
          model: root.controller.selectedTab === "queue" ? root.controller.queueList : []
          delegate: BorderSurface {
            required property int index
            required property var modelData
            id: qRow
            readonly property bool isCurrent: modelData.current === true
            width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
            color: isCurrent ? root.controller.shell.alpha(Color.accent, 0.14)
              : qRowMouse.containsMouse ? Style.hoverFillFor(root.controller.foreground, Color.accent) : "transparent"
            borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

            MouseArea {
              id: qRowMouse
              anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: root.controller.playQueueItem(qRow.modelData, qRow.index)
            }

            Row {
              anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

              Text {
                id: qIdx; width: Style.space(18); horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                text: qRow.isCurrent ? (root.controller.playbackState === "playing" ? "\uf04c" : "\uf04b")
                  : (qRow.index + 1) < 10 ? ("0" + (qRow.index + 1)) : String(qRow.index + 1)
                color: qRow.isCurrent ? Color.accent : root.controller.dim
                font.family: root.controller.fontFamily
                font.pixelSize: Style.font.caption * 0.8
              }

              BorderSurface {
                id: qThumb; width: Style.space(24); height: Style.space(24); radius: Style.space(3)
                color: root.controller.surface; borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Image {
                  visible: qRow.modelData.thumb !== undefined && qRow.modelData.thumb !== ""
                  anchors.fill: parent
                  source: root.controller.artSource(qRow.modelData.thumb)
                  fillMode: Image.PreserveAspectCrop; sourceSize.width: 48; sourceSize.height: 48
                }
                Text {
                  visible: !qRow.modelData.thumb
                  anchors.centerIn: parent; text: "\uf001"; color: root.controller.dim
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8
                }
              }

              Column {
                width: parent.width - qIdx.width - qThumb.width - qTail.width - parent.spacing * 3; anchors.verticalCenter: parent.verticalCenter; spacing: 1

                Text {
                  width: parent.width; textFormat: Text.PlainText
                  text: qRow.modelData.title || "Track"
                  color: qRow.isCurrent ? Color.accent : root.controller.foreground
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  visible: qRow.modelData.artist !== ""
                  width: parent.width; textFormat: Text.PlainText
                  text: qRow.modelData.artist || ""
                  color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.82
                  elide: Text.ElideRight
                }
              }

              Row { id: qTail; z: 2; spacing: parent.spacing; anchors.verticalCenter: parent.verticalCenter
                BorderSurface {
                  z: 2
                  visible: root.controller.queueSource === "cliamp" && !qRow.isCurrent
                  width: Style.space(20); height: Style.space(20); radius: Style.cornerRadius
                  color: qDelMouse.containsMouse ? root.controller.shell.alpha(root.controller.urgent, 0.25) : "transparent"
                  borderSpec: Border.none()
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    anchors.centerIn: parent; text: "\uf00d"
                    color: qDelMouse.containsMouse ? root.controller.urgent : root.controller.dim
                    font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.85
                  }
                  MouseArea {
                    id: qDelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.controller.removeFromQueue(qRow.modelData.queueIndex === undefined ? qRow.index : qRow.modelData.queueIndex)
                  }
                }

                RowLike { controller: root.controller; url: qRow.modelData.url || ""; title: qRow.modelData.title || ""; artist: qRow.modelData.artist || "" }
              }
            }
          }
        }
      }

      Column {
        visible: root.controller.selectedTab === "playlists"
        width: parent.width
        spacing: Style.space(6)

        Column {
          visible: root.controller.activePlaylist !== null
          width: parent.width
          spacing: Style.space(4)

          BorderSurface {
            width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
            color: Color.popups.background
            borderSpec: Border.controlSpec("normal", root.controller.foreground, Color.accent)

            Row {
              anchors.fill: parent; anchors.margins: Style.space(6); spacing: Style.space(8)

              BorderSurface {
                width: Style.space(22); height: Style.space(20); radius: Style.cornerRadius
                color: backMouse.containsMouse ? root.controller.shell.hoverFill(1) : root.controller.shell.alpha(root.controller.foreground, 0.06)
                borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent; text: "\uf060"
                  color: backMouse.containsMouse ? Color.accent : root.controller.foreground
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: backMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.controller.closePlaylist()
                }
              }

              Text {
                width: parent.width - Style.space(130)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: (root.controller.activePlaylist ? root.controller.activePlaylist.name : "") + " (" + ((root.controller.activePlaylist && root.controller.activePlaylist.tracks) ? root.controller.activePlaylist.tracks.length : 0) + ")"
                color: Color.accent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                elide: Text.ElideRight
              }

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
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.85; font.bold: true
                }
                MouseArea {
                  id: playAllMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.controller.playPlaylist(root.controller.activePlaylist)
                }
              }

              BorderSurface {
                visible: root.controller.activePlaylist && !root.controller.activePlaylist.system
                width: Style.space(20); height: Style.space(20); radius: Style.cornerRadius
                color: delPlMouse.containsMouse ? root.controller.shell.alpha(root.controller.urgent, 0.25) : "transparent"
                borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent; text: "\uf1f8"
                  color: delPlMouse.containsMouse ? root.controller.urgent : root.controller.dim
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                }
                MouseArea {
                  id: delPlMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: root.controller.deletePlaylist(root.controller.activePlaylist.name)
                }
              }
            }
          }

          Text {
            visible: root.controller.activePlaylist && (!root.controller.activePlaylist.tracks || root.controller.activePlaylist.tracks.length === 0)
            text: "No tracks found in this playlist"
            color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter; width: parent.width
          }

          Repeater {
            model: (root.controller.activePlaylist && root.controller.activePlaylist.tracks) ? root.controller.activePlaylist.tracks : []
            delegate: BorderSurface {
              required property int index
              required property var modelData
              id: plTrackRow
              readonly property bool isCurrent: (root.controller.currentUrl === modelData.url) || (root.controller.currentTrack === modelData.title && root.controller.currentTrack !== "No track loaded")
              width: parent.width; implicitHeight: Style.space(28); radius: Style.cornerRadius
              color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12) : (plTrackRowMouse.containsMouse ? Style.hoverFillFor(root.controller.foreground, Color.accent) : "transparent")
              borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

              MouseArea {
                id: plTrackRowMouse
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.controller.playOrToggle(plTrackRow.isCurrent, plTrackRow.modelData.url, plTrackRow.modelData.title, plTrackRow.modelData.artist)
              }

              Row {
                anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

                Text {
                  id: plIdx; width: Style.space(18); horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                  text: (plTrackRow.index + 1) < 10 ? ("0" + (plTrackRow.index + 1)) : String(plTrackRow.index + 1)
                  color: plTrackRow.isCurrent ? Color.accent : root.controller.dim
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8
                }

                Text {
                  id: plPlay; anchors.verticalCenter: parent.verticalCenter
                  text: plTrackRow.isCurrent && root.controller.isPlaying ? "\uead1" : "\ueb2c"
                  color: plTrackRow.isCurrent ? Color.accent : (plTrackRowMouse.containsMouse ? Color.accent : root.controller.dim)
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8 * Style.iconScale(text)
                }

                Column {
                  width: parent.width - plIdx.width - plPlay.width - plTail.width - parent.spacing * 3; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                  Text {
                    width: parent.width; textFormat: Text.PlainText
                    text: plTrackRow.modelData.title || "Track"
                    color: plTrackRow.isCurrent ? Color.accent : root.controller.foreground
                    font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: plTrackRow.modelData.artist !== ""
                    width: parent.width; textFormat: Text.PlainText
                    text: plTrackRow.modelData.artist || ""
                    color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8
                    elide: Text.ElideRight
                  }
                }

                Row { id: plTail; z: 2; spacing: parent.spacing; anchors.verticalCenter: parent.verticalCenter
                  Text {
                    z: 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uea60"
                    color: plQueueMouse.containsMouse ? Color.accent : root.controller.dim
                    font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                    MouseArea {
                      id: plQueueMouse
                      anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: root.controller.queueUrl(plTrackRow.modelData.url, plTrackRow.modelData.title, plTrackRow.modelData.artist)
                    }
                  }

                  RowLike { controller: root.controller; url: plTrackRow.modelData.url || ""; title: plTrackRow.modelData.title || ""; artist: plTrackRow.modelData.artist || "" }

                  Text {
                    visible: text !== ""; anchors.verticalCenter: parent.verticalCenter
                    text: plTrackRow.modelData.plays ? plTrackRow.modelData.plays + "×" : plTrackRow.modelData.duration || ""
                    color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        Column {
          visible: root.controller.activePlaylist === null
          width: parent.width
          spacing: Style.space(4)

          BorderSurface {
            visible: root.controller.isImportingPl
            width: parent.width; implicitHeight: Style.space(28); radius: Style.cornerRadius
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
            borderSpec: Border.flat(Color.accent, 1)

            Row {
              anchors.centerIn: parent; spacing: Style.space(6)
              Text { anchors.verticalCenter: parent.verticalCenter; text: "\uf110"; color: Color.accent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; RotationAnimator on rotation { running: root.controller.isImportingPl; from: 0; to: 360; duration: 1000; loops: Animation.Infinite } }
              Text { anchors.verticalCenter: parent.verticalCenter; text: "Importing playlist tracks..."; color: root.controller.foreground; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            }
          }

          Text {
            visible: root.controller.plImportError !== ""
            text: root.controller.plImportError
            color: root.controller.urgent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
          }

          Repeater {
            model: root.controller.playlistsList
            delegate: BorderSurface {
              required property var modelData
              id: plCard
              width: parent.width; implicitHeight: Style.space(34); radius: Style.cornerRadius
              color: plCardMouse.containsMouse ? Style.hoverFillFor(root.controller.foreground, Color.accent) : Color.popups.background
              borderSpec: Border.controlSpec("normal", root.controller.foreground, Color.accent)

              MouseArea {
                id: plCardMouse
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.controller.openPlaylist(plCard.modelData)
              }

              Row {
                anchors.fill: parent; anchors.margins: Style.space(6); spacing: Style.space(8)

                Text {
                  id: plIcon; width: Style.space(9); anchors.verticalCenter: parent.verticalCenter
                  text: plCard.modelData.name === "Liked" ? "\uf004" : plCard.modelData.name === "Most Played" ? "\uf091" : plCard.modelData.system ? "\uf017" : "\uf0ca"
                  color: Color.accent; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                }

                Column {
                  width: parent.width - plIcon.width - plsTail.width - parent.spacing * 2; anchors.verticalCenter: parent.verticalCenter; spacing: 1
                  Text {
                    width: parent.width; textFormat: Text.PlainText
                    text: plCard.modelData.name || "Playlist"
                    color: root.controller.foreground; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    text: plCard.modelData.count + " tracks"
                    color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.85
                  }
                }

                Row { id: plsTail; z: 2; spacing: parent.spacing; anchors.verticalCenter: parent.verticalCenter
                  BorderSurface {
                    z: 2
                    width: Style.space(22); height: Style.space(22); radius: Style.cornerRadius
                    color: plPlayMouse.containsMouse ? Color.accent : Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
                    borderSpec: Border.none()
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent; text: "\uf04b"
                      color: plPlayMouse.containsMouse ? Color.menu.selectedText : Color.accent
                      font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8 * Style.iconScale(text)
                    }
                    MouseArea {
                      id: plPlayMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (plCard.modelData.system) {
                          root.controller.openPlaylist(plCard.modelData)
                          root.controller.playPlaylist(root.controller.activePlaylist)
                        } else {
                          root.controller.playPlaylist(plCard.modelData)
                        }
                      }
                    }
                  }

                  BorderSurface {
                    z: 2
                    visible: !plCard.modelData.system
                    width: Style.space(22); height: Style.space(22); radius: Style.cornerRadius
                    color: plDelMouse.containsMouse ? root.controller.shell.alpha(root.controller.urgent, 0.25) : "transparent"
                    borderSpec: Border.none()
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      anchors.centerIn: parent; text: "\uf1f8"
                      color: plDelMouse.containsMouse ? root.controller.urgent : root.controller.dim
                      font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.85
                    }
                    MouseArea {
                      id: plDelMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                      onClicked: root.controller.deletePlaylist(plCard.modelData.name)
                    }
                  }
                }
              }
            }
          }
        }
      }

      Column {
        visible: root.controller.selectedTab === "files"
        width: parent.width
        spacing: Style.space(3)

        // Up one level; doubles as the breadcrumb for where we are
        BorderSurface {
          visible: !root.controller.filesAtRoot
          width: parent.width; implicitHeight: Style.space(26); radius: Style.cornerRadius
          color: fUpMouse.containsMouse ? Style.hoverFillFor(root.controller.foreground, Color.accent) : "transparent"
          borderSpec: Border.none()

          Row {
            anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)
            Text {
              anchors.verticalCenter: parent.verticalCenter; text: "\uf062"
              color: fUpMouse.containsMouse ? Color.accent : root.controller.dim
              font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(30); elide: Text.ElideLeft
              text: root.controller.filesPath; textFormat: Text.PlainText
              color: root.controller.foreground; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
            }
          }
          MouseArea {
            id: fUpMouse
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: root.controller.loadFiles(root.controller.filesParent)
          }
        }

        Item {
          visible: root.controller.filesList.length === 0
          width: parent.width; implicitHeight: Style.space(40)
          Text {
            anchors.centerIn: parent
            text: root.controller.filesAtRoot ? "No audio in the music library" : "Nothing here"
            color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: root.controller.selectedTab === "files" ? root.controller.filesList : []
          delegate: BorderSurface {
            required property var modelData
            id: fRow
            readonly property bool isDir: modelData.kind === "dir"
            readonly property bool isCurrent: !isDir && root.controller.currentUrl === modelData.url
            width: parent.width; implicitHeight: Style.space(32); radius: Style.cornerRadius
            color: isCurrent ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.14) : (fRowMouse.containsMouse ? Style.hoverFillFor(root.controller.foreground, Color.accent) : "transparent")
            borderSpec: isCurrent ? Border.flat(Color.accent, 1) : Border.none()

            MouseArea {
              id: fRowMouse
              anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (fRow.isDir) root.controller.loadFiles(fRow.modelData.rel)
                else root.controller.playOrToggle(fRow.isCurrent, fRow.modelData.url, fRow.modelData.title, fRow.modelData.artist)
              }
            }

            Row {
              anchors.fill: parent; anchors.margins: Style.space(4); spacing: Style.space(6)

              BorderSurface {
                id: fThumb; width: Style.space(24); height: Style.space(24); radius: Style.space(3)
                color: root.controller.surface; borderSpec: Border.none()
                anchors.verticalCenter: parent.verticalCenter
                Image {
                  visible: !fRow.isDir && fRow.modelData.thumb !== undefined && fRow.modelData.thumb !== ""
                  anchors.fill: parent
                  source: root.controller.artSource(fRow.modelData.thumb)
                  fillMode: Image.PreserveAspectCrop; sourceSize.width: 48; sourceSize.height: 48
                }
                Text {
                  visible: fRow.isDir || !fRow.modelData.thumb
                  anchors.centerIn: parent; text: fRow.isDir ? "\uf07b" : "\uf001"
                  color: fRow.isCurrent ? Color.accent : root.controller.dim
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.8
                }
              }

              Column {
                width: parent.width - fThumb.width - fTail.width - parent.spacing * 2
                anchors.verticalCenter: parent.verticalCenter; spacing: 1

                Text {
                  width: parent.width; textFormat: Text.PlainText
                  text: fRow.modelData.title || ""
                  color: fRow.isCurrent ? Color.accent : root.controller.foreground
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption; font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  visible: fRow.modelData.artist !== ""
                  width: parent.width; textFormat: Text.PlainText
                  text: fRow.modelData.artist || ""
                  color: root.controller.dim; font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * 0.82
                  elide: Text.ElideRight
                }
              }

              Row { id: fTail; z: 2; spacing: parent.spacing; anchors.verticalCenter: parent.verticalCenter
                // Play button; on a folder it replaces the queue with everything under it
                Text {
                  z: 2
                  anchors.verticalCenter: parent.verticalCenter
                  text: fRow.isCurrent && root.controller.isPlaying ? "\uead1" : "\ueb2c"
                  color: fRow.isCurrent ? Color.accent : (fPlayMouse.containsMouse ? Color.accent : root.controller.dim)
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption * Style.iconScale(text)
                  MouseArea {
                    id: fPlayMouse
                    anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (fRow.isDir) root.controller.playDir(fRow.modelData.rel)
                      else root.controller.playOrToggle(fRow.isCurrent, fRow.modelData.url, fRow.modelData.title, fRow.modelData.artist)
                    }
                  }
                }

                // Add to Queue button; on a folder it queues everything under it
                Text {
                  z: 2
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uea60"
                  color: fQueueMouse.containsMouse ? Color.accent : root.controller.dim
                  font.family: root.controller.fontFamily; font.pixelSize: Style.font.caption
                  MouseArea {
                    id: fQueueMouse
                    anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (fRow.isDir) root.controller.queueDir(fRow.modelData.rel)
                      else root.controller.queueUrl(fRow.modelData.url, fRow.modelData.title, fRow.modelData.artist)
                    }
                  }
                }

                RowLike {
                  visible: !fRow.isDir
                  controller: root.controller; url: fRow.modelData.url || ""; title: fRow.modelData.title || ""; artist: fRow.modelData.artist || ""
                }
              }
            }
          }
        }
      }

    }
  }
}
