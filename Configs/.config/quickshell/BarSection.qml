import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property var registry
    property var modules: []
    spacing: 0
    Repeater {
        model: root.modules
        delegate: Loader {
            required property var modelData
            readonly property string moduleId: typeof modelData === "string" ? modelData : String(modelData.id || "")
            readonly property var moduleProps: typeof modelData === "string" ? null : (modelData.props || null)
            Layout.fillHeight: true
            visible: !item ? true : item.shown !== undefined ? item.shown : item.text !== undefined ? String(item.text) !== "" : true
            sourceComponent: root.registry[moduleId] || null
            onLoaded: if (moduleProps) for (const key in moduleProps) item[key] = moduleProps[key]
        }
    }
}
