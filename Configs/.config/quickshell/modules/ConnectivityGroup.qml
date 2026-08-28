import QtQuick
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    css: "connectivity"
    fill: boxColor("fill")
    alwaysOpen: true
    slots: [wifiSlot, bluetoothSlot, disksSlot]

    Component { id: wifiSlot; WifiGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: root.vertical; showVpn: true; vpnFirst: true; alwaysOpen: true } }
    Component { id: bluetoothSlot; BluetoothGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: root.vertical } }
    Component { id: disksSlot; DisksGroup { shell: root.shell; popupsAllowed: root.popupsAllowed; vertical: root.vertical; showPrinters: true; printersFirst: true; alwaysOpen: true } }
}
