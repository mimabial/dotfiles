pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs.Commons as Commons

Column {
    id: root
    readonly property int maxWindows: 8
    readonly property int maxLabelLength: 32
    required property string appName
    property string suffix: ""
    required property var windows
    property bool advanced: true
    property bool previews: false
    property real previewWidth: Commons.Style.spacing.dropdownWidth
    readonly property real previewHeight: previews
        ? Math.max(0, ...windows.map(window => Math.min(previewWidth, previewWidth / windowAspect(window)))) : 0
    property int selectedIndex: -1
    required property var windowFocused
    required property var windowParked
    required property var windowLabel
    spacing: Commons.Style.space(3)

    function windowAspect(window) {
        const size = window?.toplevel?.lastIpcObject?.size
        return size?.[0] > 0 && size?.[1] > 0 ? size[0] / size[1] : 1
    }

    Row {
        spacing: Commons.Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
            text: root.appName
            textFormat: Text.PlainText
            color: Commons.Color.tooltip.text
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            font.bold: root.advanced && root.windows.length > 0
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.suffix !== ""
            text: root.suffix
            textFormat: Text.PlainText
            color: Commons.Util.alpha(Commons.Color.tooltip.text, 0.80)
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Grid {
        columns: root.previews ? Math.max(1, root.windows.length) : 1
        columnSpacing: Commons.Style.spacing.sm
        rowSpacing: root.spacing
        Repeater {
            model: (root.previews ? root.windows : root.advanced ? root.windows.slice(0, root.maxWindows) : [])
                .map(window => window.address)
            delegate: Column {
                id: tooltipRow
                required property int index
                required property var modelData
                spacing: Commons.Style.spacing.sm
                readonly property var window: root.windows[index] || null
                readonly property bool selected: root.selectedIndex === index
                readonly property bool focused: !!window && root.windowFocused(window)
                readonly property bool parked: !!window && root.windowParked(window)
                readonly property real aspect: root.windowAspect(window)

                Loader {
                    active: root.previews
                    visible: active
                    width: root.previewWidth
                    height: root.previewHeight
                    sourceComponent: Item {
                        Text {
                            anchors.centerIn: parent
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            visible: !preview.hasContent
                            text: "Preview unavailable"
                            elide: Text.ElideRight
                            color: Commons.Color.tooltip.text
                            font.family: Commons.Style.font.family
                            font.pixelSize: Commons.Style.font.caption
                        }
                        ScreencopyView {
                            id: preview
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height * tooltipRow.aspect)
                            height: Math.min(parent.height, parent.width / tooltipRow.aspect)
                            captureSource: tooltipRow.window?.toplevel?.wayland ?? null
                            live: true
                            paintCursor: false
                        }
                    }
                }
                RowLayout {
                    id: info
                    visible: root.advanced
                    width: root.previews ? root.previewWidth : implicitWidth
                    spacing: Commons.Style.space(5)

                    Rectangle {
                        implicitWidth: Commons.Style.space(5)
                        implicitHeight: Commons.Style.space(5)
                        radius: width / 2
                        Layout.alignment: Qt.AlignVCenter
                        color: tooltipRow.parked ? "transparent"
                            : (tooltipRow.selected ? Commons.Color.accent
                                : tooltipRow.focused ? Commons.Color.bar.active : Commons.Util.alpha(Commons.Color.tooltip.text, 0.5))
                        border.color: tooltipRow.selected ? Commons.Color.accent
                            : tooltipRow.parked ? Commons.Util.alpha(Commons.Color.tooltip.text, 0.6) : "transparent"
                        border.width: 1
                    }
                    Item {
                        implicitWidth: Commons.Style.space(6)
                        implicitHeight: Commons.Style.space(6)
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            anchors.centerIn: parent
                            text: "›"
                            textFormat: Text.PlainText
                            opacity: tooltipRow.selected ? 1 : 0
                            font.family: Commons.Style.font.family
                            font.pixelSize: Math.max(10, Commons.Style.font.caption - 1)
                            color: Commons.Color.accent
                        }
                    }
                    Text {
                        readonly property string fullLabel: tooltipRow.window ? root.windowLabel(tooltipRow.window) : ""
                        Layout.fillWidth: root.previews
                        Layout.minimumWidth: 0
                        text: fullLabel.length > root.maxLabelLength ? fullLabel.slice(0, root.maxLabelLength - 1) + "…" : fullLabel
                        textFormat: Text.PlainText
                        color: tooltipRow.selected ? Commons.Color.accent
                            : tooltipRow.focused ? Commons.Color.tooltip.text : Commons.Util.alpha(Commons.Color.tooltip.text, 0.80)
                        font.family: Commons.Style.font.family
                        font.pixelSize: Math.max(10, Commons.Style.font.caption - 1)
                        font.bold: tooltipRow.focused
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
        }
    }

    Text {
        visible: !root.previews && root.advanced && root.windows.length > root.maxWindows
        anchors.horizontalCenter: parent.horizontalCenter
        text: "+" + (root.windows.length - root.maxWindows) + " more"
        textFormat: Text.PlainText
        color: Commons.Util.alpha(Commons.Color.tooltip.text, 0.6)
        font.family: Commons.Style.font.family
        font.pixelSize: Math.max(9, Commons.Style.font.caption - 3)
    }
}
