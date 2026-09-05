import QtQuick
import ".."

// A plain launcher: left opens kitty, right opens alacritty.
BarButton {
    id: root
    css: "terminal"
    text: ""
    onClicked: button => shell.run([button === Qt.RightButton ? "alacritty" : "kitty"])
}
