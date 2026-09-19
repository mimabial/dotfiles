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
    readonly property string avatarPath: showPreview && previewPath !== ""
        ? previewPath : iconPath
    readonly property bool hasAvatar: avatarPath !== "" && avatarImage.status === Image.Ready
    readonly property string initial: app === "" ? "?" : app.charAt(0).toUpperCase()
    readonly property color sourceColor: {
        const name = app.toLowerCase()
        if (["vesktop", "discord", "webcord", "vencord"].some(part => name.includes(part)))
            return "#e0574a"
        if (["sable", "element", "cinny"].some(part => name.includes(part)))
            return "#a78bfa"
        if (name.includes("slack")) return "#4a9d7f"
        if (name.includes("telegram")) return "#5aa7d6"
        if (name.includes("signal")) return "#5b8ce0"
        if (name.includes("thunderbird")) return "#d4a35c"
        if (name.includes("spotify")) return "#6fbf73"
        return Qt.darker(shell.foreground, 1.4)
    }

    readonly property string when: {
        if (timestamp <= 0) return ""
        const seconds = Math.max(0, Math.floor((now - timestamp) / 1000))
        if (seconds < 60) return "now"
        if (seconds < 3600) return Math.floor(seconds / 60) + "m"
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h"
        if (seconds < 604800) return Math.floor(seconds / 86400) + "d"
        return Qt.formatDateTime(new Date(timestamp), "MMM d")
    }

    // paths reach QML as plain absolute paths; a space or a '#' in one would
    // otherwise truncate the URL
    function fileUrl(path) {
        if (!path) return ""
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
    }

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: content.implicitHeight + Style.controlPaddingX
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

    Item {
        id: content
        anchors.left: parent.left; anchors.right: parent.right
        anchors.leftMargin: Style.controlPaddingX; anchors.rightMargin: Style.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: textColumn.implicitHeight

        Rectangle {
            id: sourceRule
            anchors.left: parent.left
            anchors.top: parent.top; anchors.bottom: parent.bottom
            width: Style.xxs
            radius: width / 2
            color: root.sourceColor
            opacity: root.unread ? 1 : .35
        }

        Column {
            id: textColumn
            anchors.left: sourceRule.right; anchors.leftMargin: Style.controlPaddingX
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.px(1)

            Item {
                width: parent.width
                implicitHeight: Math.max(sourceLabel.implicitHeight, Style.px(13))

                Item {
                    id: avatar
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.px(13); height: Style.px(13)

                    Text {
                        anchors.centerIn: parent
                        visible: !root.hasAvatar
                        text: root.initial
                        color: root.critical
                            ? root.shell.role("error", root.shell.foreground)
                            : root.sourceColor
                        font.family: root.shell.fontFamily
                        font.pixelSize: Style.caption
                        font.bold: true
                    }
                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        visible: root.hasAvatar
                        source: root.fileUrl(root.avatarPath)
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: width * 2; sourceSize.height: height * 2
                        asynchronous: true
                        smooth: true
                    }
                }

                Text {
                    id: sourceLabel
                    anchors.left: avatar.right; anchors.leftMargin: Style.md
                    anchors.right: timeLabel.left; anchors.rightMargin: Style.lg
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.app
                    color: root.sourceColor
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.caption
                    font.bold: true
                    elide: Text.ElideRight
                }

                Text {
                    id: timeLabel
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.when
                    color: Qt.darker(root.shell.foreground, 1.5)
                    font.family: root.shell.fontFamily
                    font.pixelSize: Style.caption
                }
            }

            Text {
                visible: root.summary !== ""
                width: parent.width
                text: root.summary
                color: root.shell.foreground
                font.family: root.shell.fontFamily
                font.pixelSize: Style.body
                font.bold: root.unread
                elide: Text.ElideRight
            }

            Text {
                visible: root.showBody && root.body !== ""
                width: parent.width
                text: root.body
                textFormat: Text.PlainText
                color: Qt.darker(root.shell.foreground, 1.5)
                font.family: root.shell.fontFamily
                font.pixelSize: Style.bodySmall
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
        }
    }
}
