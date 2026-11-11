import QtQuick

BarButton {
    id: root
    property bool popupEnabled: true
    property int selected: 0
    readonly property var records: AgentsUsage.records
    readonly property real highestUsage: {
        let highest = 0
        for (const record of records)
            for (const limit of (record.limits || []))
                highest = Math.max(highest, Number(limit.usageFraction) || 0)
        return highest
    }
    readonly property bool alarming: highestUsage >= panel.alarmUsage
    readonly property bool exhausted: highestUsage >= 1

    css: "agents"
    readonly property bool shown: records.length > 0
    text: exhausted ? "󱚢" : alarming ? "󱚞" : "󱚠"
    onClicked: shell.togglePopup("agents")
    Component.onCompleted: AgentsUsage.consumers++
    Component.onDestruction: AgentsUsage.consumers--

    AgentsPopup {
        id: panel
        anchorItem: root; shell: root.shell; popupEnabled: root.popupEnabled
        records: root.records; selected: root.selected
        onSelect: index => root.selected = index
    }
}
