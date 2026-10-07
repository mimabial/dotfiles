pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets

Rectangle {
    id: root
    required property var shell
    property string icon: ""
    property color iconColor: shell.foreground
    property string iconSource: ""
    property real iconSize: Style.px(18)
    property string title: ""
    property string detail: ""
    property int detailAlignment: Text.AlignLeft
    property string value: ""
    property real valueWidth: 0
    property bool valueClickable: false
    property color titleColor: shell.foreground
    property color detailColor: shell.mutedText
    property color valueColor: shell.alpha(shell.foreground, .7)
    property color valueHoverColor: valueColor
    property bool active: false
    property bool hoverBorder: true
    // a row with nothing to click should not light up or take the keyboard cursor
    property bool interactive: true
    property real rightInset: 0
    // marks the row for PopupCard's keyboard cursor, and shows where it sits
    readonly property bool navigable: interactive && enabled
    readonly property bool hovered: mouse.containsMouse
    readonly property bool valueHovered: valueClickable && valueText.visible && hovered
        && mouse.mouseX >= valueText.mapToItem(root, 0, 0).x - Style.controlPaddingX / 2
    property bool cursored: false
    readonly property bool highlighted: cursored || (!shell.popupCard?.open && hovered)
    property bool selected: false
    // for rows that are a bare label, with no icon or value to align against
    property bool centerTitle: false
    // pills after the title: [{text, color}]
    property var badges: []
    signal clicked(int button)
    signal valueClicked()
    implicitHeight: Math.max(Style.popupRowHeight, Math.max(textColumn.implicitHeight, iconImage.visible ? root.iconSize : 0) + Style.controlPaddingY * 2)
    readonly property color highlight: !hoverBorder && hovered ? "transparent"
        : selected ? shell.hoverEdge(.85)
        : active ? shell.selectedEdge()
        : highlighted ? shell.hoverEdge(.85)
        : "transparent"
    color: (interactive && (highlighted || selected)) ? shell.hoverFill()
        : active ? shell.selectedFill() : "transparent"
    border.color: highlight
    radius: shell.rounding
    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }

    Row {
        anchors.fill: parent; anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX + root.rightInset
        spacing: Style.controlPaddingX
        // centred in its fixed column so the gap to the border matches the gap to the text
        IconImage { id: iconImage; visible: root.iconSource !== ""; implicitWidth: root.iconSize; implicitHeight: root.iconSize; clip: true; backer.fillMode: Image.PreserveAspectCrop; anchors.verticalCenter: parent.verticalCenter; source: root.iconSource }
        Text { id: iconText; visible: root.icon !== ""; width: Style.px(22); horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter; text: root.icon; color: root.iconColor; font.family: root.shell.fontFamily; font.pixelSize: Style.title + 3 }
        Column {
            id: textColumn
            width: parent.width - (iconText.visible ? iconText.width + parent.spacing : 0) - (iconImage.visible ? iconImage.width + parent.spacing : 0) - (valueText.visible ? valueText.width + parent.spacing : 0)
            anchors.verticalCenter: parent.verticalCenter; spacing: 1
            Row {
                width: parent.width; spacing: Style.xs
                Item {
                    id: titleClip
                    width: root.badges.length ? Math.min(titleText.implicitWidth, parent.width - badgeRow.width - parent.spacing) : parent.width
                    height: titleText.implicitHeight
                    clip: true
                    readonly property real overflow: Math.max(0, titleText.implicitWidth - width)
                    readonly property int scrollDuration: Math.max(600, overflow * 34)
                    // elide is what the row shows at rest; hovering reads the rest of it
                    readonly property bool scrolling: root.hovered && overflow > 0 && !Style.reduceMotion
                    onScrollingChanged: if (!scrolling) titleText.x = 0
                    Text {
                        id: titleText
                        width: titleClip.scrolling ? implicitWidth : titleClip.width
                        text: root.title; color: root.titleColor
                        font.family: root.shell.fontFamily; font.pixelSize: Style.subtitle; font.bold: root.active
                        elide: titleClip.scrolling ? Text.ElideNone : Text.ElideRight
                        horizontalAlignment: root.centerTitle ? Text.AlignHCenter : Text.AlignLeft
                        SequentialAnimation on x {
                            running: titleClip.scrolling
                            loops: Animation.Infinite
                            PauseAnimation { duration: 650 }
                            NumberAnimation { to: -titleClip.overflow; duration: titleClip.scrollDuration; easing.type: Easing.InOutQuad }
                            PauseAnimation { duration: 650 }
                            NumberAnimation { to: 0; duration: titleClip.scrollDuration; easing.type: Easing.InOutQuad }
                        }
                    }
                }
                Row {
                    id: badgeRow
                    anchors.verticalCenter: parent.verticalCenter; spacing: Style.xs
                    Repeater {
                        model: root.badges
                        Rectangle {
                            id: badgeTag
                            required property var modelData
                            width: badgeText.implicitWidth + Style.px(10); height: badgeText.implicitHeight + Style.px(3)
                            radius: root.shell.rounding; color: root.shell.alpha(badgeTag.modelData.color, .14)
                            Text { id: badgeText; anchors.centerIn: parent; text: badgeTag.modelData.text; color: badgeTag.modelData.color; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true }
                        }
                    }
                }
            }
            Text { visible: text !== ""; width: parent.width; text: root.detail; color: root.detailColor; horizontalAlignment: root.detailAlignment; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight }
        }
        Text { id: valueText; visible: text !== ""; width: root.valueWidth > 0 ? root.valueWidth : implicitWidth; anchors.verticalCenter: parent.verticalCenter; text: root.value; color: root.valueHovered ? root.valueHoverColor : root.valueColor; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.enabled && root.interactive
        hoverEnabled: root.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => {
            if (event.button === Qt.LeftButton && root.valueHovered) root.valueClicked()
            else root.clicked(event.button)
        }
    }
    PopupPointer { shell: root.shell; row: root }
}
