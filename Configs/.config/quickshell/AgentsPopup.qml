import QtQuick

PopupCard {
    id: root
    popupName: "agents"
    contentWidth: Style.px(380)
    contentHeight: agentsColumn.implicitHeight + padding * 2

    property var records: []
    property int selected: 0
    signal select(int index)

    readonly property var provider: records.length ? records[Math.min(selected, records.length - 1)] : null
    // Prefer the subscription whose tightest quota window has the least use.
    // The sum breaks ties, so both the rolling session and weekly allowances
    // affect the answer. Model-scoped limits count too: the busiest matching
    // window is the one that can stop work first.
    readonly property var recommendation: {
        let best = null
        for (const record of records) {
            const hourly = root.windowUsage(record, "hourly")
            const weekly = root.windowUsage(record, "weekly")
            const known = (hourly >= 0 ? 1 : 0) + (weekly >= 0 ? 1 : 0)
            if (known === 0) continue
            const pressure = Math.max(hourly, weekly)
            const total = Math.max(0, hourly) + Math.max(0, weekly)
            const score = pressure + (2 - known)
            if (!best || score < best.score || (score === best.score && total < best.total))
                best = { record: record, hourly: hourly, weekly: weekly, score: score, total: total }
        }
        return best
    }
    readonly property string recommendationId: recommendation ? String(recommendation.record.id || "") : ""
    readonly property string providerSummary: provider ? usageSummary({ hourly: windowUsage(provider, "hourly"), weekly: windowUsage(provider, "weekly") })
        || String(provider.usageStatusText || provider.tierLabel || "") : ""
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
    readonly property string todayDate: Qt.formatDate(shell.clock.date, "yyyy-MM-dd")
    readonly property int dayLabelWidth: Style.px(40)

    function compact(value) {
        const n = Number(value) || 0
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
        return String(Math.round(n))
    }
    function windowKind(limit) {
        const label = String(limit && (limit.label || limit.title) || "").toLowerCase()
        if (label.includes("week") || label.includes("day")) return "weekly"
        if (label.includes("hour") || label.includes("session") || /\d+\s*h\b/.test(label)) return "hourly"
        return ""
    }
    function windowUsage(record, kind) {
        let highest = -1
        for (const limit of (record && record.limits || [])) {
            const reset = Date.parse(limit.resetsAt)
            const expired = !isNaN(reset) && reset <= root.shell.clock.date.getTime()
            const percent = expired ? 0 : Number(limit.percent)
            if (windowKind(limit) === kind && percent >= 0)
                highest = Math.max(highest, Math.min(1, percent))
        }
        return highest
    }
    function usageSummary(choice) {
        if (!choice) return ""
        const parts = []
        if (choice.hourly >= 0) parts.push(Math.round(choice.hourly * 100) + "% 5h used")
        if (choice.weekly >= 0) parts.push(Math.round(choice.weekly * 100) + "% weekly used")
        return parts.join("  ·  ")
    }
    function resetsIn(iso) {
        const target = Date.parse(iso)
        if (isNaN(target)) return ""
        const minutes = Math.max(0, Math.round((target - shell.clock.date.getTime()) / 60000))
        if (minutes >= 1440) return Math.floor(minutes / 1440) + "d " + Math.floor(minutes % 1440 / 60) + "h"
        if (minutes >= 60) return Math.floor(minutes / 60) + "h " + minutes % 60 + "m"
        return minutes + "m"
    }
    onRecommendationIdChanged: {
        if (recommendationId === "") return
        shell.run(["hyprshell", "system/agent-recommendation", recommendationId,
            String(recommendation.record.name || recommendationId), usageSummary(recommendation)])
    }

    Column {
        id: agentsColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sectionGap

        PopupHero {
            shell: root.shell
            title: root.provider ? root.provider.name : "No AI coding subscriptions found"
            status: root.providerSummary
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
                    text: modelData.name + (root.recommendation && root.recommendation.record.id === modelData.id ? "  *" : "")
                    fontSize: Style.bodySmall
                    active: index === root.selected; radius: shell.rounding
                    fill: active ? shell.alpha(shell.role("act_bg", shell.accent), .3) : "transparent"
                    outline: active ? shell.alpha(shell.role("act_br", shell.accent), .65) : "transparent"
                    textColor: index === root.selected ? shell.accent : shell.alpha(shell.foreground, .6)
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
                    width: agentsColumn.width; spacing: Style.md
                    Row {
                        width: parent.width
                        Text {
                            text: String(modelData.label).replace(/\s*\(.*\)\s*$/, ""); color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth); height: 1 }
                        Text {
                            text: Math.round(Number(modelData.percent) * 100) + "%"
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
                    Text {
                        visible: text !== ""
                        width: parent.width
                        text: root.resetsIn(modelData.resetsAt) ? "Resets in " + root.resetsIn(modelData.resetsAt) : ""
                        color: root.shell.alpha(root.shell.foreground, .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
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
                    required property var modelData
                    readonly property bool today: String(modelData.date) === root.todayDate
                    width: agentsColumn.width; spacing: Style.lg
                    Text {
                        width: root.dayLabelWidth
                        text: today ? "Today" : Qt.formatDate(new Date(String(modelData.date) + "T00:00:00"), "ddd")
                        color: root.shell.alpha(root.shell.foreground, today ? .9 : .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: today
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - root.dayLabelWidth - Style.px(56) - Style.lg * 2; height: Style.trackHeight
                        radius: Style.trackHeight / 2; color: root.shell.alpha(root.shell.foreground, .1)
                        Rectangle {
                            width: root.busiestDay > 0 ? parent.width * (Number(modelData.messageCount) / root.busiestDay) : 0
                            height: parent.height; radius: parent.radius
                            color: root.shell.alpha(root.shell.role("act_br", root.shell.accent), today ? 1 : .55)
                        }
                    }
                    Text {
                        width: Style.px(56); horizontalAlignment: Text.AlignRight
                        text: root.compact(modelData.messageCount)
                        color: root.shell.alpha(root.shell.foreground, today ? .9 : .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: today
                    }
                }
            }
        }

        Column {
            visible: root.models.length > 0
            width: parent.width; spacing: Style.md
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "TOKENS BY MODEL" }
            Repeater {
                model: root.models.slice(0, 5)
                Item {
                    id: modelRow
                    required property var modelData
                    width: agentsColumn.width
                    implicitHeight: modelName.implicitHeight + Style.lg

                    Rectangle {
                        anchors.fill: parent; radius: root.shell.rounding
                        color: root.shell.alpha(root.shell.foreground, .05)
                    }
                    Rectangle {
                        anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                        width: root.heaviestModel > 0
                            ? parent.width * Math.min(1, modelRow.modelData.total / root.heaviestModel)
                            : 0
                        radius: root.shell.rounding
                        color: root.shell.alpha(root.shell.foreground, .14)
                    }
                    Text {
                        id: modelName
                        text: modelRow.modelData.name; elide: Text.ElideRight
                        color: root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        anchors.left: parent.left; anchors.leftMargin: Style.lg
                        anchors.right: modelTokens.left; anchors.rightMargin: Style.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id: modelTokens
                        text: root.compact(modelRow.modelData.total)
                        color: root.shell.alpha(root.shell.foreground, .65)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: true
                        anchors.right: parent.right; anchors.rightMargin: Style.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Text {
            visible: root.records.length > 1 && root.recommendation !== null
            width: parent.width
            text: "* Recommended based on 5-hour and weekly limits"
            horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
            color: root.shell.alpha(root.shell.foreground, .55)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
    }
}
