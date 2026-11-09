import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui

PopupWindow {
  id: tip
  required property var dock
  required property Item target
  property real gap: Commons.Style.space(8)
  property alias padding: surface.padding
  default property alias content: holder.data

  color: "transparent"
  mask: Region {}
  implicitWidth: surface.width
  implicitHeight: surface.height

  anchor.item: tip.target
  anchor.rect.x: (tip.target.width - tip.implicitWidth) / 2
  anchor.rect.y: tip.dock.edge === "top" ? tip.target.height + tip.gap : -tip.implicitHeight - tip.gap
  anchor.rect.width: 1
  anchor.rect.height: 1

  BorderSurface {
    id: surface
    color: Commons.Util.scaleAlpha(Commons.Style.popupTinted(Commons.Color.tooltip.background), Commons.Style.popupSurfaceOpacity)
    borderSpec: Commons.Border.none()
    radius: Commons.Style.cornerRadius
    padding: Commons.Style.space(4)
    width: Math.ceil(holder.childrenRect.width + contentLeftInset + contentRightInset)
    height: Math.ceil(holder.childrenRect.height + contentTopInset + contentBottomInset)

    Item {
      id: holder
      x: surface.contentLeftInset
      y: surface.contentTopInset
    }
  }
}
