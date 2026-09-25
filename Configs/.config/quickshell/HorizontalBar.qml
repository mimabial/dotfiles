pragma ComponentBehavior: Bound

import QtQuick

BarSurface {
    id: root
    readonly property var section: shell.style.box(".modules-left")
    readonly property var layout: shell.barLayout
    readonly property bool onTop: shell.barEdge === "top"
    BarModules { id: moduleCatalog; shell: root.shell; popupsAllowed: root.popupsAllowed }
    readonly property var registry: moduleCatalog.registry
    readonly property var centerModules: layout.center || []
    readonly property int centerAnchorIndex: moduleIndex(centerModules, String(layout.centerAnchor || ""))
    readonly property var centerBeforeModules: centerAnchorIndex < 0 ? [] : centerModules.slice(0, centerAnchorIndex)
    readonly property var centerAnchorModules: centerAnchorIndex < 0 ? [] : [centerModules[centerAnchorIndex]]
    readonly property var centerAfterModules: centerAnchorIndex < 0 ? [] : centerModules.slice(centerAnchorIndex + 1)
    function moduleIndex(modules, id) {
        for (let i = 0; i < modules.length; i++) {
            const entry = modules[i]
            if ((typeof entry === "string" ? entry : String(entry.id || "")) === id) return i
        }
        return -1
    }
    active: (shell.mode === "horizontal" || shell.mode === "winbar") && !shell.userHidden
    anchors.left: true; anchors.right: true; anchors.top: onTop; anchors.bottom: !onTop
    margins.left: floatMargin("left"); margins.right: floatMargin("right")
    margins.top: onTop ? (active ? floatMargin("top") : -implicitHeight) : floatMargin("top")
    margins.bottom: onTop ? floatMargin("bottom") : (active ? floatMargin("bottom") : -implicitHeight)
    implicitHeight: Math.max(leftRow.implicitHeight, centerFallback.implicitHeight, centerBefore.implicitHeight, centerAnchor.implicitHeight, centerAfter.implicitHeight, rightRow.implicitHeight)

    BarSection {
        id: leftRow
        anchors.left: parent.left; anchors.leftMargin: root.section.margin[3] + root.section.padding[3]; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.right: leftRow.stretches ? (root.centerAnchorIndex < 0 ? centerFallback : centerBefore).left : undefined
        registry: root.registry; modules: root.layout.left || []
    }
    BarSection {
        id: centerFallback
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerAnchorIndex < 0 ? root.centerModules : []
    }
    BarSection {
        id: centerBefore
        anchors.right: centerAnchor.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerBeforeModules
    }
    BarSection {
        id: centerAnchor
        anchors.horizontalCenter: parent.horizontalCenter; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerAnchorModules
    }
    BarSection {
        id: centerAfter
        anchors.left: centerAnchor.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; modules: root.centerAfterModules
    }
    BarSection {
        id: rightRow
        anchors.right: parent.right; anchors.rightMargin: root.section.margin[1] + root.section.padding[1]; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.left: rightRow.stretches ? (root.centerAnchorIndex < 0 ? centerFallback : centerAfter).right : undefined
        registry: root.registry; modules: root.layout.right || []
    }

    PopupHost { shell: root.shell; anchorItem: leftRow; popupsAllowed: root.popupsAllowed }
}
