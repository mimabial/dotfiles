import QtQuick

PopupCard {
    id: root
    popupName: "agents"
    contentWidth: 380
    contentHeight: agentsColumn.implicitHeight + padding * 2

    property var records: []
    property int selected: 0
    signal select(int index)

    readonly property var provider: records.length ? records[Math.min(selected, records.length - 1)] : null
    readonly property var limits: provider && provider.limits ? provider.limits : []
    readonly property var days: provider && provider.recentDays ? provider.recentDays : []
    readonly property real busiestDay: {
        let peak = 0
        for (const day of days) peak = Math.max(peak, Number(day.messageCount) || 0)
        return peak
    }
    // modelUsage is keyed by model; each entry splits input/output/cache.
    readonly property var models: {
        const usage = provider && provider.modelUsage ? provider.modelUsage : ({})
        const out = []
        for (const name in usage) {
            const entry = usage[name] || ({})
            out.push({
                name: name,
                total: (Number(entry.inputTokens) || 0) + (Number(entry.outputTokens) || 0)
                    + (Number(entry.cacheCreationInputTokens) || 0) + (Number(entry.cacheReadInputTokens) || 0)
            })
        }
        out.sort((a, b) => b.total - a.total)
        return out
    }
    readonly property real heaviestModel: models.length ? models[0].total : 0

    function compact(value) {
        const n = Number(value) || 0
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
        return String(Math.round(n))
    }
    function resetsIn(iso) {
        const target = Date.parse(iso)
        if (isNaN(target)) return ""
        const minutes = Math.max(0, Math.round((target - Date.now()) / 60000))
        if (minutes >= 1440) return Math.floor(minutes / 1440) + "d " + Math.floor(minutes % 1440 / 60) + "h"
        if (minutes >= 60) return Math.floor(minutes / 60) + "h " + minutes % 60 + "m"
        return minutes + "m"
    }

    Column {
        id: agentsColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupSection { shell: root.shell; text: "AGENTS" }
        Column {
            width: parent.width; spacing: Style.xxs
            Text {
                width: parent.width
                text: root.provider ? root.provider.name : "No AI coding subscriptions found"
                color: root.shell.foreground; font.family: root.shell.fontFamily
                font.pixelSize: Style.title; font.bold: true; elide: Text.ElideRight
            }
            Text {
                visible: text !== ""
                width: parent.width
                text: root.provider ? (String(root.provider.usageStatusText || "") || String(root.provider.tierLabel || "")) : ""
                color: root.shell.alpha(root.shell.foreground, .6)
                font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; elide: Text.ElideRight
            }
        }

        // Subscription switch — only when more than one agent reports usage.
        Row {
            visible: root.records.length > 1
            width: parent.width; spacing: Style.xs
            Repeater {
                model: root.records
                BarButton {
                    required property int index; required property var modelData
                    shell: root.shell
                    implicitWidth: (agentsColumn.width - Style.xs * (root.records.length - 1)) / root.records.length
                    implicitHeight: Style.controlHeight
                    text: modelData.name
                    fontSize: Style.bodySmall
                    active: index === root.selected
                    onClicked: root.select(index)
                }
            }
        }

        Column {
            visible: root.limits.length > 0
            width: parent.width; spacing: Style.md
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "LIMITS" }
            Repeater {
                model: root.limits
                Column {
                    required property var modelData
                    width: agentsColumn.width; spacing: Style.xxs
                    Row {
                        width: parent.width
                        Text {
                            text: modelData.label; color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth); height: 1 }
                        Text {
                            text: Math.round(Number(modelData.percent) * 100) + "%"
                                + (root.resetsIn(modelData.resetsAt) ? "  ·  " + root.resetsIn(modelData.resetsAt) : "")
                            color: root.shell.alpha(root.shell.foreground, .65)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                    }
                    Rectangle {
                        width: parent.width; height: Style.trackHeight; radius: Style.trackHeight / 2
                        color: root.shell.alpha(root.shell.foreground, .12)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, Number(modelData.percent)))
                            height: parent.height; radius: parent.radius
                            color: Number(modelData.percent) >= 0.9
                                ? root.shell.role("error", root.shell.accent)
                                : root.shell.role("act_br", root.shell.accent)
                        }
                    }
                }
            }
        }

        Column {
            visible: root.days.length > 0
            width: parent.width; spacing: Style.xs
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "TOKENS BY DAY" }
            Repeater {
                model: root.days
                Row {
                    required property int index; required property var modelData
                    readonly property bool today: index === root.days.length - 1
                    width: agentsColumn.width; spacing: Style.lg
                    Text {
                        width: 32; text: Qt.formatDate(new Date(modelData.date), "ddd")
                        color: root.shell.alpha(root.shell.foreground, today ? .9 : .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: today
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 32 - 56 - Style.lg * 2; height: Style.trackHeight
                        radius: Style.trackHeight / 2; color: root.shell.alpha(root.shell.foreground, .1)
                        Rectangle {
                            width: root.busiestDay > 0 ? parent.width * (Number(modelData.messageCount) / root.busiestDay) : 0
                            height: parent.height; radius: parent.radius
                            color: root.shell.alpha(root.shell.role("act_br", root.shell.accent), today ? 1 : .55)
                        }
                    }
                    Text {
                        width: 56; horizontalAlignment: Text.AlignRight
                        text: root.compact(modelData.messageCount)
                        color: root.shell.alpha(root.shell.foreground, today ? .9 : .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: today
                    }
                }
            }
        }

        Column {
            visible: root.models.length > 0
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "TOKENS BY MODEL" }
            Repeater {
                model: root.models.slice(0, 5)
                // name and total on one line, the bar on its own beneath: model
                // names are long, and the bar used to be drawn inside the text's
                // line box, which left it colliding with the descenders
                Column {
                    required property var modelData
                    width: agentsColumn.width; spacing: 3
                    Row {
                        width: parent.width; spacing: Style.lg
                        Text {
                            width: parent.width - 56 - Style.lg
                            text: parent.parent.modelData.name; elide: Text.ElideRight
                            color: root.shell.alpha(root.shell.foreground, .8)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                        Text {
                            width: 56; horizontalAlignment: Text.AlignRight
                            text: root.compact(parent.parent.modelData.total)
                            color: root.shell.alpha(root.shell.foreground, .65)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                        }
                    }
                    Rectangle {
                        width: parent.width; height: Style.trackHeight
                        radius: Style.trackHeight / 2
                        color: root.shell.alpha(root.shell.foreground, .1)
                        Rectangle {
                            width: root.heaviestModel > 0 ? parent.width * (parent.parent.modelData.total / root.heaviestModel) : 0
                            height: parent.height; radius: parent.radius
                            color: root.shell.alpha(root.shell.role("act_br", root.shell.accent), .55)
                        }
                    }
                }
            }
        }
    }
}
