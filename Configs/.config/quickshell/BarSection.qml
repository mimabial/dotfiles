pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var registry
    required property var shell
    required property string sectionName
    property var modules: []
    onModulesChanged: preserveModuleInstances()
    Component.onCompleted: preserveModuleInstances()
    function preserveModuleInstances() {
        const entryKeys = modules.map(entry => JSON.stringify(entry))
        for (let targetIndex = 0; targetIndex < entryKeys.length; targetIndex++) {
            let existingIndex = targetIndex
            while (existingIndex < moduleInstances.count && moduleInstances.get(existingIndex).key !== entryKeys[targetIndex]) existingIndex++
            if (existingIndex === moduleInstances.count) moduleInstances.insert(targetIndex, { key: entryKeys[targetIndex] })
            else if (existingIndex > targetIndex) moduleInstances.move(existingIndex, targetIndex, 1)
        }
        if (moduleInstances.count > entryKeys.length) moduleInstances.remove(entryKeys.length, moduleInstances.count - entryKeys.length)
    }
    ListModel { id: moduleInstances }
    readonly property var styleBox: shell.style.box(".modules-" + sectionName)
    readonly property real topInset: styleBox.margin[0] + styleBox.padding[0]
    readonly property real rightInset: styleBox.margin[1] + styleBox.padding[1]
    readonly property real bottomInset: styleBox.margin[2] + styleBox.padding[2]
    readonly property real leftInset: styleBox.margin[3] + styleBox.padding[3]
    readonly property real contentCenterOffset: (leftInset - rightInset) / 2
    readonly property bool stretches: modules.some(entry => (entry.id || entry) === "spacer" || !!(entry.props && entry.props.fillAvailableWidth))
    readonly property real widthBesideTaskbar: Array.from(content.children)
        .filter(child => "moduleId" in child && child.moduleId !== "taskbar" && child.visible)
        .reduce((width, child) => width + child.implicitWidth + content.spacing, 0)
    implicitWidth: content.implicitWidth + leftInset + rightInset
    implicitHeight: content.implicitHeight + topInset + bottomInset
    RowLayout {
        id: content
        anchors.fill: parent
        anchors.topMargin: root.topInset; anchors.rightMargin: root.rightInset
        anchors.bottomMargin: root.bottomInset; anchors.leftMargin: root.leftInset
        spacing: root.styleBox.spacing || 0
        Repeater {
            model: moduleInstances
            delegate: BarModuleLoader { required property string key; modelData: JSON.parse(key); registry: root.registry; shell: root.shell; sectionName: root.sectionName }
        }
    }
}
