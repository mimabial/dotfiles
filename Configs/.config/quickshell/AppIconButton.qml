import QtQuick
import Quickshell

BarButton {
    id: root
    property bool useSymbolic: false
    property string icon: root.useSymbolic ? "" : box.icon ?? ""
    readonly property bool shown: root.text !== "" || root.icon !== ""
    Image {
        anchors.centerIn: parent
        width: root.iconBoxPx; height: width
        visible: root.icon !== ""
        source: root.icon ? Quickshell.iconPath(root.icon, true) : ""
        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        smooth: true; mipmap: true
    }
}
