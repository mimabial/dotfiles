import QtQuick
import QtQuick.Layouts
import ".."

DrawerGroup {
    id: root
    property bool popupsAllowed: true
    property bool showMemory: true
    property bool showDisk: true
    property bool single: false
    property bool showGpu: true
    shell: root.shell; css: "info"; reverse: true; Layout.fillWidth: true
    holdOpen: ["gpu", "cpu", "memory", "disk"].includes(root.shell.popupName)
    primary: Component { BarButton {
        shell: root.shell; css: "custom-dmark"; text: "—"; fontWeight: Font.Bold
        textColor: root.shell.role("c7", root.shell.foreground)
        tooltip: root.single ? "Show " + (root.showGpu ? "CPU" : "GPU") : ""
        onClicked: button => { if (root.single && button === Qt.LeftButton) root.showGpu = !root.showGpu }
    } }
    secondary: root.single ? singleView : multiView
    Component { id: singleView; Loader { sourceComponent: root.showGpu ? gpuView : cpuView } }
    Component { id: multiView; ColumnLayout { spacing: 0
        Loader { Layout.fillWidth: true; sourceComponent: gpuView }
        Loader { Layout.fillWidth: true; sourceComponent: cpuView }
        Loader { Layout.fillWidth: true; sourceComponent: root.showMemory ? memoryView : null }
        Loader { Layout.fillWidth: true; sourceComponent: root.showDisk ? diskView : null }
    } }
    Component { id: gpuView; GpuModule { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: cpuView; CpuModule { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: memoryView; MemoryModule { shell: root.shell; popupsAllowed: root.popupsAllowed } }
    Component { id: diskView; DiskModule { shell: root.shell; popupsAllowed: root.popupsAllowed } }
}
