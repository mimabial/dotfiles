pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import ".."

BarButton {
    id: root
    readonly property real dotToIconRatio: 0.5
    readonly property real dotSize: Math.round(symbolSize * dotToIconRatio)
    readonly property real inactiveDotScale: 0.75
    readonly property real inactiveDotOpacity: 0.5
    readonly property var activeDotWidthSteps: [{ maxDots: 2, multiplier: 3.625 }, { maxDots: 5, multiplier: 3.25 }, { maxDots: Infinity, multiplier: 2.75 }]
    readonly property int workspaceSwitchDuration: Style.duration(250)
    readonly property int dotScaleInDuration: Style.duration(500)
    readonly property var workspaces: Hyprland.workspaces.values.filter(workspace => workspace.id > 0).sort((a, b) => a.id - b.id)
    readonly property var lastWorkspace: workspaces[workspaces.length - 1] ?? null
    readonly property bool endsWithEmptyWorkspace: !!lastWorkspace && lastWorkspace.toplevels.values.length === 0
    readonly property var dotIds: workspaces.map(workspace => workspace.id).concat(endsWithEmptyWorkspace ? [] : [(lastWorkspace?.id ?? 0) + 1])
    readonly property int activeIndex: dotIds.indexOf(Hyprland.focusedWorkspace?.id ?? -1)
    readonly property real activeDotWidthMultiplier: activeDotWidthSteps.find(step => dotIds.length <= step.maxDots).multiplier
    property real activePosition: activeIndex
    Behavior on activePosition { NumberAnimation { duration: root.workspaceSwitchDuration; easing.type: Easing.OutCubic } }
    function lerp(from, to, progress) { return from + (to - from) * progress }
    function syncDotSlots() {
        while (dotSlots.count < dotIds.length) dotSlots.append({})
        while (dotSlots.count > dotIds.length) dotSlots.remove(dotSlots.count - 1)
    }
    function stepWorkspace(direction) {
        const target = dotIds[Math.max(0, Math.min(dotIds.length - 1, activeIndex + direction))]
        if (target !== Hyprland.focusedWorkspace?.id) Hyprland.dispatch('hl.dsp.focus({ workspace = "' + target + '" })')
    }
    onDotIdsChanged: syncDotSlots()
    Component.onCompleted: syncDotSlots()
    css: "gnome-activities"
    text: ""
    tooltip: "Activities"
    trailingWidth: dots.implicitWidth
    active: !!shell.expose?.opened
    onClicked: shell.expose?.toggle()
    onWheeled: delta => stepWorkspace(delta > 0 ? -1 : 1)
    ListModel { id: dotSlots }
    Row {
        id: dots
        anchors.centerIn: parent
        spacing: Style.sm
        Repeater {
            model: dotSlots
            Rectangle {
                required property int index
                readonly property real expansion: Math.max(0, Math.min(1, 1 - Math.abs(index - root.activePosition)))
                readonly property bool urgent: !!root.workspaces.find(workspace => workspace.id === root.dotIds[index])?.urgent
                property real appearance
                NumberAnimation on appearance { from: 0; to: 1; duration: root.dotScaleInDuration; easing.type: Easing.OutCubic }
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(root.dotSize * root.lerp(1, root.activeDotWidthMultiplier, expansion))
                height: root.dotSize; radius: height / 2
                scale: root.lerp(root.inactiveDotScale, 1, expansion) * appearance
                opacity: root.lerp(root.inactiveDotOpacity, 1, expansion)
                color: urgent ? root.shell.role("warning", root.shell.foreground) : root.contentColor
            }
        }
    }
}
