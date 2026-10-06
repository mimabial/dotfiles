pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris

Item {
    id: root
    required property var shell
    property string appearance: "countdown"
    property int cavaBars: 16
    property real cavaBarWidth: 2
    property real cavaGap: 1
    property string cavaPosition: "center"
    property string cavaMode: "bars"
    property int cavaFps: 20
    property real cavaGain: 1
    property int cavaSmoothing: 77
    property bool noIcon: false
    property bool popupEnabled: true
    property int albumArtSize: 18
    property bool showAlbumArt: true
    property string artIcon: "󰝚"
    property int maxLabelWidth: 300
    property bool fillAvailableWidth: false
    property bool showControls: true
    property bool controlsRight: false
    property bool showArtist: true
    property bool randomizeProgressShape: false
    // with no player the module collapses to nothing; showWhenIdle keeps a
    // placeholder in the bar to open the popup from
    property bool showWhenIdle: false
    property string idleIcon: "󰽯"
    property var idleQuotes: [
        { text: "What we play is life.", author: "Louis Armstrong" },
        { text: "I hear America singing", author: "Walt Whitman" },
        { text: "Music, when soft voices die", author: "P. B. Shelley" },
        { text: "If music be the food of love", author: "William Shakespeare" },
        { text: "And sings the tune", author: "Emily Dickinson" },
        { text: "Heard melodies are sweet", author: "John Keats" },
        { text: "The aim was song", author: "Robert Frost" },
        { text: "the mermaids singing", author: "T. S. Eliot" },
        { text: "Keeping time, time, time,", author: "Edgar Allan Poe" },
        { text: "A River sings", author: "Maya Angelou" },
        { text: "Sing low, sing high", author: "Carl Sandburg" },
        { text: "loving nothing but music", author: "Naomi Shihab Nye" },
        { text: "Singing everlastingly;", author: "John Milton" },
        { text: "Music is music", author: "Elizabeth Akers Allen" },
        { text: "Music is feeling", author: "Wallace Stevens" },
        { text: "You got a song, man", author: "Martín Espada" },
        { text: "I sing the body electric", author: "Walt Whitman" },
        { text: "Sounds and sweet airs", author: "William Shakespeare" },
        { text: "Our sweetest songs", author: "P. B. Shelley" },
        { text: "Sing and let your song be new", author: "J. Osherow" }
    ]
    property int idleQuoteIndex: 0
    readonly property var idleQuote: idleQuotes.length ? idleQuotes[idleQuoteIndex % idleQuotes.length] : null
    readonly property string idleText: idleQuote
        ? (showArtist && idleQuote.author ? idleQuote.author + " — " : "") + idleQuote.text : ""
    readonly property bool cavaAppearance: appearance === "cava"
    readonly property bool mprisAppearance: appearance === "mpris"
    readonly property bool iconAppearance: appearance === "icon" && !noIcon
    readonly property var player: Media.player
    readonly property Item simpleItem: simpleLoader.item as Item
    readonly property bool hasPlayer: player !== null
    readonly property bool mprisView: mprisAppearance && shown
    readonly property bool shown: hasPlayer || showWhenIdle
    readonly property int artSize: Math.max(Style.px(12), Style.px(albumArtSize))
    readonly property int fixedWidth: (transport.visible ? transport.implicitWidth + contents.spacing : 0)
        + (noIcon ? 0 : artSize + metadata.spacing) + Style.px(12)
    readonly property string displayText: !hasPlayer ? idleText : showArtist && Media.artist && Media.title
        ? Media.artist + " — " + Media.title : Media.title || Media.artist

    visible: shown
    implicitWidth: !shown ? 0 : mprisView
        ? (fillAvailableWidth ? fixedWidth : contents.implicitWidth + Style.px(12))
        : root.simpleItem ? root.simpleItem.implicitWidth : 0
    implicitHeight: !shown ? 0 : mprisView
        ? Math.max(artSize, contents.implicitHeight)
        : root.simpleItem ? root.simpleItem.implicitHeight : 0

    Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    function wheel(delta) { if (delta > 0) Media.previous(); else if (delta < 0) Media.next() }
    function cycleIdleQuote() { if (idleQuotes.length > 1) idleQuoteIndex = (idleQuoteIndex + 1) % idleQuotes.length }
    function rightClick() {
        if (cavaAppearance) cavaMode = Cava.modes[(Cava.modes.indexOf(cavaMode) + 1) % Cava.modes.length]
        else Media.playPause()
    }
    function metadataClick(button) {
        if (button === Qt.MiddleButton) Media.previous()
        else if (button === Qt.RightButton) rightClick()
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
        id: simpleLoader
        anchors.verticalCenter: parent.verticalCenter
        width: root.simpleItem ? root.simpleItem.implicitWidth : 0
        // swapping left/horizontalCenter anchors after creation briefly sets both, which pins width to 0
        x: root.fillAvailableWidth ? 0 : (root.width - width) / 2
        active: root.shown && !root.mprisView
        sourceComponent: simpleView
    }
    Component {
        id: simpleView
        BarButton {
            id: readout
            shell: root.shell
            opensPopup: true
            css: "mediaplayer"
            maxWidth: !root.player && root.showWhenIdle && !root.iconAppearance
                ? Math.min(Style.px(root.maxLabelWidth), root.fillAvailableWidth ? Math.max(1, root.width) : Style.px(root.maxLabelWidth))
                : 0
            textColor: !root.player && root.showWhenIdle ? shell.alpha(shell.foreground, .5)
                : box.color !== undefined ? styleColor("color")
                : shell.alpha(shell.role("act_fg", shell.foreground), .7)
            leadingIcon: !root.noIcon && !root.player && root.showWhenIdle && !root.iconAppearance ? root.idleIcon : ""
            text: root.player ? root.cavaAppearance ? (root.noIcon ? "" : Media.icon(root.player)) : (root.noIcon ? Media.remaining(root.player)
                : Media.icon(root.player) + (root.iconAppearance ? "" : "  " + Media.remaining(root.player)))
                : root.showWhenIdle ? (root.iconAppearance ? root.idleIcon : root.idleText) : ""
            tooltip: root.cavaAppearance && root.hasPlayer ? root.displayText : ""
            trailingWidth: spectrum.active ? spectrum.width + (text ? Style.sm : 0) : 0
            onHoveredChanged: if (hovered && !root.player && !root.iconAppearance) root.cycleIdleQuote()
            onClicked: button => button === Qt.RightButton ? root.rightClick()
                : button === Qt.MiddleButton ? Media.next() : root.shell.togglePopup("media")
            onWheeled: delta => root.wheel(delta)
            Binding on implicitHeight {
                when: spectrum.active
                value: Math.max(readout.box.minHeight, root.artSize) + readout.verticalInsets
            }
            Loader {
                id: spectrum
                active: root.cavaAppearance && root.hasPlayer
                opacity: root.player?.isPlaying ? 1 : root.player?.playbackState === MprisPlaybackState.Paused ? 0.25 : 0.1
                anchors.right: parent.right
                anchors.rightMargin: readout.box.margin[1] + readout.paintedBorderWidth + readout.box.padding[1]
                anchors.verticalCenter: parent.verticalCenter
                width: (item as Item)?.implicitWidth ?? 0
                height: root.artSize
                sourceComponent: Component {
                    CavaView {
                        shell: root.shell
                        playing: !!root.player?.isPlaying
                        barCount: root.cavaBars
                        barWidth: Style.px(root.cavaBarWidth)
                        gap: Style.px(root.cavaGap)
                        position: root.cavaPosition
                        mode: root.cavaMode
                        frameRate: root.cavaFps
                        gain: root.cavaGain
                        smoothing: root.cavaSmoothing
                    }
                }
            }
        }
    }

    MediaPopup { anchorItem: root.fillAvailableWidth ? (root.mprisView ? contents : simpleLoader) : root; shell: root.shell; popupEnabled: root.popupEnabled; randomizeProgressShape: root.randomizeProgressShape }

    Row {
        id: contents
        anchors.verticalCenter: parent.verticalCenter
        x: root.fillAvailableWidth ? 0 : (root.width - width) / 2
        spacing: Style.px(4)
        layoutDirection: root.controlsRight ? Qt.RightToLeft : Qt.LeftToRight
        visible: root.mprisView

        Row {
            id: transport
            spacing: Style.px(4); layoutDirection: Qt.LeftToRight; visible: root.showControls && root.hasPlayer
            TransportButton { iconText: "󰒮"; enabled: !!(root.player && root.player.canGoPrevious); onTriggered: Media.previous() }
            TransportButton {
                iconText: root.player && root.player.isPlaying ? "󰏤" : "󰐊"
                enabled: !!(root.player && (root.player.canPlay || root.player.canPause || root.player.canTogglePlaying))
                onTriggered: Media.playPause()
            }
            TransportButton { iconText: "󰒭"; enabled: !!(root.player && root.player.canGoNext); onTriggered: Media.next() }
        }

        Row {
          id: metadata
          spacing: Style.px(4); layoutDirection: Qt.LeftToRight
          HoverHandler { onHoveredChanged: if (hovered && !root.player) root.cycleIdleQuote() }
          Item {
            id: artContainer
            width: root.artSize; height: root.artSize
            visible: !root.noIcon
            anchors.verticalCenter: parent.verticalCenter

            Rectangle { anchors.fill: parent; radius: Style.px(3); color: root.shell.alpha(root.shell.foreground, .08) }
            Image {
                id: cover
                anchors.fill: parent; anchors.margins: 1
                source: root.showAlbumArt ? Media.artUrl : ""
                sourceSize.width: Math.round(width * Screen.devicePixelRatio)
                sourceSize.height: Math.round(height * Screen.devicePixelRatio)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true; cache: true; smooth: true
            }
            Text {
                anchors.centerIn: parent
                visible: !root.showAlbumArt || Media.artUrl === "" || cover.status === Image.Error
                text: root.hasPlayer ? root.artIcon : root.idleIcon; color: root.shell.foreground
                font.family: root.shell.iconGlyphFont; font.pixelSize: Style.body
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
            visible: root.displayText !== ""
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
            font.family: root.shell.iconGlyphFont; font.pixelSize: Style.body
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
