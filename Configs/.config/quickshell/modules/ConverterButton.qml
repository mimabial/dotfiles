import QtQuick
import ".."

BarButton {
    id: root
    property bool popupsAllowed: true
    css: "converter"; text: ""; tooltip: "Unit & currency converter"
    onClicked: root.shell.togglePopup("converter")
    ConverterPopup { anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed }
}
