import QtQuick

// Providers use "<icon><br>value"; separate labels keep line spacing deterministic.
ScriptButton {
    id: root
    property bool vertical: true
    property real gap: box.gap || 0
    property real iconLineHeight: box.iconLine || 0
    property real iconRightPadding: box.iconPadRight || 0
    property real valueAlignmentOffset: box.valuePadLeft || 0
    property real tailTopPadding: 0
    readonly property real iconSize: box.iconSize !== undefined && box.fontSize
        ? root.fontSize * box.iconSize / box.fontSize : root.fontSize
    readonly property var readoutParts: {
        const parts = String(root.rendered).split(/<br\s*\/?>|\r\n?|\n/i)
        const icon = root.vertical ? parts[0] || ""
            : String(parts[0] || "").replace(/font-size:[^;']*;?/g, "")
        return { icon: icon, value: parts[1] || "", tail: parts[2] || "" }
    }
    text: ""
    readonly property bool shown: rendered !== ""
    visible: shown
    // Rich text re-reports implicitWidth whenever its document is re-parsed, and
    // a hover recolour does that: binding the size to it live would resize the
    // button mid-hover, reflow the row and drop the pointer. Measure per text.
    property real measuredContentWidth: 0
    function updateMeasuredWidth() {
        const value = valueLabel.implicitWidth - root.valueAlignmentOffset
        if (root.vertical) {
            root.measuredContentWidth = Math.max(iconLabel.implicitWidth, value, tailLabel.implicitWidth)
            return
        }
        const visiblePartWidths = [iconLabel.implicitWidth, value, tailLabel.implicitWidth].filter(width => width > 0)
        root.measuredContentWidth = visiblePartWidths.reduce((total, width) => total + width, 0)
            + root.gap * Math.max(0, visiblePartWidths.length - 1)
    }
    onReadoutPartsChanged: Qt.callLater(root.updateMeasuredWidth)
    onVerticalChanged: Qt.callLater(root.updateMeasuredWidth)
    onFontSizeChanged: Qt.callLater(root.updateMeasuredWidth)
    onIconSizeChanged: Qt.callLater(root.updateMeasuredWidth)
    onGapChanged: Qt.callLater(root.updateMeasuredWidth)
    onIconLineHeightChanged: Qt.callLater(root.updateMeasuredWidth)
    Component.onCompleted: root.updateMeasuredWidth()
    implicitWidth: root.measuredContentWidth + horizontalInsets
    implicitHeight: readoutLayout.implicitHeight + verticalInsets

    Grid {
        id: readoutLayout
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
            horizontalAlignment: root.textAlignment
            rightPadding: root.iconRightPadding
            visible: text !== ""
            text: root.readoutParts.icon
            textFormat: root.markup ? Text.RichText : Text.PlainText
            lineHeightMode: root.iconLineHeight > 0 ? Text.FixedHeight : Text.ProportionalHeight
            lineHeight: root.iconLineHeight > 0 ? Style.fontPx(root.iconLineHeight) : 1
            color: root.interactiveColor("content", root.textColor)
            font.family: root.shell.fontFamily
            font.pixelSize: root.iconSize
        }
        Text {
            id: valueLabel
            width: root.vertical ? parent.width : implicitWidth
            horizontalAlignment: root.textAlignment
            leftPadding: root.valueAlignmentOffset
            visible: text !== ""
            text: root.readoutParts.value
            textFormat: root.markup ? Text.RichText : Text.PlainText
            color: root.interactiveColor("content", root.textColor)
            font.family: root.shell.fontFamily
            font.pixelSize: root.fontSize
            font.weight: root.fontWeight
        }
        Text {
            id: tailLabel
            width: root.vertical ? parent.width : implicitWidth
            horizontalAlignment: root.textAlignment
            topPadding: root.tailTopPadding
            visible: text !== ""
            text: root.readoutParts.tail
            textFormat: root.markup ? Text.RichText : Text.PlainText
            color: root.interactiveColor("content", root.textColor)
            font.family: root.shell.fontFamily
            font.pixelSize: root.fontSize
            font.weight: root.fontWeight
        }
    }
}
