pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var shell
    property int cursor: -1
    readonly property FolderListModel pacmanLock: FolderListModel { folder: "file:///var/lib/pacman"; nameFilters: ["db.lck"]; showDirs: false }
    readonly property FolderListModel unfinishedDownloads: FolderListModel {
        folder: "file://" + root.shell.home + "/Downloads"; nameFilters: ["*.part", "*.crdownload"]; showDirs: false
    }
    readonly property var shutdownWarnings: [
        pacmanLock.count > 0 ? "The package database is locked: an update may be running" : "",
        unfinishedDownloads.count > 0 ? unfinishedDownloads.count + (unfinishedDownloads.count === 1 ? " download is" : " downloads are") + " unfinished in ~/Downloads" : ""
    ].filter(Boolean)

    readonly property real restInsetX: width * 0.35
    readonly property real restInsetY: height * 0.25
    readonly property real hoverInsetX: width * 0.32
    readonly property real hoverInsetY: height * 0.20
    readonly property real restIconRatio: 0.10
    readonly property real cursorIconRatio: 0.20
    readonly property real hoverIconRatio: 0.25
    readonly property real labelSize: height * 0.02
    readonly property real restOpacity: 0.5
    readonly property real edgeRadius: shell.rounding * 8
    readonly property real hoverRadius: shell.rounding * 5
    readonly property var actions: [
        { key: "l", text: "Lock", icon: "\uf023", column: 0, row: 0, command: ["hyprshell", "session/lock-screen.sh"] },
        { key: "e", text: "Logout", icon: "\u{f0343}", column: 0, row: 1, command: ["hyprshell", "logout"] },
        { key: "s", text: "Shutdown", icon: "\u{f0425}", column: 1, row: 0, command: ["hyprshell", "system/powerctl.sh", "shutdown"] },
        { key: "r", text: "Reboot", icon: "\u{f0709}", column: 1, row: 1, command: ["hyprshell", "system/powerctl.sh", "reboot"] }
    ]

    function close() { shell.sessionMenuScreen = "" }
    function run(action) { shell.run(action.command); close() }
    function indexAt(column, row) { return actions.findIndex(item => item.column === column && item.row === row) }
    function handleKey(event) {
        const action = actions.find(item => item.key === event.text.toLowerCase())
        const current = actions[Math.max(cursor, 0)]
        if (action) run(action)
        else if (event.key === Qt.Key_Escape) close()
        else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) cursor = indexAt(1 - current.column, current.row)
        else if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) cursor = indexAt(current.column, 1 - current.row)
        else if (event.key === Qt.Key_Tab) cursor = (cursor + 1) % actions.length
        else if (cursor >= 0 && [Qt.Key_Return, Qt.Key_Enter, Qt.Key_Space].includes(event.key)) run(actions[cursor])
        else return
        event.accepted = true
    }

    screen: Quickshell.screens.find(screen => screen.name === shell.sessionMenuScreen) ?? null
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "hypr-shell-session"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => root.handleKey(event)
        onClicked: root.close()
    }
    Repeater {
        model: root.actions
        Rectangle {
            id: quadrant
            required property var modelData
            required property int index
            readonly property int column: modelData.column
            readonly property int row: modelData.row
            readonly property real iconRatio: index === root.cursor ? root.cursorIconRatio : root.restIconRatio
            property real hoverProgress: area.containsMouse ? 1 : 0
            Behavior on hoverProgress { NumberAnimation { duration: Style.duration(300); easing.type: Easing.BezierSpline; easing.bezierCurve: [0.55, 0, 0.28, 1.682, 1, 1] } }
            readonly property real insetX: root.restInsetX + (root.hoverInsetX - root.restInsetX) * hoverProgress
            readonly property real insetY: root.restInsetY + (root.hoverInsetY - root.restInsetY) * hoverProgress
            function cornerRadius(cornerColumn, cornerRow) {
                const atScreenEdge = cornerColumn === column && cornerRow === row
                const atCentre = cornerColumn !== column && cornerRow !== row
                return atScreenEdge ? root.edgeRadius + (root.hoverRadius - root.edgeRadius) * hoverProgress
                    : atCentre ? 0 : root.hoverRadius * hoverProgress
            }
            x: column ? root.width / 2 : insetX
            y: row ? root.height / 2 : insetY
            width: root.width / 2 - insetX
            height: root.height / 2 - insetY
            topLeftRadius: cornerRadius(0, 0)
            topRightRadius: cornerRadius(1, 0)
            bottomLeftRadius: cornerRadius(0, 1)
            bottomRightRadius: cornerRadius(1, 1)
            color: area.containsMouse ? root.shell.role("hvr_br", root.shell.accent)
                : index === root.cursor ? root.shell.accent : root.shell.alpha(root.shell.background, root.restOpacity)

            Text {
                anchors.centerIn: parent
                text: quadrant.modelData.icon
                color: root.shell.foreground
                font.family: root.shell.iconGlyphFont
                font.pixelSize: quadrant.width * (quadrant.iconRatio + (root.hoverIconRatio - quadrant.iconRatio) * quadrant.hoverProgress)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: font.pixelSize
                text: quadrant.modelData.text
                color: root.shell.foreground
                font.family: root.shell.fontFamily
                font.pixelSize: root.labelSize
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.run(quadrant.modelData)
            }
        }
    }
    Text {
        visible: root.shutdownWarnings.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(Style.popupPadding / 2, Style.sm)
        text: root.shutdownWarnings.join(" · ")
        color: root.shell.role("warning", root.shell.foreground)
        font.family: root.shell.fontFamily
        font.pixelSize: Style.body
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.max(Style.popupPadding / 2, Style.sm)
        text: root.actions.map(action => action.key.toUpperCase() + " " + action.text.toLowerCase()).join(" · ") + " · ←→↑↓/Tab move · Enter select · Esc"
        color: root.shell.mutedText
        font.family: root.shell.fontFamily
        font.pixelSize: Style.caption
    }
}
