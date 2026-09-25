pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

BarSurface {
    id: root
    active: shell.mode === "vertical" && !shell.userHidden
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    margins.top: floatMargin("top"); margins.bottom: floatMargin("bottom")
    margins.left: active ? floatMargin("left") : -implicitWidth
    margins.right: floatMargin("right")
    BarModules { id: moduleCatalog; shell: root.shell; popupsAllowed: root.popupsAllowed }
    readonly property var registry: moduleCatalog.registry
    readonly property var layout: shell.barLayout.modules || []
    readonly property var section: shell.style.box(".modules-left")
    implicitWidth: mainColumn.implicitWidth + section.margin[1] + section.margin[3] + section.padding[1] + section.padding[3]
    ColumnLayout {
        id: mainColumn
        anchors.fill: parent
        anchors.leftMargin: root.section.margin[3] + root.section.padding[3]; anchors.rightMargin: root.section.margin[1] + root.section.padding[1]
        anchors.topMargin: root.section.margin[0] + root.section.padding[0]; anchors.bottomMargin: root.section.margin[2] + root.section.padding[2]
        spacing: 0

        Repeater {
            model: root.layout
            delegate: BarModuleLoader { registry: root.registry; vertical: true }
        }
    }

    PopupHost { shell: root.shell; anchorItem: mainColumn; popupsAllowed: root.popupsAllowed }
}
