import QtQuick

// The sysinfo scripts emit "<icon><br>value". As one Text the space between the
// lines is font metrics; two Texts make it an explicit number.
ScriptButton {
    id: root
    property real gap: box.gap || 0
    // a larger icon reserves ascent above its ink; pinning its line box stops
    // that headroom scaling with the span's point size
    property real iconLine: box.iconLine || 0
    property real iconPadRight: box.iconPadRight || 0
    // a trailing glyph the eye discounts (a degree sign) pulls the digits left of
    // centre; padding the value's leading edge puts them back under the icon
    property real valuePadLeft: box.valuePadLeft || 0
    property real tailGap: 0
    // "iconSize" in the style file sizes the icon alone; it rides the same scale
    // as fontSize, so a text-size change moves both together
    readonly property real iconSize: box.iconSize !== undefined && box.fontSize
        ? root.fontSize * box.iconSize / box.fontSize : root.fontSize
    readonly property var halves: {
        const parts = String(root.rendered).split(/<br\s*\/?>|\r\n?|\n/i)
        // the scripts pad a line's edge to sit its digits under the icon, so the
        // parts are passed through whole; plain text keeps those spaces as typed
        return { icon: parts[0] || "", value: parts[1] || "", tail: parts[2] || "" }
    }
    // the inherited single-line label stands down; the column below draws instead
    text: ""
    readonly property bool shown: rendered !== ""
    visible: shown
    // Rich text re-reports implicitWidth whenever its document is re-parsed, and
    // a hover recolour does that: binding the size to it live would resize the
    // button mid-hover, reflow the row and drop the pointer. Measure per text.
    property real spanWidth: 0
    function remeasure() {
        // the value's leading pad only nudges the line inside the box; letting it
        // count here would widen the button, and with it the whole bar
        root.spanWidth = Math.max(iconLabel.implicitWidth, valueLabel.implicitWidth - root.valuePadLeft, tailLabel.implicitWidth)
    }
    onHalvesChanged: Qt.callLater(root.remeasure)
    onFontSizeChanged: Qt.callLater(root.remeasure)
    onIconSizeChanged: Qt.callLater(root.remeasure)
    onGapChanged: Qt.callLater(root.remeasure)
    onIconLineChanged: Qt.callLater(root.remeasure)
    Component.onCompleted: root.remeasure()
    implicitWidth: root.spanWidth + spanX
    implicitHeight: stack.implicitHeight + spanY

    Column {
        id: stack
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: root.box.margin[3] + root.box.border + root.box.padding[3]
        anchors.rightMargin: root.box.margin[1] + root.box.border + root.box.padding[1]
        spacing: root.gap
        Text {
            id: iconLabel
            width: parent.width
            horizontalAlignment: root.align
            rightPadding: root.iconPadRight
            visible: text !== ""
            text: root.halves.icon
            textFormat: root.markup ? Text.RichText : Text.PlainText
            lineHeightMode: root.iconLine > 0 ? Text.FixedHeight : Text.ProportionalHeight
            lineHeight: root.iconLine > 0 ? Style.fontPx(root.iconLine) : 1
            color: root.hoverPaint("content", root.textColor)
            font.family: root.shell.fontFamily
            font.pixelSize: root.iconSize
        }
        Text {
            id: valueLabel
            width: parent.width
            horizontalAlignment: root.align
            leftPadding: root.valuePadLeft
            visible: text !== ""
            text: root.halves.value
            textFormat: root.markup ? Text.RichText : Text.PlainText
            color: root.hoverPaint("content", root.textColor)
            font.family: root.shell.fontFamily
            font.pixelSize: root.fontSize
            font.weight: root.fontWeight
        }
        Text {
            id: tailLabel
            width: parent.width
            horizontalAlignment: root.align
            topPadding: root.tailGap
            visible: text !== ""
            text: root.halves.tail
            textFormat: root.markup ? Text.RichText : Text.PlainText
            color: root.hoverPaint("content", root.textColor)
            font.family: root.shell.fontFamily
            font.pixelSize: root.fontSize
            font.weight: root.fontWeight
        }
    }
}
