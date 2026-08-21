import QtQuick
import QtQuick.Layouts
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool showMemory: false
    property bool showDisk: false
    property bool showFan: false
    shell: root.shell; css: "info"; Layout.fillWidth: true
    holdOpen: ["gpu", "cpu", "memory", "disk"].includes(root.shell.popupName)
    primary: Component { DmarkModule { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    secondary: Component { ColumnLayout { spacing: 0
        GpuModule    { Layout.fillWidth: true; shell: root.shell; popupsAllowed: root.popupsAllowed }
        CpuModule    { Layout.fillWidth: true; shell: root.shell; popupsAllowed: root.popupsAllowed }
        MemoryModule { Layout.fillWidth: true; visible: root.showMemory; shell: root.shell; popupsAllowed: root.popupsAllowed }
        DiskModule   { Layout.fillWidth: true; visible: root.showDisk;   shell: root.shell; popupsAllowed: root.popupsAllowed }
        FanModule    { Layout.fillWidth: true; visible: root.showFan;    shell: root.shell; popupsAllowed: root.popupsAllowed }
    } }
}
