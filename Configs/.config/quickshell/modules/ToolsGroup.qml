pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    shell: root.shell; css: "tools"; Layout.fillWidth: true
    holdOpen: ["converter", "colorpicker"].includes(root.shell.popupName)
    slots: [converterSlot, pickerSlot]

    Component { id: converterSlot; ConverterButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: pickerSlot; ColorPickerButton { shell: root.shell; popupsAllowed: root.popupsAllowed } }
}
