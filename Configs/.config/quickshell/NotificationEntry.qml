pragma ComponentBehavior: Bound
import QtQuick

// One archived notification. Given explicit properties rather than a modelData
// of its own, so the popup owns the shape of an entry and this owns its look.
Rectangle {
    id: root
    required property var shell
    property string app: ""
    property string summary: ""
    property string body: ""
    property string iconPath: ""
    property string previewPath: ""
    property string urgency: "NORMAL"
    property double timestamp: 0
    property double now: 0
    property bool unread: false
    property bool showBody: true
    property bool showPreview: true

    // keeps PopupCard's up/down cursor working over these rows
    readonly property bool navigable: true
    property bool cursored: false
    readonly property bool hovered: rowArea.containsMouse
    signal clicked(int button)
    signal removeRequested

    readonly property bool critical: urgency === "CRITICAL"
    readonly property bool hasIcon: iconPath !== "" && iconImage.status === Image.Ready
    readonly property bool hasPreview: showPreview && previewPath !== ""
        && previewImage.status === Image.Ready
    // an app that shipped no icon still gets a slot, so the left edge of the
    // list does not move from row to row
    readonly property string initial: app === "" ? "?" : app.charAt(0).toUpperCase()

    readonly property string when: {
        if (timestamp <= 0) return ""
        // the day this landed on is the section header's job, so a row only
        // ever has to say where in that day it was
        const seconds = Math.max(0, Math.floor((now - timestamp) / 1000))
        if (seconds < 60) return "now"
        if (seconds < 3600) return Math.floor(seconds / 60) + "m"
        return Qt.formatDateTime(new Date(timestamp), "HH:mm")
    }

    // paths reach QML as plain absolute paths; a space or a '#' in one would
    // otherwise truncate the URL
    function fileUrl(path) {
        if (!path) return ""
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
    }

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: layout.implicitHeight + Style.controlPaddingY * 2
    radius: root.shell.rounding
    color: root.cursored || rowArea.containsMouse ? root.shell.hoverFill(2) : "transparent"
    border.width: root.cursored ? 1 : 0
    border.color: root.shell.hoverEdge(1)
    Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => event.button === Qt.RightButton
            ? root.removeRequested()
            : root.clicked(event.button)
    }

    Row {
        id: layout
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.controlPaddingX

        Item {
            id: iconSlot
            width: Style.px(22); height: Style.px(22)
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                anchors.fill: parent
                visible: !root.hasIcon
                radius: width / 2
                color: root.shell.alpha(root.shell.foreground, .12)
                Text {
                    anchors.centerIn: parent
                    text: root.initial
                    color: root.shell.alpha(root.shell.foreground, .7)
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.caption
                    font.bold: true
                }
            }
            Image {
                id: iconImage
                anchors.fill: parent
                source: root.fileUrl(root.iconPath)
                fillMode: Image.PreserveAspectFit
                sourceSize.width: width * 2; sourceSize.height: height * 2
                asynchronous: true
                visible: root.hasIcon
            }
        }

        Column {
            width: parent.width - iconSlot.width - stamp.width - parent.spacing * 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: root.summary !== "" ? root.summary : root.app
                elide: Text.ElideRight
                color: root.critical
                    ? root.shell.role("error", root.shell.foreground)
                    : root.shell.foreground
                font.family: root.shell.fontFamily
                font.pixelSize: Style.bodySmall
                font.bold: root.unread
            }
            Text {
                visible: root.showBody && text !== ""
                width: parent.width
                text: root.body
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily
                font.pixelSize: Style.caption
            }
            Item {
                visible: root.hasPreview
                width: parent.width
                height: visible ? Style.px(68) : 0
                Image {
                    id: previewImage
                    anchors.left: parent.left
                    anchors.top: parent.top; anchors.topMargin: Style.xs
                    width: Math.min(parent.width, Style.px(112))
                    height: Style.px(68) - Style.xs
                    source: root.showPreview ? root.fileUrl(root.previewPath) : ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: width * 2; sourceSize.height: height * 2
                    asynchronous: true
                    clip: true
                }
            }
        }

        Column {
            id: stamp
            width: Math.max(age.implicitWidth, Style.px(26))
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.xxs

            Text {
                id: age
                anchors.right: parent.right
                text: root.when
                color: root.shell.alpha(root.shell.foreground, .45)
                font.family: root.shell.fontFamily
                font.pixelSize: Style.caption
                visible: !removeArea.containsMouse && !rowArea.containsMouse
            }
            Rectangle {
                id: removeButton
                anchors.right: parent.right
                width: Style.px(20); height: Style.px(20)
                radius: root.shell.rounding
                visible: rowArea.containsMouse || removeArea.containsMouse || root.cursored
                color: removeArea.containsMouse ? root.shell.hoverFill(3) : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "\u{f0156}"
                    color: root.shell.alpha(root.shell.foreground, removeArea.containsMouse ? 1 : .6)
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.bodySmall
                }
                MouseArea {
                    id: removeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removeRequested()
                }
            }
            Rectangle {
                anchors.right: parent.right
                width: Style.px(6); height: Style.px(6)
                radius: width / 2
                visible: root.unread && !removeButton.visible
                color: root.shell.role("accent", root.shell.foreground)
            }
        }
    }
}
