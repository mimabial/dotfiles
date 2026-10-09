import QtQuick

BarSurface {
    id: root
    readonly property var layout: shell.barLayout
    readonly property bool onTop: shell.barEdge === "top"
    BarModules {
        id: moduleCatalog
        shell: root.shell; popupsAllowed: root.popupsAllowed
        taskbarAvailableWidth: Math.max(0, rightRow.x - leftRow.x - leftRow.width
            - centerFallback.leftInset - centerFallback.rightInset - centerFallback.widthBesideTaskbar)
    }
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
    function sectionAt(x) {
        if (x < (leftRow.x + leftRow.width + centerStart()) / 2) return "left"
        if (x < (centerEnd() + rightRow.x) / 2) return "center"
        return "right"
    }
    function centerStart() { return centerAnchorIndex < 0 ? centerFallback.x : centerBefore.width ? centerBefore.x : centerAnchor.x }
    function centerEnd() { return centerAnchorIndex < 0 ? centerFallback.x + centerFallback.width : centerAfter.width ? centerAfter.x + centerAfter.width : centerAnchor.x + centerAnchor.width }
    function sectionModules(section) {
        const modules = []
        function collect(item) {
            for (const child of item.children) {
                const module = child as BarModuleLoader
                if (!module) collect(child)
                else if (module.sectionName === section && module.visible)
                    modules.push({ key: module.moduleKey, x: module.mapToItem(root.contentItem, 0, 0).x, width: module.width })
            }
        }
        collect(root.contentItem)
        return modules.sort((a, b) => a.x - b.x)
    }
    function dropPlacement(x) {
        const section = sectionAt(x), modules = sectionModules(section)
        const next = modules.find(module => x < module.x + module.width / 2), last = modules[modules.length - 1]
        return { section, target: next ? next.key : "",
            x: next ? next.x : last ? last.x + last.width : section === "left" ? leftRow.x : section === "center" ? centerStart() : rightRow.x }
    }
    active: shell.barShown
    anchors.left: true; anchors.right: true; anchors.top: onTop; anchors.bottom: !onTop
    margins.left: floatMargin("left"); margins.right: floatMargin("right")
    margins.top: onTop ? (active ? floatMargin("top") : -implicitHeight) : floatMargin("top")
    margins.bottom: onTop ? floatMargin("bottom") : (active ? floatMargin("bottom") : -implicitHeight)
    implicitHeight: Math.max(Style.fontPx(shell.style.box("bar." + shell.barEdge).fontSize) * (shell.style.box("bar." + shell.barEdge).heightEm ?? 0), leftRow.implicitHeight, centerFallback.implicitHeight, centerBefore.implicitHeight, centerAnchor.implicitHeight, centerAfter.implicitHeight, rightRow.implicitHeight)

    BarSection {
        id: leftRow
        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.right: leftRow.stretches ? (root.centerAnchorIndex < 0 ? centerFallback : centerBefore).left : undefined
        registry: root.registry; shell: root.shell; sectionName: "left"; modules: root.layout.left || []
    }
    BarSection {
        id: centerFallback
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: {
            if (root.shell.layoutName !== "winbar") return -centerFallback.contentCenterOffset
            const base = (root.width - centerFallback.width) / 2
            const preferred = base - centerFallback.contentCenterOffset
            return Math.max(leftRow.x + leftRow.width, Math.min(preferred, rightRow.x - centerFallback.width)) - base
        }
        anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; shell: root.shell; sectionName: "center"; modules: root.centerAnchorIndex < 0 ? root.centerModules : []
    }
    BarSection {
        id: centerBefore
        anchors.right: centerAnchor.left; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; shell: root.shell; sectionName: "center"; modules: root.centerBeforeModules
    }
    BarSection {
        id: centerAnchor
        anchors.horizontalCenter: parent.horizontalCenter; anchors.horizontalCenterOffset: -centerAnchor.contentCenterOffset; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; shell: root.shell; sectionName: "center"; modules: root.centerAnchorModules
    }
    BarSection {
        id: centerAfter
        anchors.left: centerAnchor.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        registry: root.registry; shell: root.shell; sectionName: "center"; modules: root.centerAfterModules
    }
    BarSection {
        id: rightRow
        anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.left: rightRow.stretches ? (root.centerAnchorIndex < 0 ? centerFallback : centerAfter).right : undefined
        registry: root.registry; shell: root.shell; sectionName: "right"; modules: root.layout.right || []
    }

    DropArea {
        id: gapTarget
        anchors.fill: parent
        z: -1
        enabled: root.shell.barModules.includes("tray")
        keys: ["bar-module", "tray-module"]
        onDropped: drop => {
            const module = drop.source as BarModuleLoader
            if (!module) return
            const shell = root.shell, key = module.moduleKey, placement = root.dropPlacement(drop.x)
            drop.acceptProposedAction()
            Qt.callLater(() => shell.moveBarModule(key, placement.section, placement.target, false))
        }
    }
    Rectangle {
        visible: gapTarget.containsDrag
        z: 20
        x: Math.max(0, Math.min(root.width - width, root.dropPlacement(gapTarget.drag.x).x))
        width: 2; height: root.height; color: root.shell.accent
    }

    PopupHost { shell: root.shell; anchorItem: leftRow; popupsAllowed: root.popupsAllowed }
}
