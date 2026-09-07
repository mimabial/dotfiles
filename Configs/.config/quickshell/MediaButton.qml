pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var shell
    // One module, two presentations: the original countdown or Omarchy MPRIS controls.
    property string appearance: "compact"
    property bool popupEnabled: true
    property bool vertical: false
    property int albumArtSize: 18
    property int maxLabelWidth: 300
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
    readonly property bool hasPlayer: player !== null
    // the placeholder is a plain glyph, so the transport row only stands in for a live player
    readonly property bool mprisView: mprisAppearance && hasPlayer
    readonly property bool shown: hasPlayer || showWhenIdle
    readonly property int artSize: Math.max(Style.px(12), Style.px(albumArtSize))
    readonly property string displayText: showArtist && Media.artist && Media.title
        ? Media.artist + " — " + Media.title : Media.title || Media.artist

    visible: shown
    implicitWidth: !shown ? 0 : mprisView
        ? (vertical ? artSize : contents.implicitWidth + Style.px(12))
        : compactLoader.item ? compactLoader.item.implicitWidth : 0
    implicitHeight: !shown ? 0 : mprisView
        ? Math.max(artSize, contents.implicitHeight)
        : compactLoader.item ? compactLoader.item.implicitHeight : 0

    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    function wheel(delta) { if (delta > 0) Media.previous(); else if (delta < 0) Media.next() }
    function metadataClick(button) {
        if (button === Qt.MiddleButton) Media.previous()
        else if (button === Qt.RightButton) Media.next()
        else shell.togglePopup("media")
    }

    Loader {
        id: compactLoader
        anchors.centerIn: parent
        active: !root.mprisView
        sourceComponent: compactView
    }
    Component {
        id: compactView
        BarButton {
            shell: root.shell
            css: "mediaplayer"
            textColor: shell.alpha(shell.role("act_fg", shell.foreground), .7)
            text: root.player ? Media.icon(root.player) + "  " + Media.remaining(root.player)
                : root.showWhenIdle ? root.idleIcon : ""
            onClicked: button => button === Qt.RightButton ? Media.playPause()
                : button === Qt.MiddleButton ? Media.next() : root.shell.togglePopup("media")
            onWheeled: delta => root.wheel(delta)
        }
    }

    MediaPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled; randomizeProgressShape: root.randomizeProgressShape }

    Row {
        id: contents
        anchors.centerIn: parent
        spacing: Style.px(4)
        layoutDirection: root.controlsRight ? Qt.RightToLeft : Qt.LeftToRight
        visible: root.mprisView

        Row {
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
            width: Math.min(Style.px(root.maxLabelWidth), label.implicitWidth)
            height: Math.max(root.artSize, label.implicitHeight)
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.vertical && root.displayText !== ""
            clip: true

            Text {
                id: label
                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: root.displayText; color: root.shell.foreground
                opacity: root.player && root.player.isPlaying ? .92 : .58
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
