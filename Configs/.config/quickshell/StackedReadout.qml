import QtQuick

// The sysinfo scripts emit "<icon><br>value". As one Text the space between the
// lines is font metrics; two Texts make it an explicit number.
ScriptButton {
    id: root
    property real gap: 0
    // a larger icon reserves ascent above its ink; pinning its line box stops
    // that headroom scaling with the span's point size
    property real iconLine: 0
    property real iconPadRight: 0
    property real tailGap: 0
    readonly property var halves: {
        const parts = String(root.rendered).split(/<br\s*\/?>|\r\n?|\n/i)
        return {
            icon: (parts[0] || "").trim(),
            value: (parts[1] || "").trim(),
            tail: (parts[2] || "").trim()
        }
    }
    // the inherited single-line label stands down; the column below draws instead
    text: ""
    readonly property bool shown: rendered !== ""
    visible: shown
    implicitWidth: Math.max(iconLabel.implicitWidth, valueLabel.implicitWidth, tailLabel.implicitWidth) + spanX
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
            textFormat: Text.RichText
            lineHeightMode: root.iconLine > 0 ? Text.FixedHeight : Text.ProportionalHeight
            lineHeight: root.iconLine > 0 ? root.iconLine : 1
            color: root.textColor
            font.family: root.shell.fontFamily
            font.pixelSize: root.fontSize
        }
        Text {
            id: valueLabel
            width: parent.width
            horizontalAlignment: root.align
            visible: text !== ""
            text: root.halves.value
            textFormat: Text.RichText
            color: root.textColor
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
            textFormat: Text.RichText
            color: root.textColor
            font.family: root.shell.fontFamily
            font.pixelSize: root.fontSize
            font.weight: root.fontWeight
        }
    }
}
