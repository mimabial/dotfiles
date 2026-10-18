import QtQuick
import QtQuick.Layouts
import "../controls"

Item {
    id: view

    property var svc: null
    readonly property var ui: svc ? svc.ui : null
    readonly property real margin: ui.px(14)
    implicitHeight: content.implicitHeight + margin * 2
    clip: true

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: view.margin
        spacing: ui.px(12)

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + ui.px(24)
            radius: ui.cornerRadius(2.5)
            color: ui.tint(0.05)
            border.width: 1
            border.color: ui.tint(0.08)

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.margins: ui.px(12)
                spacing: ui.px(10)

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: ui.px(30); implicitHeight: ui.px(30)
                    radius: ui.cornerRadius(1.5)
                    color: ui.accentTint(0.18)
                    border.width: 1
                    border.color: ui.tint(0.08)
                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 2
                        Repeater {
                            model: 4
                            Rectangle { width: ui.px(6); height: ui.px(5); radius: 1; color: index === 3 ? ui.accent : ui.tint(0.45) }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    Txt {
                        ui: view.ui
                        Layout.fillWidth: true
                        text: view.svc ? view.svc.displayName : ""
                        font.pixelSize: ui.fontPx(13)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Txt {
                        ui: view.ui
                        Layout.fillWidth: true
                        font.pixelSize: ui.fontPx(11)
                        opacity: 0.6
                        elide: Text.ElideRight
                        text: {
                            if (!view.svc) return "Starting…"
                            var n = view.svc.windowCount
                            return n + (n === 1 ? " window" : " windows")
                        }
                    }
                }

                Btn {
                    ui: view.ui
                    Layout.alignment: Qt.AlignVCenter
                    kind: settingsView.confirmReset ? "primary" : "normal"
                    text: settingsView.confirmReset ? "Really reset?" : "Reset all"
                    onClicked: settingsView.resetAll()
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: settingsView.implicitHeight + ui.px(20)
            radius: ui.cornerRadius(2.5)
            color: ui.tint(0.035)
            border.width: 1
            border.color: ui.tint(0.07)
            clip: true

            SettingsView {
                id: settingsView
                anchors.fill: parent
                anchors.margins: ui.px(10)
                svc: view.svc
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: ui.px(8)

            Rectangle {
                implicitWidth: escLabel.implicitWidth + ui.px(12)
                implicitHeight: ui.px(18)
                radius: ui.cornerRadius(1)
                color: ui.tint(0.08)
                Txt { id: escLabel; ui: view.ui; anchors.centerIn: parent; text: "Esc"; font.pixelSize: ui.fontPx(10); opacity: 0.75 }
            }
            Txt { ui: view.ui; text: "close"; font.pixelSize: ui.fontPx(10); opacity: 0.45 }

            Txt {
                ui: view.ui
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: ui.fontPx(10)
                opacity: 0.45
                text: settingsView.changed === 0 ? "All settings are at their defaults"
                    : settingsView.changed + (settingsView.changed === 1 ? " setting differs" : " settings differ") + " from the defaults"
            }
        }
    }
}
