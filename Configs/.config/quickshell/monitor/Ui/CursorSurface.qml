import QtQuick
import qs.Commons as Commons

// Derive visuals from `hasCursor`/`current`, never a local `containsMouse`, so
// keyboard and pointer navigation cannot paint two highlights.
BorderSurface {
  id: root

  property bool hasCursor: false
  property bool current: false
  property bool outline: false
  property bool bordered: false

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color fill: Commons.Style.hoverFillFor(foreground, accent)
  property color currentFill: Commons.Style.selectedFillFor(foreground, accent)

  radius: Commons.Style.cornerRadius

  color: hasCursor ? fill : (current ? currentFill : "transparent")
  borderSpec: root.hasCursor
    ? Commons.Border.controlSpec("hover-cursor", root.foreground, root.accent)
    : (root.current
      ? Commons.Border.controlSpec("selected", root.foreground, root.accent)
      : (root.bordered
        ? Commons.Border.controlSpec("normal", root.foreground, root.accent)
        : Commons.Border.none()))

  Behavior on color {
    ColorAnimation { duration: 60 }
  }
}
