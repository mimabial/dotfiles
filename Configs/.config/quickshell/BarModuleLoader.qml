pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Loader {
    id: root
    required property var modelData
    required property var registry
    property bool vertical: false
    readonly property string moduleId: typeof modelData === "string" ? modelData : String(modelData.id || "")
    readonly property var moduleProps: typeof modelData === "string" ? null : (modelData.props || null)
    readonly property bool spacer: moduleId === "spacer"
    function moduleVisible(module: var): bool {
        if (!module) return true
        if ("shown" in module) return module.shown
        return !("text" in module) || String(module.text) !== ""
    }
    Layout.fillWidth: vertical ? moduleId !== "date" : spacer || !!(moduleProps && moduleProps.fillAvailableWidth)
    Layout.fillHeight: vertical ? spacer : true
    Layout.alignment: vertical && moduleId === "date" ? Qt.AlignHCenter : 0
    visible: moduleVisible(item)
    sourceComponent: spacer ? null : registry[moduleId] || null
    Component.onCompleted: if (!spacer && !registry[moduleId]) console.warn("unknown bar module: " + moduleId)
    onLoaded: if (moduleProps) for (const key in moduleProps) {
        if (!(key in item)) console.warn("unknown bar module prop: " + moduleId + "." + key)
        item[key] = moduleProps[key]
    }
}
