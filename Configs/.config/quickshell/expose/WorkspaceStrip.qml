pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons as Commons
import "WindowModel.js" as WindowModel

Item {
    id: strip

    required property var controller
    required property string screenName
    required property real chipHeight
    readonly property real previewHeight: Math.max(chipHeight, controller.dragPreviewHeight)
    readonly property int hyprlandFullscreenMode: 2
    readonly property int windowBorderWidth: 2
    readonly property int windowGap: 2
    readonly property int thumbnailInset: 6
    readonly property var display: Quickshell.screens.find(screen => screen.name === screenName) ?? null
    readonly property var sourceToplevels: {
        const revision = controller.modelRevision
        return controller.toplevelsOnScreen(screenName)
    }
    property var toplevels: []
    readonly property var workspaces: strip.controller.workspacesForScreen(strip.screenName)
    readonly property var macSpaces: workspaces.regular.filter(workspace => String(workspace.name).indexOf("macspace_") === 0)

    function syncToplevels() {
        if (!WindowModel.sameItems(toplevels, sourceToplevels)) toplevels = sourceToplevels
    }
    onSourceToplevelsChanged: syncToplevels()
    Component.onCompleted: syncToplevels()

    Layout.fillWidth: true
    implicitWidth: row.implicitWidth + (newWorkspace.implicitWidth + Commons.Style.spacing.sm) * 2
    implicitHeight: Math.max(row.implicitHeight, newWorkspace.implicitHeight)
    readonly property real separatorCenterX: row.x + separator.x + separator.width / 2

    Row {
        id: row
        readonly property real maxVisibleX: strip.width - width - Commons.Style.spacing.sm - newWorkspace.implicitWidth
        x: separator.visible
            ? Math.max(0, Math.min(maxVisibleX, strip.width / 2 - separator.x - separator.width / 2))
            : (strip.width - width - Commons.Style.spacing.sm - newWorkspace.implicitWidth) / 2
        spacing: Commons.Style.spacing.sm

        Repeater {
            model: strip.workspaces.regular
            delegate: WorkspaceChip {}
        }

        Rectangle {
            id: separator
            visible: strip.workspaces.special.length > 0
            width: Commons.Style.normalBorderWidth
            height: strip.previewHeight
            color: Commons.Color.menu.border
        }

        Repeater {
            model: strip.workspaces.special
            delegate: WorkspaceChip {}
        }
    }

    WorkspaceChip {
        id: newWorkspace
        x: row.x + row.width + Commons.Style.spacing.sm
        modelData: null
    }

    component WorkspaceChip: Item {
        id: chip

        required property var modelData
        readonly property string name: chip.modelData ? String(chip.modelData.name || "") : ""
        readonly property bool shown: chip.modelData !== null && strip.controller.isWorkspaceShown(chip.modelData)
        readonly property bool highlighted: drop.containsDrag || pointer.containsMouse
        readonly property var monitor: chip.modelData?.monitor ?? strip.controller.monitorForScreen(strip.screenName)
        readonly property real monitorScale: monitor?.scale > 0 ? monitor.scale : 1
        readonly property real displayWidth: monitor?.width > 0 ? monitor.width / monitorScale : strip.display?.width ?? strip.previewHeight
        readonly property real displayHeight: monitor?.height > 0 ? monitor.height / monitorScale : strip.display?.height ?? strip.previewHeight
        readonly property real originX: monitor?.x ?? 0
        readonly property real originY: monitor?.y ?? 0
        readonly property var reserved: monitor?.lastIpcObject?.reserved ?? []
        readonly property real usableX: originX + Number(reserved[0] ?? 0)
        readonly property real usableY: originY + Number(reserved[1] ?? 0)
        readonly property real usableWidth: displayWidth - Number(reserved[0] ?? 0) - Number(reserved[2] ?? 0)
        readonly property real usableHeight: displayHeight - Number(reserved[1] ?? 0) - Number(reserved[3] ?? 0)
        readonly property var sourceWindows: {
            const revision = strip.controller.modelRevision
            return chip.modelData ? strip.toplevels.filter(top => WindowModel.isOnWorkspace(top, chip.modelData)
                && top.monitor === chip.monitor) : []
        }
        property var windows: []
        readonly property bool fullscreenPreview: windows.some(top => WindowModel.ipcFor(top).fullscreen === strip.hyprlandFullscreenMode)
        readonly property real previewOriginX: fullscreenPreview ? originX : usableX
        readonly property real previewOriginY: fullscreenPreview ? originY : usableY
        readonly property real previewWidth: fullscreenPreview ? displayWidth : usableWidth
        readonly property real previewHeight: fullscreenPreview ? displayHeight : usableHeight

        function syncWindows() {
            if (!WindowModel.sameItems(windows, sourceWindows)) windows = sourceWindows
        }
        onSourceWindowsChanged: syncWindows()
        Component.onCompleted: syncWindows()

        implicitWidth: strip.previewHeight * displayWidth / displayHeight
        implicitHeight: strip.previewHeight + Commons.Style.spacing.xs + label.implicitHeight

        Rectangle {
            id: thumbnail
            width: chip.width
            height: strip.previewHeight
            radius: Commons.Style.cornerRadius
            color: chip.modelData === null ? Commons.Style.popupTinted(Commons.Color.background) : Commons.Color.alpha(Commons.Style.popupTinted(Commons.Color.background), Commons.Style.popupSurfaceOpacity)
            clip: true

            Image {
                anchors.fill: parent
                visible: chip.modelData === null
                source: "file://" + Quickshell.env("HOME") + "/.cache/hypr/wallpaper/current/wall.thmb"
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                layer.enabled: visible
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: wallpaperMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
            }

            Rectangle {
                id: wallpaperMask
                anchors.fill: parent
                radius: thumbnail.radius
                color: "black"
                visible: false
                layer.enabled: true
                layer.smooth: true
            }

            Item {
                id: previewArea
                anchors.fill: parent
                anchors.margins: chip.fullscreenPreview ? 0 : strip.thumbnailInset
                clip: true
                layer.enabled: chip.fullscreenPreview
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: wallpaperMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }

                Repeater {
                    model: chip.windows
                    Item {
                        id: windowPreview
                        required property var modelData
                        readonly property var ipc: WindowModel.ipcFor(modelData)
                        readonly property real cornerRadius: ipc.fullscreen === strip.hyprlandFullscreenMode
                            ? 0 : Math.min(Commons.Style.cornerRadius, width / 2, height / 2)
                        readonly property var previewRect: {
                            const revision = strip.controller.modelRevision
                            return WindowModel.thumbnailRect(modelData, chip.windows,
                                { x: chip.previewOriginX, y: chip.previewOriginY, width: chip.previewWidth, height: chip.previewHeight },
                                previewArea.width, previewArea.height, strip.windowGap)
                        }
                        x: previewRect.x
                        y: previewRect.y
                        width: previewRect.width
                        height: previewRect.height

                        ScreencopyView {
                            anchors.fill: parent
                            captureSource: WindowModel.waylandFor(windowPreview.modelData)
                            live: strip.controller.opened
                            paintCursor: false
                            layer.enabled: windowPreview.cornerRadius > 0
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: windowMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1
                            }
                        }

                        Rectangle {
                            id: windowMask
                            anchors.fill: parent
                            radius: windowPreview.cornerRadius
                            color: "black"
                            visible: false
                            layer.enabled: windowPreview.cornerRadius > 0
                            layer.smooth: true
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: windowPreview.ipc.fullscreen !== strip.hyprlandFullscreenMode
                            radius: windowPreview.cornerRadius
                            color: "transparent"
                            border.width: strip.windowBorderWidth
                            border.color: Commons.Color.alpha(Commons.Color.role("br", Commons.Color.menu.text), Commons.Style.popupBorderOpacity)
                        }
                    }
                }
            }

            Text {
                visible: chip.modelData === null
                anchors.centerIn: parent
                text: "+"
                color: Commons.Color.menu.text
                font.family: Commons.Style.font.menuFamily
                font.pixelSize: Commons.Style.font.heading
            }

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: Commons.Style.normalBorderWidth
                border.color: chip.highlighted ? Commons.Color.menu.selectedBorder : chip.shown ? Commons.Color.accent : Commons.Color.menu.border
            }
        }

        Text {
            id: label
            y: thumbnail.height + Commons.Style.spacing.xs
            width: chip.width
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: chip.modelData === null ? "new" : chip.name.indexOf("special:") === 0
                ? chip.name.slice("special:".length) : chip.name.indexOf("macspace_") === 0
                    ? "Space " + (strip.macSpaces.indexOf(chip.modelData) + 1)
                    : strip.controller.formatWorkspaceLabel(chip.name)
            textFormat: Text.PlainText
            color: chip.shown ? Commons.Color.accent : Commons.Color.menu.text
            font.family: Commons.Style.font.menuFamily
            font.pixelSize: Commons.Style.font.body
            font.bold: chip.shown
        }

        MouseArea {
            id: pointer
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: strip.controller.showWorkspace(chip.modelData)
        }

        DropArea {
            id: drop
            anchors.fill: parent
            keys: strip.controller.windowDragKeys
            onDropped: function (event) {
                strip.controller.moveWindowTo((event.source as WindowCard).modelData, chip.modelData);
                event.accept();
            }
        }
    }
}
