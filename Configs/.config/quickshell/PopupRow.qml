pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets

Rectangle {
    id: root
    required property var shell
    property string icon: ""
    property color iconColor: shell.foreground
    property string iconSource: ""
    property string title: ""
    property string detail: ""
    property string value: ""
    property real valueWidth: 0
    property color titleColor: shell.foreground
    property color detailColor: shell.alpha(shell.foreground, .55)
    property color valueColor: shell.alpha(shell.foreground, .7)
    property bool active: false
    // a row with nothing to click should not light up or take the keyboard cursor
    property bool interactive: true
    property real rightInset: 0
    // marks the row for PopupCard's keyboard cursor, and shows where it sits
    readonly property bool navigable: interactive
    readonly property bool hovered: mouse.containsMouse
    property bool cursored: false
    property bool selected: false
    // for rows that are a bare label, with no icon or value to align against
    property bool centerTitle: false
    // pills after the title: [{text, color}]
    property var badges: []
    signal clicked(int button)
    implicitHeight: Math.max(Style.popupRowHeight, textColumn.implicitHeight + Style.controlPaddingY * 2)
    readonly property color highlight: selected ? shell.hoverEdge(.85)
        : active ? shell.alpha(shell.role("act_br", shell.accent), .5)
        : cursored ? shell.hoverEdge(.85)
        : (interactive && mouse.containsMouse) ? shell.hoverEdge(.6)
        : "transparent"
    color: (interactive && (mouse.containsMouse || cursored || selected)) ? shell.hoverFill()
        : active ? shell.alpha(shell.role("act_bg", shell.accent), .2) : "transparent"
    border.color: highlight
    radius: shell.rounding
    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }

    Row {
        anchors.fill: parent; anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX + root.rightInset
        spacing: Style.controlPaddingX
        // centred in its fixed column so the gap to the border matches the gap to the text
        IconImage { id: iconImage; visible: root.iconSource !== ""; implicitWidth: Style.px(18); implicitHeight: Style.px(18); anchors.verticalCenter: parent.verticalCenter; source: root.iconSource }
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
                    readonly property bool scrolling: root.hovered && overflow > 0
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
            Text { visible: text !== ""; width: parent.width; text: root.detail; color: root.detailColor; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; elide: Text.ElideRight }
        }
        Text { id: valueText; visible: text !== ""; width: root.valueWidth > 0 ? root.valueWidth : implicitWidth; anchors.verticalCenter: parent.verticalCenter; text: root.value; color: root.valueColor; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
    }
    MouseArea { id: mouse; anchors.fill: parent; enabled: root.enabled && root.interactive; hoverEnabled: root.interactive; acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton; onClicked: event => root.clicked(event.button) }
}
