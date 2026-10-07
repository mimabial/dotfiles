pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// The state and the rotation live in the Wallpaper singleton.
PopupCard {
    id: root
    popupName: "wallpaper"
    contentWidth: Style.px(360)
    contentHeight: wallColumn.implicitHeight + padding * 2

    readonly property int columns: 3
    readonly property real cellSpacing: Style.xs
    readonly property real cellSize: Math.floor((contentWidth - padding * 2 - cellSpacing * (columns - 1)) / columns)
    // a theme's wallpaper count is unbounded, so cap the grid and scroll it
    // rather than letting the card grow past the screen
    readonly property int gridRows: 3
    readonly property real gridMaxHeight: cellSize * gridRows + cellSpacing * (gridRows - 1)
    // the wallpaper under the cursor, shown in the section header — a tooltip
    // window would stack over the popup that owns the focus grab
    property string hoverName: ""
    // the slider's live position while dragging, so the reading tracks the knob
    // without writing the config on every step
    property int draftInterval: -1

    readonly property int intervalIndex: root.nearestStep(Wallpaper.intervalMinutes)
    readonly property int shownInterval: Wallpaper.intervalSteps[root.draftInterval >= 0 ? root.draftInterval : root.intervalIndex]

    // a hand-edited interval need not be one of the steps; snap to the closest
    function nearestStep(minutes) {
        const steps = Wallpaper.intervalSteps
        let best = 0
        for (let i = 1; i < steps.length; i++)
            if (Math.abs(steps[i] - minutes) < Math.abs(steps[best] - minutes)) best = i
        return best
    }

    // opening is the only moment worth paying for thumbnail generation
    onOpenChanged: {
        if (!open) { root.hoverName = ""; root.draftInterval = -1; return }
        Wallpaper.nowEpoch = Date.now()
        Wallpaper.updateCurrent()
        Wallpaper.refresh(true)
    }

    Column {
        id: wallColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero { shell: root.shell; title: "Wallpaper"; status: Wallpaper.nextText() }

        PopupSeparator { shell: root.shell }

        Column {
            width: parent.width; spacing: Style.sm
            PopupSection {
                shell: root.shell; text: "WALLPAPERS"
                value: root.hoverName !== "" ? root.hoverName
                    : Wallpaper.entries.length + (Wallpaper.themeName ? " · " + Wallpaper.themeName : "")
            }

            Flickable {
                id: gridScroll
                width: parent.width
                height: Math.min(wallFlow.implicitHeight, root.gridMaxHeight)
                contentWidth: width
                contentHeight: wallFlow.implicitHeight
                interactive: contentHeight > height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: gridScroll.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

                Flow {
                    id: wallFlow
                    width: gridScroll.width
                    spacing: root.cellSpacing

                    Repeater {
                        model: Wallpaper.entries

                        delegate: Rectangle {
                            id: cell
                            required property var modelData
                            readonly property bool navigable: true
                            property bool cursored: false
                            signal clicked(int button)
                            onClicked: Wallpaper.setWallpaper(modelData.path)
                            readonly property bool isCurrent: Wallpaper.current === modelData.path
                            // the thumbnail cache can lag a freshly added wallpaper;
                            // fall back to the full image rather than an empty cell
                            property bool thumbFailed: false
                            width: root.cellSize; height: root.cellSize
                            color: root.shell.alpha(root.shell.foreground, .06)
                            radius: root.shell.rounding
                            clip: true

                            Image {
                                anchors.fill: parent
                                // decode only while the panel is open, at thumbnail size,
                                // and drop the pixmap on close
                                source: root.open ? Wallpaper.fileUrl(cell.thumbFailed ? cell.modelData.path : cell.modelData.thumb) : ""
                                sourceSize: Qt.size(240, 240)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                smooth: true
                                onStatusChanged: if (status === Image.Error && !cell.thumbFailed) cell.thumbFailed = true
                            }
                            Rectangle {
                                id: nonCurrentShade
                                anchors.fill: parent; radius: parent.radius
                                color: root.shell.alpha(root.shell.background,
                                    cell.isCurrent ? 0 : cellMouse.containsMouse ? .1 : .35)
                                Behavior on color { ColorAnimation { duration: Style.hoverDuration } }
                            }
                            // drawn over the image so it cannot be hidden by it
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius; color: "transparent"
                                border.width: cell.isCurrent ? 2 : 1
                                border.color: cell.cursored ? root.shell.hoverEdge(.85) : cell.isCurrent ? root.shell.role("act_br", root.shell.accent)
                                    : cellMouse.containsMouse ? root.shell.hoverEdge()
                                    : root.shell.alpha(root.shell.foreground, .18)
                            }
                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.hoverName = cell.modelData.name
                                onExited: if (root.hoverName === cell.modelData.name) root.hoverName = ""
                                onClicked: cell.clicked(Qt.LeftButton)
                            }
                        }
                    }
                }
            }

            Text {
                visible: Wallpaper.entries.length === 0
                width: parent.width
                text: "No wallpapers found for this theme."
                color: root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                wrapMode: Text.WordWrap
            }
        }

        PopupSeparator { shell: root.shell }

        Column {
            width: parent.width; spacing: Style.sm
            PopupSection { shell: root.shell; text: "SCHEDULE" }

            PopupToggleRow {
                width: parent.width; shell: root.shell
                icon: Wallpaper.enabled ? "󰑖" : "󰑗"
                title: "Automatic switching"
                detail: Wallpaper.enabled ? Wallpaper.intervalLabel(Wallpaper.intervalMinutes) : "Paused"
                checked: Wallpaper.enabled
                onToggled: Wallpaper.setEnabled(!Wallpaper.enabled)
            }

            PopupSlider {
                width: parent.width
                shell: root.shell
                label: "Interval"
                value: root.intervalIndex
                minimum: 0
                maximum: Wallpaper.intervalSteps.length - 1
                step: 1
                tickCount: Wallpaper.intervalSteps.length
                valueText: Wallpaper.intervalLabel(root.shownInterval)
                onChanged: value => root.draftInterval = Math.round(value)
                onReleased: value => {
                    root.draftInterval = -1
                    Wallpaper.updateSchedule({intervalMinutes: Wallpaper.intervalSteps[Math.round(value)]})
                }
            }

            Row {
                width: parent.width; spacing: Style.sm
                Repeater {
                    model: [{value: "sequential", label: "Sequential", icon: "󰒬"},
                            {value: "shuffle", label: "Shuffle", icon: "󰒝"}]
                    PopupTab {
                        required property var modelData
                        width: (wallColumn.width - Style.sm) / 2
                        shell: root.shell; icon: modelData.icon; text: modelData.label
                        selected: Wallpaper.mode === modelData.value
                        onClicked: Wallpaper.updateSchedule({mode: modelData.value})
                    }
                }
            }

            PopupRow {
                width: parent.width; shell: root.shell
                icon: Wallpaper.busy ? "󰔟" : "󰑐"; title: Wallpaper.busy ? "Applying…" : "Apply next wallpaper now"
                enabled: !Wallpaper.busy
                onClicked: Wallpaper.applyNext()
            }

            Text {
                visible: text !== ""
                width: parent.width
                text: Wallpaper.lastError !== "" ? Wallpaper.lastError : Wallpaper.lastAction
                color: Wallpaper.lastError !== "" ? root.shell.role("error", root.shell.foreground)
                    : root.shell.mutedText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "Picking a wallpaper here restarts the interval, so manual choices and "
                    + "scheduled changes share one rotation. "
                    + (Wallpaper.shuffle ? "Shuffle plays every wallpaper once before repeating."
                        : "Sequential advances by one wallpaper each interval.")
                color: root.shell.faintText
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                wrapMode: Text.WordWrap
            }
        }
    }
}
