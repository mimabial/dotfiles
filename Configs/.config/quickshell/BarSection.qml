pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var registry
    required property var shell
    required property string sectionName
    property var modules: []
    readonly property var styleBox: shell.style.box(".modules-" + sectionName)
    readonly property real topInset: styleBox.margin[0] + styleBox.padding[0]
    readonly property real rightInset: styleBox.margin[1] + styleBox.padding[1]
    readonly property real bottomInset: styleBox.margin[2] + styleBox.padding[2]
    readonly property real leftInset: styleBox.margin[3] + styleBox.padding[3]
    readonly property real contentCenterOffset: (leftInset - rightInset) / 2
    readonly property bool stretches: modules.some(entry => (entry.id || entry) === "spacer" || !!(entry.props && entry.props.fillAvailableWidth))
    implicitWidth: content.implicitWidth + leftInset + rightInset
    implicitHeight: content.implicitHeight + topInset + bottomInset
    RowLayout {
        id: content
        anchors.fill: parent
        anchors.topMargin: root.topInset; anchors.rightMargin: root.rightInset
        anchors.bottomMargin: root.bottomInset; anchors.leftMargin: root.leftInset
        spacing: root.styleBox.spacing || 0
        Repeater {
            model: root.modules
            delegate: BarModuleLoader { registry: root.registry; shell: root.shell; sectionName: root.sectionName }
        }
    }
}
