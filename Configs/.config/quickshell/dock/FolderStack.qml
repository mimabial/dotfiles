pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Qt.labs.folderlistmodel
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel

BorderSurface {
  id: stack
  required property var dock

  readonly property bool hovered: stackHover.hovered
  readonly property string path: stack.dock.expandHome(stack.dock.activeStackFolder)
  property bool keyboard: false

  readonly property int bodyRows: 12
  readonly property real rowStep: Math.max(28, Commons.Style.space(28)) + listView.spacing
  readonly property real rowWidth: stack.dock.menuContentWidth(listView.contentItem)

  color: Commons.Util.alpha(Commons.Style.popupTinted(Commons.Color.menu.background), Commons.Style.popupSurfaceOpacity)
  borderSpec: Commons.Border.surfaceSpec("menu", "border",
    Commons.Util.alpha(Commons.Style.popupBorder(Commons.Color.menu.border), Commons.Style.popupBorderOpacity), 1)
  radius: Commons.Style.cornerRadius
  padding: Commons.Style.space(4)
  width: stack.rowWidth + contentLeftInset + contentRightInset
  height: column.implicitHeight + contentTopInset + contentBottomInset

  NumberAnimation on opacity { from: 0; to: 1; duration: 120 }

  HoverHandler { id: stackHover }

  FolderListModel {
    id: files
    folder: DockModel.fileUrl(stack.path)
    sortField: FolderListModel.Time
  }

  function open(path, isDir) {
    if (isDir) stack.dock.openInFileManager(path)
    else Commons.Util.execDetached("uwsm-app -- xdg-open " + Commons.Util.shellQuote(path))
    stack.dock.closeFolderStack()
  }

  function handleKey(event) {
    var key = event.key
    if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space || key === Qt.Key_Right) {
      const index = listView.currentIndex
      if (index < 0 || index >= listView.count) return false
      stack.open(files.get(index, "filePath"), files.get(index, "fileIsDir"))
      return true
    }
    if (!stack.keyboard) {
      stack.keyboard = [Qt.Key_Down, Qt.Key_Up, Qt.Key_Tab, Qt.Key_Backtab].indexOf(key) >= 0
      return stack.keyboard
    }
    if (key === Qt.Key_Down || key === Qt.Key_Tab) listView.incrementCurrentIndex()
    else if (key === Qt.Key_Up || key === Qt.Key_Backtab) listView.decrementCurrentIndex()
    else return false
    listView.positionViewAtIndex(listView.currentIndex, ListView.Contain)
    return true
  }

  Column {
    id: column
    x: stack.contentLeftInset
    y: stack.contentTopInset
    width: stack.rowWidth
    spacing: Commons.Style.space(2)

    DockMenuRow {
      menuWidth: stack.rowWidth
      isHeader: true
      text: stack.dock.activeStackName + (listView.count > 0 ? " (" + listView.count + ")" : "")
    }

    Item {
      width: stack.rowWidth
      height: listView.count === 0 ? emptyText.implicitHeight
        : Math.min(listView.count * stack.rowStep - listView.spacing, stack.bodyRows * stack.rowStep)

      Text {
        id: emptyText
        visible: files.status === FolderListModel.Ready && listView.count === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "Folder is empty"
        textFormat: Text.PlainText
        color: Commons.Util.alpha(Commons.Color.menu.text, 0.45)
        font.family: Commons.Style.font.family
        font.pixelSize: Commons.Style.font.body
        padding: Commons.Style.space(8)
      }

      ListView {
        id: listView
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        spacing: Commons.Style.space(2)
        model: files
        ScrollBar.vertical: PanelScrollBar { policy: listView.contentHeight > listView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
        delegate: FileStackRow {
          required property string fileName
          required property string filePath
          required property string fileSuffix
          required property bool fileIsDir
          required property real fileSize
          dock: stack.dock
          menuWidth: stack.rowWidth
          name: fileName
          path: filePath
          icon: DockModel.fileIcon(fileSuffix, fileIsDir)
          subtext: fileIsDir ? "" : DockModel.sizeLabel(fileSize)
          cursored: stack.keyboard && ListView.isCurrentItem
          onTriggered: stack.open(filePath, fileIsDir)
        }
      }
    }

    DockMenuDivider { menuWidth: stack.rowWidth }

    DockMenuRow {
      menuWidth: stack.rowWidth
      text: "Open in File Manager"
      onTriggered: {
        stack.dock.openInFileManager(stack.path)
        stack.dock.closeFolderStack()
      }
    }

    Text {
      width: stack.rowWidth
      text: "↑↓ Move  Enter Open  ←/Esc Close"
      wrapMode: Text.NoWrap
      horizontalAlignment: Text.AlignHCenter
      fontSizeMode: Text.HorizontalFit
      minimumPixelSize: Math.max(10, Commons.Style.font.caption - 2)
      color: Commons.Util.alpha(Commons.Color.menu.text, .55)
      font.family: Commons.Style.font.family
      font.pixelSize: Commons.Style.font.caption
    }
  }
}
