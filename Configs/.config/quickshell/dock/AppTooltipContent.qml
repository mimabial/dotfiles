pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

Column {
    id: root
    required property string appName
    property string suffix: ""
    required property var windows
    property bool advanced: true
    property int selectedIndex: -1
    required property var windowFocused
    required property var windowParked
    required property var windowLabel
    spacing: Style.space(3)

    Row {
        spacing: Style.space(4)
        anchors.horizontalCenter: parent.horizontalCenter

        Text {
            text: root.appName
            textFormat: Text.PlainText
            color: Color.tooltip.text
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: root.advanced && root.windows.length > 0
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.suffix !== ""
            text: root.suffix
            textFormat: Text.PlainText
            color: Util.alpha(Color.tooltip.text, 0.80)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Repeater {
        model: root.advanced ? Math.min(root.windows.length, 8) : 0
        delegate: Row {
            id: tooltipRow
            required property int index
            spacing: Style.space(5)
            readonly property var window: root.windows[index]
            readonly property bool selected: root.selectedIndex === index
            readonly property bool focused: root.windowFocused(window)
            readonly property bool parked: root.windowParked(window)

            Rectangle {
                width: Style.space(5)
                height: Style.space(5)
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: tooltipRow.parked ? "transparent"
                    : (tooltipRow.selected ? Color.accent
                        : tooltipRow.focused ? Color.bar.active : Util.alpha(Color.tooltip.text, 0.5))
                border.color: tooltipRow.selected ? Color.accent
                    : tooltipRow.parked ? Util.alpha(Color.tooltip.text, 0.6) : "transparent"
                border.width: 1
            }
            Item {
                width: Style.space(6)
                height: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    anchors.centerIn: parent
                    text: "›"
                    textFormat: Text.PlainText
                    opacity: tooltipRow.selected ? 1 : 0
                    font.family: Style.font.family
                    font.pixelSize: Math.max(10, Style.font.caption - 1)
                    color: Color.accent
                }
            }
            Text {
                readonly property string fullLabel: root.windowLabel(tooltipRow.window)
                text: fullLabel.length > 32 ? fullLabel.slice(0, 30) + "…" : fullLabel
                textFormat: Text.PlainText
                color: tooltipRow.selected ? Color.accent
                    : tooltipRow.focused ? Color.tooltip.text : Util.alpha(Color.tooltip.text, 0.80)
                font.family: Style.font.family
                font.pixelSize: Math.max(10, Style.font.caption - 1)
                font.bold: tooltipRow.focused
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }
    }

    Text {
        visible: root.advanced && root.windows.length > 8
        anchors.horizontalCenter: parent.horizontalCenter
        text: "+" + (root.windows.length - 8) + " more"
        textFormat: Text.PlainText
        color: Util.alpha(Color.tooltip.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Math.max(9, Style.font.caption - 3)
    }
}
