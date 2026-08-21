import QtQuick
import QtQuick.Layouts
import ".."

Item {
    required property var shell
    property bool popupsAllowed: true
    property bool pairDrawers: false
    id: connectivityGroup
    readonly property var box: connectivityGroup.shell.style.box("connectivity")
    // "fill"/"outline" read the same way DrawerGroup and BarButton do
    function boxColor(key) {
        const spec = box[key]
        if (!spec) return "transparent"
        return Array.isArray(spec)
            ? connectivityGroup.shell.alpha(connectivityGroup.shell.role(spec[0], connectivityGroup.shell.foreground), spec[1])
            : connectivityGroup.shell.role(spec, connectivityGroup.shell.foreground)
    }
    Layout.fillWidth: true
    implicitHeight: connectivityColumn.implicitHeight + box.margin[0] + box.margin[2] + box.padding[0] + box.padding[2]
    Rectangle {
        anchors.fill: parent
        anchors.topMargin: parent.box.margin[0]; anchors.rightMargin: parent.box.margin[1]
        anchors.bottomMargin: parent.box.margin[2]; anchors.leftMargin: parent.box.margin[3]
        radius: connectivityGroup.shell.moduleRadius
        color: connectivityGroup.boxColor("fill")
        border.color: connectivityGroup.boxColor("outline")
        border.width: connectivityEdge.replacesOutline ? 0 : parent.box.border
    }
    ColumnLayout {
        id: connectivityColumn
        anchors.fill: parent
        anchors.topMargin: parent.box.margin[0] + parent.box.padding[0]
        anchors.rightMargin: parent.box.margin[1] + parent.box.padding[1]
        anchors.bottomMargin: parent.box.margin[2] + parent.box.padding[2]
        anchors.leftMargin: parent.box.margin[3] + parent.box.padding[3]
        spacing: 0

        Loader { Layout.fillWidth: true; active: !connectivityGroup.pairDrawers; sourceComponent: Component { VpnModule { shell: connectivityGroup.shell; popupsAllowed: connectivityGroup.popupsAllowed } } }
        WifiModule { Layout.fillWidth: true; shell: connectivityGroup.shell; popupsAllowed: connectivityGroup.popupsAllowed; showVpn: connectivityGroup.pairDrawers }
        BluetoothModule { Layout.fillWidth: true; shell: connectivityGroup.shell; popupsAllowed: connectivityGroup.popupsAllowed }
        Loader { Layout.fillWidth: true; active: !connectivityGroup.pairDrawers; sourceComponent: Component { PrintersModule { shell: connectivityGroup.shell; popupsAllowed: connectivityGroup.popupsAllowed } } }
        DisksModule { Layout.fillWidth: true; shell: connectivityGroup.shell; popupsAllowed: connectivityGroup.popupsAllowed; showPrinters: connectivityGroup.pairDrawers }
    }
    ModuleEdge { id: connectivityEdge; shell: connectivityGroup.shell }
}
