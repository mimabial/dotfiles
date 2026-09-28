pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Loader {
    id: root
    required property var modelData
    required property var registry
    required property var shell
    required property string sectionName
    property bool hosted: false
    readonly property var moduleEntry: hosted ? modelData.entry : modelData
    readonly property string moduleId: typeof moduleEntry === "string" ? moduleEntry : String(moduleEntry.id || "")
    readonly property string moduleKey: shell.trayKey(sectionName, moduleEntry)
    readonly property var moduleProps: typeof moduleEntry === "string" ? null : (moduleEntry.props || null)
    readonly property bool spacer: moduleId === "spacer"
    readonly property bool customSource: !registry[moduleId] && !!moduleEntry.source
    function moduleVisible(module: var): bool {
        if (!module) return true
        if ("shown" in module) return module.shown
        return !("text" in module) || String(module.text) !== ""
    }
    Layout.fillWidth: spacer || !!(moduleProps && moduleProps.fillAvailableWidth)
    Layout.fillHeight: true
    visible: moduleVisible(item)
    sourceComponent: spacer || customSource ? null : registry[moduleId] || (moduleEntry.exec ? commandModule : null)
    Component.onCompleted: {
        if (customSource) setSource(Qt.resolvedUrl(moduleEntry.source), Object.assign({ shell }, moduleProps || {}))
        else if (!spacer && !sourceComponent) console.warn("unknown bar module: " + moduleId)
    }
    onLoaded: if (moduleProps && !customSource) for (const key in moduleProps) {
        if (!(key in item)) console.warn("unknown bar module prop: " + moduleId + "." + key)
        item[key] = moduleProps[key]
    }
    Component {
        id: commandModule
        ScriptButton {
            shell: root.shell
            command: Array.isArray(root.moduleEntry.exec) ? root.moduleEntry.exec : ["/bin/sh", "-lc", String(root.moduleEntry.exec)]
            interval: root.moduleEntry.interval || 60000
            polling: root.moduleEntry.polling !== false
            Component.onCompleted: if (!polling) refresh()
        }
    }
    DragHandler {
        id: handle
        target: null
        enabled: !root.spacer && root.moduleId !== "tray" && root.item !== null && root.shell.barModules.includes("tray")
        dragThreshold: 8
        onActiveChanged: {
            if (active) { root.shell.dragKey = root.moduleKey; marker.Drag.active = true }
            else {
                if (marker.Drag.active) marker.Drag.drop()
                if (root.shell.dragKey === root.moduleKey) root.shell.dragKey = ""
            }
        }
    }
    Component.onDestruction: if (shell.dragKey === moduleKey) shell.dragKey = ""
    Item {
        id: marker
        width: 1; height: 1
        x: handle.centroid.position.x
        y: handle.centroid.position.y
        Drag.source: root
        Drag.keys: [root.hosted ? "tray-module" : "bar-module"]
        Drag.proposedAction: Qt.MoveAction
        Rectangle {
            anchors.centerIn: parent
            visible: handle.active
            width: Math.min(160, label.implicitWidth + 16); height: label.implicitHeight + 8
            radius: 4; color: root.shell.alpha(root.shell.background, .94)
            border.color: root.shell.accent
            Text { id: label; anchors.centerIn: parent; text: root.moduleId; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: 11 }
        }
    }
    DropArea {
        id: barTarget
        anchors.fill: parent
        z: 10
        enabled: !root.hosted && !root.spacer && root.moduleId !== "tray" && root.shell.layoutName === "winbar"
        keys: ["bar-module", "tray-module"]
        onDropped: drop => {
            const source = drop.source as BarModuleLoader
            if (!source || source.moduleKey === root.moduleKey) return
            const shell = root.shell, key = source.moduleKey, section = root.sectionName
            const target = root.moduleKey, after = drop.x >= width / 2
            drop.acceptProposedAction()
            Qt.callLater(() => shell.moveBarModule(key, section, target, after))
        }
        Rectangle {
            visible: barTarget.containsDrag
            x: barTarget.drag.x >= barTarget.width / 2 ? parent.width - width : 0
            width: 2; height: parent.height; color: root.shell.accent
        }
    }
}
