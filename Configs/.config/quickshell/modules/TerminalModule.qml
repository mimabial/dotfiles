import QtQuick
import QtQuick.Layouts
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "terminal"; text: ""
    textColor: root.shell.role("c9", root.shell.foreground)
    onClicked: root.shell.run(["kitty"])
}
