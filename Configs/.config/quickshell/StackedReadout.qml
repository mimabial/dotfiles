import QtQuick

// The sysinfo scripts emit "<icon><br>value". As one Text the space between the
// lines is font metrics; two Texts make it an explicit number.
ScriptButton {
    id: root
    // the stack is for the vertical bars; a horizontal one sets this false and
    // gets the same two parts side by side
    property bool vertical: true
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
        // the scripts size their icon in the markup, which reads as a deliberate
        // step up over the value below it but as a mismatch beside it — and it
        // would drive the bar's height. Drop the size, keep the colour a script
        // uses to signal temperature, and let iconSize rule.
        const icon = root.vertical ? parts[0] || ""
            : String(parts[0] || "").replace(/font-size:[^;']*;?/g, "")
        // the scripts pad a line's edge to sit its digits under the icon, so the
        // parts are passed through whole; plain text keeps those spaces as typed
        return { icon: icon, value: parts[1] || "", tail: parts[2] || "" }
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
        const value = valueLabel.implicitWidth - root.valuePadLeft
        if (root.vertical) {
            root.spanWidth = Math.max(iconLabel.implicitWidth, value, tailLabel.implicitWidth)
            return
        }
        const drawn = [iconLabel.implicitWidth, value, tailLabel.implicitWidth].filter(width => width > 0)
        root.spanWidth = drawn.reduce((total, width) => total + width, 0) + root.gap * Math.max(0, drawn.length - 1)
    }
    onHalvesChanged: Qt.callLater(root.remeasure)
    onVerticalChanged: Qt.callLater(root.remeasure)
    onFontSizeChanged: Qt.callLater(root.remeasure)
    onIconSizeChanged: Qt.callLater(root.remeasure)
    onGapChanged: Qt.callLater(root.remeasure)
    onIconLineChanged: Qt.callLater(root.remeasure)
    Component.onCompleted: root.remeasure()
    implicitWidth: root.spanWidth + spanX
    implicitHeight: stack.implicitHeight + spanY

    Grid {
        id: stack
        // one column stacks, three put the parts in a single row; either way the
        // children stay in script order
        columns: root.vertical ? 1 : 3
        verticalItemAlignment: Grid.AlignVCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: root.box.margin[3] + root.box.border + root.box.padding[3]
        anchors.rightMargin: root.box.margin[1] + root.box.border + root.box.padding[1]
        spacing: root.gap
        Text {
            id: iconLabel
            width: root.vertical ? parent.width : implicitWidth
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
            width: root.vertical ? parent.width : implicitWidth
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
            width: root.vertical ? parent.width : implicitWidth
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
