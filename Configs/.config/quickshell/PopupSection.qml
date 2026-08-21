import QtQuick

// Section label inside a popup ("AUDIO", "OUTPUT DEVICE"). Mirrors omarchy's
// PanelSectionHeader: caption weight, darkened rather than faded, and a top
// pad so nerd-font ascenders aren't clipped by a surrounding ListView.
Text {
    id: root
    required property var shell
    color: Qt.darker(shell.foreground, 1.4)
    font.family: shell.fontFamily
    font.pixelSize: Style.caption
    font.bold: true
    topPadding: Math.ceil(font.pixelSize * 0.15)
}
