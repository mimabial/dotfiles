pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    required property var registry
    required property var shell
    required property string sectionName
    property var modules: []
    onModulesChanged: syncSlots()
    Component.onCompleted: syncSlots()
    // keyed by the serialized entry, so a layout write keeps every module it did not
    // touch alive, along with any popup that module has open
    function syncSlots() {
        const keys = modules.map(entry => JSON.stringify(entry))
        for (let i = 0; i < keys.length; i++) {
            let j = i
            while (j < slots.count && slots.get(j).key !== keys[i]) j++
            if (j === slots.count) slots.insert(i, { key: keys[i] })
            else if (j > i) slots.move(j, i, 1)
        }
        if (slots.count > keys.length) slots.remove(keys.length, slots.count - keys.length)
    }
    ListModel { id: slots }
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
            model: slots
            delegate: BarModuleLoader { required property string key; modelData: JSON.parse(key); registry: root.registry; shell: root.shell; sectionName: root.sectionName }
        }
    }
}
