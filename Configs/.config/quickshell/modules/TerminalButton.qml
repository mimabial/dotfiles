import QtQuick
import ".."

BarButton {
    id: root
    css: "terminal"
    text: ""
    onClicked: button => shell.run([button === Qt.RightButton ? "kitty" : "foot"])
}
