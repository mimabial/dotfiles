import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

GridLayout {
    id: root
    required property var shell
    property bool popupsEnabled: true
    property bool vertical: true
    property bool reverse: false
    property bool showAudio: true
    property bool sliderFirst: false
    property bool showNetwork: true
    property bool showPower: true
    property bool showLogout: true
    readonly property var battery: UPower.displayDevice
    columns: vertical ? 1 : 8
    rows: vertical ? 8 : 1
    rowSpacing: 0
    columnSpacing: 0

    DrawerGroup {
        visible: root.showAudio; css: "volumecontrol"; vertical: root.vertical; reverse: root.reverse
        Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
        shell: root.shell
        primary: Component { AudioButton {
            shell: root.shell; framed: root.vertical
            popupEnabled: root.popupsEnabled && root.showAudio
        } }
        secondary: Component { GridLayout { columns: 1; rowSpacing: 0; columnSpacing: 0
            MicrophoneButton {
                shell: root.shell; Layout.fillWidth: true
                Layout.row: root.sliderFirst ? 1 : 0; Layout.column: 0
            }
            VolumeSlider {
                visible: root.vertical; shell: root.shell; Layout.fillWidth: true
                Layout.row: root.sliderFirst ? 0 : 1; Layout.column: 0
            }
        } }
    }
    DrawerGroup {
        visible: root.showNetwork; vertical: root.vertical; reverse: root.reverse
        Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
        shell: root.shell
        primary: Component { NetworkButton {
            shell: root.shell; popupEnabled: root.popupsEnabled && root.showNetwork
        } }
        secondary: Component { BluetoothButton {
            shell: root.shell; popupEnabled: root.popupsEnabled && root.showNetwork
        } }
    }
    DrawerGroup {
        visible: root.showPower; css: "powerconsumption"; vertical: root.vertical; reverse: root.reverse
        Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
        shell: root.shell
        secondaryAvailable: root.battery && root.battery.isPresent && root.battery.energyCapacity > 0
        primary: Component { PowerProfileButton {
            shell: root.shell; popupEnabled: root.popupsEnabled && root.showPower
        } }
        secondary: Component { BatteryButton { shell: root.shell } }
    }
    LogoutButton {
        visible: root.showLogout; shell: root.shell
        Layout.fillWidth: root.vertical; Layout.fillHeight: !root.vertical
    }
}
