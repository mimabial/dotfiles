pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var shell
    // "compact" is the remaining-time countdown, "mpris" the transport controls.
    property string appearance: "compact"
    property bool popupEnabled: true
    property bool vertical: false
    property int albumArtSize: 18
    property int maxLabelWidth: 300
    property bool fillAvailableWidth: false
    property bool showControls: true
    property bool controlsRight: false
    property bool showArtist: true
    property bool randomizeProgressShape: false
    // with no player the module collapses to nothing; showWhenIdle keeps a
    // placeholder in the bar to open the popup from
    property bool showWhenIdle: false
    property string idleIcon: "\uf001"
    readonly property bool mprisAppearance: appearance === "mpris"
    readonly property var player: Media.player
    readonly property Item compactItem: compactLoader.item as Item
    readonly property bool hasPlayer: player !== null
    // the placeholder is a plain glyph, so the transport row only stands in for a live player
    readonly property bool mprisView: mprisAppearance && hasPlayer
    readonly property bool shown: hasPlayer || showWhenIdle
    readonly property int artSize: Math.max(Style.px(12), Style.px(albumArtSize))
    readonly property int fixedWidth: (showControls ? transport.implicitWidth + contents.spacing : 0)
        + artSize + metadata.spacing + Style.px(12)
    readonly property string displayText: showArtist && Media.artist && Media.title
        ? Media.artist + " — " + Media.title : Media.title || Media.artist

    visible: shown
    implicitWidth: !shown ? 0 : mprisView
        ? (vertical ? artSize : fillAvailableWidth ? fixedWidth : contents.implicitWidth + Style.px(12))
        : root.compactItem ? root.compactItem.implicitWidth : 0
    implicitHeight: !shown ? 0 : mprisView
        ? Math.max(artSize, contents.implicitHeight)
        : root.compactItem ? root.compactItem.implicitHeight : 0

    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    function wheel(delta) { if (delta > 0) Media.previous(); else if (delta < 0) Media.next() }
    function metadataClick(button) {
        if (button === Qt.MiddleButton) Media.previous()
        else if (button === Qt.RightButton) Media.playPause()
        else shell.togglePopup("media")
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: event => root.metadataClick(event.button)
        onWheel: event => root.wheel(event.angleDelta.y)
    }

    Loader {
        id: compactLoader
        anchors.verticalCenter: parent.verticalCenter
        width: root.compactItem ? root.compactItem.implicitWidth : 0
        // swapping left/horizontalCenter anchors after creation briefly sets both, which pins width to 0
        x: root.fillAvailableWidth ? 0 : (root.width - width) / 2
        active: !root.mprisView
        sourceComponent: compactView
    }
    Component {
        id: compactView
        BarButton {
            shell: root.shell
            opensPopup: true
            css: "mediaplayer"
            textColor: shell.alpha(shell.role("act_fg", shell.foreground), .7)
            text: root.player ? Media.icon(root.player) + "  " + Media.remaining(root.player)
                : root.showWhenIdle ? root.idleIcon : ""
            onClicked: button => button === Qt.RightButton ? Media.playPause()
                : button === Qt.MiddleButton ? Media.next() : root.shell.togglePopup("media")
            onWheeled: delta => root.wheel(delta)
        }
    }

    MediaPopup { anchorItem: root.fillAvailableWidth ? (root.mprisView ? contents : compactLoader) : root; shell: root.shell; popupEnabled: root.popupEnabled; randomizeProgressShape: root.randomizeProgressShape }

    Row {
        id: contents
        anchors.verticalCenter: parent.verticalCenter
        x: root.fillAvailableWidth ? 0 : (root.width - width) / 2
        spacing: Style.px(4)
        layoutDirection: root.controlsRight ? Qt.RightToLeft : Qt.LeftToRight
        visible: root.mprisView

        Row {
            id: transport
            spacing: Style.px(4); layoutDirection: Qt.LeftToRight; visible: root.showControls
            TransportButton { iconText: "󰒮"; enabled: !!(root.player && root.player.canGoPrevious); visible: !root.vertical; onTriggered: Media.previous() }
            TransportButton {
                iconText: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                enabled: !!(root.player && (root.player.canPlay || root.player.canPause || root.player.canTogglePlaying))
                onTriggered: Media.playPause()
            }
            TransportButton { iconText: "󰒭"; enabled: !!(root.player && root.player.canGoNext); visible: !root.vertical; onTriggered: Media.next() }
        }

        Row {
          id: metadata
          spacing: Style.px(4); layoutDirection: Qt.LeftToRight; visible: !root.vertical
          Item {
            id: artContainer
            width: root.artSize; height: root.artSize
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical

            Rectangle { anchors.fill: parent; radius: Style.px(3); color: root.shell.alpha(root.shell.foreground, .08) }
            Image {
                id: cover
                anchors.fill: parent; anchors.margins: 1
                source: Media.artUrl
                sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; cache: true; smooth: true
            }
            Text {
                anchors.centerIn: parent
                visible: Media.artUrl === "" || cover.status === Image.Error
                text: "󰝚"; color: root.shell.foreground
                font.family: root.shell.fontFamily; font.pixelSize: Style.body
            }
            MouseArea {
                anchors.fill: parent; hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: event => root.metadataClick(event.button)
                onWheel: event => root.wheel(event.angleDelta.y)
            }
        }

          Item {
            id: labelClip
            width: Math.min(label.implicitWidth, root.fillAvailableWidth
                ? Math.max(0, root.width - root.fixedWidth) : Style.px(root.maxLabelWidth))
            height: Math.max(root.artSize, label.implicitHeight)
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical && root.displayText !== ""
            clip: true

            Text {
                id: label
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: root.displayText; color: root.shell.foreground
                opacity: root.player && root.player.isPlaying ? .9 : .5
                font.family: root.shell.fontFamily; font.pixelSize: Style.body
                elide: Text.ElideRight
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }
            MouseArea {
                anchors.fill: parent; hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: event => root.metadataClick(event.button)
                onWheel: event => root.wheel(event.angleDelta.y)
            }
          }
        }
    }

    component TransportButton: Item {
        id: button
        required property string iconText
        signal triggered()
        implicitWidth: Style.px(20)
        implicitHeight: root.artSize
        opacity: enabled ? 1 : .32

        Behavior on opacity { NumberAnimation { duration: 120 } }
        Rectangle {
            anchors.fill: parent; radius: Style.sm
            color: mouse.containsMouse && button.enabled ? root.shell.hoverFill() : "transparent"
            Behavior on color { ColorAnimation { duration: Style.hoverDuration; easing.type: Easing.OutCubic } }
        }
        Text {
            anchors.centerIn: parent; text: button.iconText; color: root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Style.body
        }
        MouseArea {
            id: mouse
            anchors.fill: parent; enabled: button.enabled; hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: button.triggered()
            onWheel: event => root.wheel(event.angleDelta.y)
        }
    }
}
