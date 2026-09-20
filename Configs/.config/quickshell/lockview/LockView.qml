pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
    id: root
    property var shell: null
    property var layouts: []
    property var cmdText: ({})
    property int current: 0
    property bool full: false
    property bool stale: false

    readonly property color background: Color.menu.background
    readonly property color foreground: Color.menu.text
    readonly property color muted: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
    readonly property color accent: Color.accent
    readonly property string fontFamily: Style.font.menuFamily
    readonly property int columns: 3
    readonly property int contentMargin: Style.spacing.panelPadding + Style.space(8)
    readonly property int gap: Style.space(20)
    readonly property int captionHeight: Style.space(58)
    readonly property int headerHeight: Style.space(96)
    readonly property int footerHeight: Style.space(40)
    readonly property int rightPanelW: Style.space(348)
    readonly property var selected: layouts[current] ?? null
    readonly property string activeName: layouts.find(layout => layout.active)?.name ?? ""

    function close() {
        root.shell.lockviewScreen = ""
    }
    function move(step) {
        root.current = Math.max(0, Math.min(root.layouts.length - 1, root.current + step))
    }
    function script(action) {
        return [root.shell.home + "/.local/lib/hypr/session/hyprlock.sh", action, root.selected.name]
    }
    function apply() {
        if (!root.selected)
            return
        applier.command = root.script("--apply")
        applier.running = true
    }
    function test() {
        if (root.selected)
            Quickshell.execDetached(root.script("--test"))
    }
    function refresh() {
        if (helper.running)
            root.stale = true
        else
            helper.running = true
    }
    function targetScreen() {
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; ++i)
            if (screens[i].name === root.shell.lockviewScreen)
                return screens[i]
        return screens[0]
    }

    Component.onCompleted: {
        Style.shell = root.shell
        Color.shell = root.shell
    }

    Process {
        id: helper
        running: true
        command: [root.shell.home + "/.local/lib/hypr/session/hyprlock.preview.py"]
        stdout: SplitParser {
            onRead: line => {
                const message = JSON.parse(line)
                if (message.kind === "layouts") {
                    const keep = root.layouts[root.current]?.name
                    root.layouts = message.layouts
                    const index = message.layouts.findIndex(layout => keep ? layout.name === keep : layout.active)
                    root.current = Math.max(0, index)
                } else {
                    root.cmdText = Object.assign({}, root.cmdText, { [message.cmd]: message.text })
                }
            }
        }
        // A re-port rewrites every layout at once; one more run after this one covers them all.
        onExited: {
            if (root.stale) {
                root.stale = false
                helper.running = true
            }
        }
    }

    // Anything the preview is built from: the layouts, the palette, the shared
    // variables every layout is parsed against, and the helper's own code.
    component Watch: FileView {
        required property var owner
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload()
            owner.refresh()
        }
    }

    Instantiator {
        model: root.layouts
        delegate: Watch {
            required property var modelData
            owner: root
            path: modelData.path
        }
    }

    Instantiator {
        model: [root.shell.home + "/.config/hypr/hyprlock/colors.conf",
                root.shell.home + "/.local/share/hypr/hyprlock.conf",
                root.shell.home + "/.local/lib/hypr/session/hyprlock.preview.py",
                root.shell.home + "/.local/lib/hypr/pyutils/hyprlang.py"]
        delegate: Watch {
            required property string modelData
            owner: root
            path: modelData
        }
    }

    Process {
        id: applier
        onExited: exitCode => {
            if (exitCode === 0)
                root.close()
            else
                console.warn("lockview: hyprlock.sh --apply exited " + exitCode)
        }
    }

    FloatingWindow {
        id: window
        // Layout offsets target the lock surface of the monitor the explorer opened from.
        readonly property var monitor: root.targetScreen()
        readonly property real canvasWidth: window.monitor.width * window.monitor.devicePixelRatio
        readonly property real canvasHeight: window.monitor.height * window.monitor.devicePixelRatio

        title: "Lock Layouts"
        implicitWidth: Math.min(Style.space(1560), window.monitor.width * 0.9)
        implicitHeight: window.monitor.height * 0.9
        color: Color.alpha(root.background, Style.popupSurfaceOpacity)
        onClosed: root.close()

        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                switch (event.key) {
                case Qt.Key_Left: case Qt.Key_H: root.move(-1); break
                case Qt.Key_Right: case Qt.Key_L: root.move(1); break
                case Qt.Key_Up: case Qt.Key_K: root.move(-root.columns); break
                case Qt.Key_Down: case Qt.Key_J: root.move(root.columns); break
                case Qt.Key_Space: root.full = !root.full; break
                case Qt.Key_Return: case Qt.Key_Enter: root.apply(); break
                case Qt.Key_T: root.test(); break
                case Qt.Key_R: root.refresh(); break
                case Qt.Key_Escape:
                    if (root.full) root.full = false
                    else root.close()
                    break
                default: return
                }
                event.accepted = true
            }
        }

        Item {
            id: content
            anchors.fill: parent
            anchors.margins: root.contentMargin

            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.headerHeight

                Column {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    spacing: 3
                    Row {
                        spacing: Style.space(8)
                        Text {
                            text: "::"
                            color: root.accent
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.display
                            font.weight: Font.Bold
                        }
                        Text {
                            text: "LOCK SCREEN EXPLORER"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.display
                            font.weight: Font.Bold
                            font.letterSpacing: 2
                        }
                    }
                    Text {
                        text: root.layouts.length + " hyprlock layouts · " + (root.shell.themeName || "your theme") + " · follows your theme"
                        textFormat: Text.PlainText
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }
                }

                Rectangle {
                    visible: root.activeName !== ""
                    anchors.right: parent.right
                    anchors.top: parent.top
                    width: activeLabel.implicitWidth + Style.space(20)
                    height: Style.space(28)
                    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
                    Text {
                        id: activeLabel
                        anchors.centerIn: parent
                        text: "Active: " + root.activeName
                        textFormat: Text.PlainText
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                    }
                }
            }

            GridView {
                id: grid
                readonly property int cellSpan: Math.floor(width / root.columns)
                readonly property int thumbWidth: cellSpan - root.gap
                readonly property int thumbHeight: Math.round(thumbWidth * window.canvasHeight / window.canvasWidth)
                anchors.top: header.bottom
                anchors.bottom: footer.top
                anchors.left: parent.left
                anchors.right: previewPanel.left
                anchors.rightMargin: Style.space(20)
                anchors.bottomMargin: Style.space(8)
                clip: true
                model: root.layouts
                currentIndex: root.current
                cellWidth: cellSpan
                cellHeight: thumbHeight + root.captionHeight + root.gap
                topMargin: Style.space(4)
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.current
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: frame
                        width: grid.thumbWidth
                        height: grid.thumbHeight
                        color: Color.background
                        border.width: cell.selected ? 3 : 1
                        border.color: cell.selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)
                        clip: true
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        Item {
                            anchors.fill: parent
                            anchors.margins: frame.border.width
                            clip: true
                            LockCanvas {
                                anchors.fill: parent
                                nativeWidth: window.canvasWidth
                                nativeHeight: window.canvasHeight
                                layout: cell.modelData
                                cmdText: root.cmdText
                                screenName: window.monitor.name
                            }
                        }
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: Style.space(10)
                            width: Style.space(24)
                            height: Style.space(24)
                            radius: 5
                            color: Qt.rgba(0, 0, 0, 0.55)
                            Text {
                                anchors.centerIn: parent
                                text: cell.index + 1
                                color: "#ffffff"
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                        }
                        Rectangle {
                            visible: cell.modelData.active
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Style.space(10)
                            width: activeText.implicitWidth + Style.space(14)
                            height: Style.space(24)
                            color: root.accent
                            Text {
                                id: activeText
                                anchors.centerIn: parent
                                text: "󰄬 Active"
                                color: Color.background
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.current = cell.index
                            onDoubleClicked: { root.current = cell.index; root.apply() }
                        }
                        Row {
                            visible: cell.selected
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Style.space(10)
                            spacing: Style.space(6)
                            Rectangle {
                                width: useLabel.implicitWidth + Style.space(16)
                                height: Style.space(26)
                                radius: 6
                                color: root.accent
                                Text {
                                    id: useLabel
                                    anchors.centerIn: parent
                                    text: "Use  ⏎"
                                    color: Color.background
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.apply()
                                }
                            }
                            Rectangle {
                                width: testLabel.implicitWidth + Style.space(16)
                                height: Style.space(26)
                                radius: 6
                                color: Qt.rgba(0, 0, 0, 0.6)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.25)
                                Text {
                                    id: testLabel
                                    anchors.centerIn: parent
                                    text: "Test  T"
                                    color: "#ffffff"
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.test()
                                }
                            }
                        }
                    }

                    Column {
                        anchors.top: frame.bottom
                        anchors.topMargin: Style.space(8)
                        width: grid.thumbWidth
                        spacing: 2
                        Row {
                            spacing: Style.space(8)
                            Text {
                                text: cell.modelData.name
                                textFormat: Text.PlainText
                                color: cell.selected ? root.foreground : root.muted
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.weight: cell.selected ? Font.DemiBold : Font.Normal
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: tagLabel.implicitWidth + Style.space(10)
                                height: Style.space(18)
                                radius: 4
                                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                                Text {
                                    id: tagLabel
                                    anchors.centerIn: parent
                                    text: cell.modelData.path.startsWith(root.shell.home + "/.config/") ? "user" : "shared"
                                    color: root.muted
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }
                        Text {
                            width: parent.width
                            text: cell.modelData.path.replace(root.shell.home, "~")
                            textFormat: Text.PlainText
                            elide: Text.ElideMiddle
                            color: root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.bodySmall
                        }
                    }
                }
            }

            Column {
                id: previewPanel
                anchors.top: header.bottom
                anchors.bottom: footer.top
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.topMargin: Style.space(6)
                width: root.rightPanelW - Style.space(8)
                spacing: Style.space(12)

                Item {
                    width: parent.width
                    height: lockLabel.implicitHeight
                    Text {
                        id: lockLabel
                        text: "LOCK SCREEN"
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 2
                    }
                    Text {
                        anchors.right: parent.right
                        text: root.selected?.name ?? ""
                        textFormat: Text.PlainText
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                }
                Rectangle {
                    width: parent.width
                    height: Math.round(parent.width * window.canvasHeight / window.canvasWidth)
                    color: Color.background
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
                    clip: true
                    LockCanvas {
                        anchors.fill: parent
                        anchors.margins: 1
                        nativeWidth: window.canvasWidth
                        nativeHeight: window.canvasHeight
                        layout: root.selected
                        cmdText: root.cmdText
                        screenName: window.monitor.name
                    }
                }
                Rectangle {
                    width: parent.width
                    height: Style.space(30)
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, fullButton.containsMouse ? 0.12 : 0.05)
                    border.width: 1
                    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
                    Text {
                        anchors.centerIn: parent
                        text: "Preview full screen · Space"
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                        id: fullButton
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.full = true
                    }
                }
            }

            Item {
                id: footer
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: root.footerHeight
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Arrows: browse   Space: preview   Enter: select   T: test   R: reload   Esc: close"
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                }
            }
        }

        Loader {
            anchors.fill: parent
            active: root.full && root.selected !== null
            sourceComponent: MouseArea {
                id: fullView
                readonly property real fit: Math.min(fullView.width / window.canvasWidth,
                                                     fullView.height / window.canvasHeight)
                onClicked: root.full = false
                Rectangle {
                    anchors.fill: parent
                    color: root.background
                }
                LockCanvas {
                    x: (fullView.width - window.canvasWidth * fullView.fit) / 2
                    y: (fullView.height - window.canvasHeight * fullView.fit) / 2
                    width: window.canvasWidth * fullView.fit
                    height: window.canvasHeight * fullView.fit
                    nativeWidth: window.canvasWidth
                    nativeHeight: window.canvasHeight
                    layout: root.selected
                    cmdText: root.cmdText
                    screenName: window.monitor.name
                }
            }
        }
    }
}
