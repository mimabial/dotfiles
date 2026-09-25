pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root
    required property var registry
    property var modules: []
    readonly property bool stretches: modules.some(entry => (entry.id || entry) === "spacer" || !!(entry.props && entry.props.fillAvailableWidth))
    spacing: 0
    Repeater {
        model: root.modules
        delegate: BarModuleLoader { registry: root.registry }
    }
}
