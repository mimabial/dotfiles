pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Dialogs
import org.kde.kdeconnect as KDEConnect

Item {
    id: root
    required property var shell
    property string selectedDevice: ""
    property var selectedFiles: []
    readonly property alias reachableDevices: reachable
    readonly property var reachableIds: Array.from({length: reachable.count},
        (_, row) => reachable.data(reachable.index(row, 0), KDEConnect.DevicesModel.IdModelRole))
    readonly property string recipient: reachableIds.includes(selectedDevice) ? selectedDevice
        : reachableIds.length === 1 ? reachableIds[0] : ""

    function pickFiles() {
        shell.closePopup()
        picker.open()
    }
    function send() {
        KDEConnect.ShareDbusInterfaceFactory.create(recipient).shareUrls(selectedFiles)
        selectedFiles = []
    }
    function refresh() { KDEConnect.DaemonDbusInterface.forceOnNetworkChange() }
    function openDevices() {
        shell.closePopup()
        shell.run(["hyprshell", "app", "--", "kdeconnect-app"])
    }

    KDEConnect.DevicesModel { id: reachable; displayFilter: KDEConnect.DevicesModel.Paired | KDEConnect.DevicesModel.Reachable }
    FileDialog {
        id: picker; title: "Send files"; fileMode: FileDialog.OpenFiles
        onAccepted: { root.selectedFiles = Array.from(picker.selectedFiles, String); root.shell.togglePopup("kdeconnect") }
    }
}
