import QtQuick
import QtQuick.Layouts
import "../controls"

Item {
    id: root

    property var ui: null
    property string settingKey: ""
    property string label: ""
    property string hint: ""
    required property string kind
    property string control: ""
    property var options: []
    property var labels: ({})
    property var value: null

    property var optimistic: undefined
    readonly property var current: optimistic !== undefined ? optimistic : value
    onValueChanged: optimistic = undefined
    function commit(v) { if (enabled) { optimistic = v; edited(v) } }
    property var defaultValue: null
    property bool dimmed: false

    signal edited(var v)

    function asText(v) { return (v === null || v === undefined) ? "" : String(v) }
    function same(a, b) { return asText(a) === asText(b) }
    function labelFor(opt) { return labels[opt] !== undefined ? labels[opt] : String(opt) }

    readonly property string mode: kind !== "enum" ? ""
        : (control !== "" ? control : "seg")
    readonly property bool boolValue: current === true || current === "true"
    readonly property bool atDefault: same(current, defaultValue)

    implicitWidth: 400
    implicitHeight: col.implicitHeight
    enabled: !dimmed
    opacity: dimmed ? 0.4 : 1.0
    Behavior on opacity { enabled: ui.animations; NumberAnimation { duration: 140 } }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: ui.px(14)

        RowLayout {
            Layout.fillWidth: true
            spacing: ui.px(10)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: root.label
                    font.pixelSize: ui.fontPx(13)
                    font.weight: Font.DemiBold
                }
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    visible: root.hint !== ""
                    text: root.hint
                    font.pixelSize: ui.fontPx(10)
                    opacity: 0.55
                    wrapMode: Text.Wrap
                }
            }

            Rectangle {
                visible: !root.atDefault
                implicitWidth: ui.px(24); implicitHeight: ui.px(24)
                radius: root.ui.cornerRadius(0.5)
                color: ui.tint(resetArea.containsMouse ? 0.18 : 0.08)
                Txt { ui: root.ui; anchors.centerIn: parent; text: "\u21BA"; font.pixelSize: ui.fontPx(12) }
                MouseArea {
                    id: resetArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.commit(root.defaultValue)
                }
            }

            Sw {
                ui: root.ui
                Layout.alignment: Qt.AlignVCenter
                visible: root.kind === "bool"
                k: ui.px(1)
                animate: ui.animations
                ink: ui.fg; accent: ui.accent; knob: ui.accentText
                on: root.boolValue
                onFlipped: root.commit(!root.boolValue)
            }
        }

        GridLayout {
            Layout.fillWidth: true
            visible: root.mode === "tiles"
            columns: 2
            columnSpacing: ui.px(10)
            rowSpacing: ui.px(10)

            Repeater {
                model: root.mode === "tiles" ? root.options : []
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    id: tile
                    readonly property bool on: root.same(root.current, modelData)
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: ui.px(84)
                    radius: root.ui.cornerRadius(1.4)
                    color: on ? ui.accentTint(0.16) : ui.tint(tArea.containsMouse ? 0.09 : 0.04)
                    border.width: on ? 1.5 : 1
                    border.color: on ? ui.accent : ui.tint(0.08)
                    Behavior on color { enabled: ui.animations; ColorAnimation { duration: 100 } }

                    TileArt {
                        ui: root.ui
                        key: root.settingKey
                        opt: String(modelData)
                        on: tile.on
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: ui.px(12)
                    }
                    Txt {
                        ui: root.ui
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: ui.px(9)
                        width: parent.width - ui.px(12)
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.labelFor(modelData)
                        font.pixelSize: ui.fontPx(10)
                        font.weight: tile.on ? Font.DemiBold : Font.Normal
                        opacity: tile.on ? 1.0 : 0.75
                    }
                    MouseArea {
                        id: tArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commit(modelData)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            visible: root.mode === "seg"
            implicitHeight: ui.px(38)
            radius: root.ui.cornerRadius(1.4)
            color: ui.tint(0.05)
            border.width: 1
            border.color: ui.tint(0.08)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 2

                Repeater {
                    model: root.mode === "seg" ? root.options : []
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: root.same(root.current, modelData)
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        radius: root.ui.cornerRadius(1.1)
                        color: on ? ui.accent : (sArea.containsMouse ? ui.tint(0.08) : "transparent")
                        Behavior on color { enabled: ui.animations; ColorAnimation { duration: 90 } }
                        Txt {
                            ui: root.ui
                            anchors.centerIn: parent
                            width: parent.width - ui.px(8)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: root.labelFor(modelData)
                            color: parent.on ? ui.accentText : ui.fg
                            font.pixelSize: ui.fontPx(11)
                            font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: sArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.commit(modelData)
                        }
                    }
                }
            }
        }

    }
}
