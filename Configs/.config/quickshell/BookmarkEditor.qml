import QtQuick
import "Commons" as Commons
import "Ui" as Ui

Item {
  id: root

  property bool opened: false
  property bool editing: false
  property bool fromClipboard: false
  property bool webDetailsEnabled: false
  property string bookmarkId: ""
  property string initialUrl: ""
  property string pendingFavicon: ""
  property string validationError: ""
  property var urlValidator: null

  readonly property bool canSubmit:
    urlField.text.trim().length > 0

  signal submitted(
    string bookmarkId,
    string title,
    string url,
    string tags,
    string keyword,
    string favicon
  )

  signal canceled()
  signal webDetailsSettingsRequested()

  function openForCreate() {
    root.openForClipboard(null)
    root.fromClipboard = false
  }

  function openForClipboard(item) {
    root.editing = false
    root.fromClipboard = Boolean(item)
    root.bookmarkId = ""
    root.validationError = ""
    titleField.text = String(item && item.title || "")
    urlField.text = String(item && item.url || "")
    tagsField.text = item && Array.isArray(item.tags) ? item.tags.join(", ") : ""
    keywordField.text = String(item && item.keyword || "")
    root.initialUrl = String(item && item.url || "")
    root.pendingFavicon = String(item && item.favicon || "")
    root.opened = true

    Qt.callLater(function() {
      titleField.forceActiveFocus()
    })
  }

  function openForEdit(bookmark) {
    if (!bookmark)
      return

    root.editing = true
    root.fromClipboard = false
    root.bookmarkId = String(bookmark.id || "")
    root.validationError = ""
    titleField.text = String(bookmark.title || "")
    urlField.text = String(bookmark.url || "")
    tagsField.text = Array.isArray(bookmark.tags)
      ? bookmark.tags.join(", ")
      : ""
    keywordField.text = String(bookmark.keyword || "")
    root.initialUrl = String(bookmark.url || "")
    root.pendingFavicon = String(bookmark.favicon || "")
    root.opened = true

    Qt.callLater(function() {
      titleField.forceActiveFocus()
      titleField.selectAll()
    })
  }

  function close() {
    root.opened = false
    root.editing = false
    root.fromClipboard = false
    root.bookmarkId = ""
    root.validationError = ""
    root.initialUrl = ""
    root.pendingFavicon = ""
    titleField.text = ""
    urlField.text = ""
    tagsField.text = ""
    keywordField.text = ""
  }

  function refocus() {
    Qt.callLater(function() {
      if (root.opened)
        titleField.forceActiveFocus()
    })
  }

  function cancel() {
    root.close()
    root.canceled()
  }

  function submit() {
    var title = titleField.text.trim()
    var url = urlField.text.trim()

    if (!url) {
      root.validationError = "Enter a URL"
      urlField.forceActiveFocus()
      return
    }

    if (/\s/.test(url) || (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(url) && !/^https?:\/\//i.test(url))) {
      root.validationError = "Use an HTTP(S) URL"
      urlField.forceActiveFocus()
      return
    }

    var normalizedUrl = url
    if (typeof root.urlValidator === "function") {
      normalizedUrl = root.urlValidator(url)
      if (!normalizedUrl) {
        root.validationError = "Enter a valid HTTP(S) URL"
        urlField.forceActiveFocus()
        return
      }
    }

    if (/\s/.test(keywordField.text.trim())) {
      root.validationError = "Keyword cannot contain spaces"
      keywordField.forceActiveFocus()
      return
    }

    root.validationError = ""
    root.submitted(
      root.bookmarkId,
      title,
      url,
      tagsField.text,
      keywordField.text,
      normalizedUrl === root.initialUrl ? root.pendingFavicon : ""
    )
  }

  visible: opened
  enabled: opened

  Keys.priority: Keys.BeforeItem

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      root.cancel()
      event.accepted = true
    } else if (
      (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
      && event.modifiers === Qt.ControlModifier
    ) {
      root.submit()
      event.accepted = true
    }
  }

  Rectangle {
    anchors.fill: parent
    color: Commons.Color.menu.background

    MouseArea {
      anchors.fill: parent
      onClicked: {}
    }
  }

  Column {
    anchors.fill: parent
    spacing: Commons.Style.spacing.md

    Item {
      width: parent.width
      height: Commons.Style.space(42)

      Text {
        id: editorHeading

        anchors.left: parent.left
        anchors.right: webDetailsControl.left
        anchors.rightMargin: Commons.Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter

        text: root.editing ? "Edit bookmark" : "Add bookmark"
        color: Commons.Color.menu.text
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.title
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }

      Text {
        id: webDetailsControl

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        text: (root.webDetailsEnabled ? "Paste details: On" : "Paste details: Off")
          + " · Change"
        color: Commons.Color.menu.text
        opacity: root.webDetailsEnabled ? 0.72 : 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Commons.Style.spacing.sm
          cursorShape: Qt.PointingHandCursor
          onClicked: root.webDetailsSettingsRequested()
        }
      }
    }

    Column {
      width: parent.width
      spacing: Commons.Style.spacing.xs

      Text {
        text: "Title (optional)"
        color: Commons.Color.menu.text
        opacity: 0.72
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
      }

      Ui.TextField {
        id: titleField

        width: parent.width
        placeholderText: "Bookmark name"
        foreground: Commons.Color.menu.text
        accent: Commons.Color.menu.selectedText

        onTextChanged: root.validationError = ""
        onAccepted: urlField.forceActiveFocus()
      }
    }

    Column {
      width: parent.width
      spacing: Commons.Style.spacing.xs

      Text {
        text: "URL"
        color: Commons.Color.menu.text
        opacity: 0.72
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
      }

      Ui.TextField {
        id: urlField

        width: parent.width
        placeholderText: "https://example.com"
        foreground: Commons.Color.menu.text
        accent: Commons.Color.menu.selectedText

        onTextChanged: root.validationError = ""
        onAccepted: tagsField.forceActiveFocus()
      }
    }

    Column {
      width: parent.width
      spacing: Commons.Style.spacing.xs

      Text {
        text: "Tags"
        color: Commons.Color.menu.text
        opacity: 0.72
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
      }

      Ui.TextField {
        id: tagsField

        width: parent.width
        placeholderText: "tag-one, tag-two"
        foreground: Commons.Color.menu.text
        accent: Commons.Color.menu.selectedText

        onTextChanged: root.validationError = ""
        onAccepted: keywordField.forceActiveFocus()
      }
    }

    Column {
      width: parent.width
      spacing: Commons.Style.spacing.xs

      Text {
        text: "Keyword (optional)"
        color: Commons.Color.menu.text
        opacity: 0.72
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
      }

      Ui.TextField {
        id: keywordField

        width: parent.width
        placeholderText: "alias"
        foreground: Commons.Color.menu.text
        accent: Commons.Color.menu.selectedText

        onTextChanged: root.validationError = ""
        onAccepted: root.submit()
      }
    }

    Item {
      width: parent.width
      height: Commons.Style.space(32)

      Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        text: root.validationError
        textFormat: Text.PlainText
        visible: text !== ""
        color: Commons.Color.urgent
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
        elide: Text.ElideRight
      }
    }

    Item {
      width: parent.width
      height: Commons.Style.space(42)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        text: root.fromClipboard && !root.webDetailsEnabled
          ? "Web details off · add anything you want"
          : "Enter Next field    Ctrl+Enter Save"
        color: Commons.Color.menu.text
        opacity: 0.48
        font.family: Commons.Style.font.menuFamily
        font.pixelSize: Commons.Style.font.caption
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Commons.Style.spacing.sm

        Ui.Button {
          width: Commons.Style.space(88)
          height: Commons.Style.space(34)
          text: "Cancel"
          bordered: true
          focusable: true
          foreground: Commons.Color.menu.text
          accent: Commons.Color.menu.selectedText

          onClicked: root.cancel()
        }

        Ui.Button {
          width: Commons.Style.space(88)
          height: Commons.Style.space(34)
          text: root.editing ? "Save" : "Add"
          bordered: true
          selected: true
          focusable: true
          enabled: root.canSubmit
          opacity: enabled ? 1 : 0.42
          foreground: Commons.Color.menu.text
          accent: Commons.Color.menu.selectedText

          onClicked: root.submit()
        }
      }
    }
  }
}
