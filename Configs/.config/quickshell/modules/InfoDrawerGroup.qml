pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool showMemory: false
    property bool showDisk: false
    property bool showFan: false
    shell: root.shell; css: "info"; Layout.fillWidth: true
    holdOpen: ["gpu", "cpu", "memory", "disk"].includes(root.shell.popupName)
    slots: [dmarkSlot, gpuSlot, cpuSlot].concat(root.showMemory ? [memorySlot] : [])
        .concat(root.showDisk ? [diskSlot] : []).concat(root.showFan ? [fanSlot] : [])

    Component { id: dmarkSlot;   DmarkButton  { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: gpuSlot;     GpuReadout    { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: cpuSlot;     CpuReadout    { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: memorySlot;  MemoryReadout { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: diskSlot;    DiskReadout   { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: fanSlot;     FanReadout    { shell: root.shell; popupsAllowed: root.popupsAllowed } }
}
