import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "dmark"; text: "—"
    textColor: root.shell.role("c7", root.shell.foreground)
}
