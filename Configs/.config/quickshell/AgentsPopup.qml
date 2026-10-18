pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "systemstats/ui" as Stats
import "CalendarMath.js" as CalendarMath
import "Units.js" as Units

PopupCard {
    id: root
    readonly property real alarmUsage: 0.9
    popupName: "agents"
    keyboardHint: "↑↓/Tab move · Enter details · R refresh · Esc close"
    contentWidth: Style.px(380)
    contentHeight: agentsViewport.height + padding * 2

    property var records: []
    property string activeTab: "limits"
    property int costPeriod: 7
    onActiveTabChanged: { agentsViewport.contentY = 0; clearCursor(); rebuildRows() }
    onCostPeriodChanged: { agentsViewport.contentY = 0; clearCursor(); rebuildRows() }
    property int selected: 0
    property string expandedProviderId: ""
    property string recommendationId: ""
    property var notificationSettings: ({notifyRecommendation: false, notifyLimit: false})
    readonly property bool notifyLimit: notificationSettings.notifyLimit === true
    signal select(int index)
    signal refreshRequested()
    signal limitNotificationsEnabled()
    onNotifyLimitChanged: if (notifyLimit) limitNotificationsEnabled()

    readonly property int blockingHorizonMs: 5 * CalendarMath.MS_PER_HOUR
    readonly property int staleAfterMs: 40 * CalendarMath.MS_PER_MINUTE
    readonly property int viewportHeight: Style.px(520)
    readonly property real switchMargin: 0.05

    readonly property var provider: records.length ? records[Math.min(selected, records.length - 1)] : null
    readonly property bool isOpenCode: provider !== null && provider.id === "opencode"
    readonly property var providerUsage: isOpenCode ? provider.providerUsage || [] : []
    readonly property bool telemetryStale: records.some(record => record.id !== "opencode" &&
        (record.limits || []).length && Date.now() - (Number(record.limitsObservedAt) || 0) > staleAfterMs)
    readonly property var candidate: records.filter(record => record.id !== "opencode").map(rank).reduce((best, scored) =>
        scored && (!best || better(scored, best, 0)) ? scored : best, null)

    readonly property string providerSummary: provider
        ? (isOpenCode ? String(provider.usageStatusText || "")
            : usageSummary(provider) || String(provider.usageStatusText || provider.tierLabel || "")) : ""
    readonly property var limits: provider && provider.limits ? provider.limits : []
    readonly property var days: provider && provider.recentDays ? provider.recentDays : []
    readonly property real recentTotal: days.reduce((total, day) => total + (Number(day.tokenCount) || 0), 0)
    readonly property real providerWeekTotal: providerUsage.reduce((total, entry) => total + (Number(entry.tokensWeek) || 0), 0)
    readonly property real busiestDay: {
        let peak = 0
        for (const day of days) peak = Math.max(peak, Number(day.tokenCount) || 0)
        return peak
    }
    readonly property var models: {
        const usage = provider && provider.modelUsage ? provider.modelUsage : ({})
        const out = []
        for (const name in usage) {
            const entry = usage[name] || ({})
            out.push({
                name: name,
                total: (Number(entry.totalTokens) || 0) + (Number(entry.inputTokens) || 0) + (Number(entry.outputTokens) || 0)
                    + (Number(entry.cacheCreationInputTokens) || 0) + (Number(entry.cacheReadInputTokens) || 0)
            })
        }
        out.sort((a, b) => b.total - a.total)
        return out
    }
    readonly property real heaviestModel: models.length ? models[0].total : 0
    readonly property string todayDate: Qt.formatDate(shell.clock.date, "yyyy-MM-dd")

    function compact(value) {
        const n = Number(value) || 0
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "K"
        return String(Math.round(n))
    }
    function rank(record) {
        const now = Date.now()
        let pressure = -1, load = 0, blockedFor = 0
        for (const limit of (record.limits || [])) {
            const reset = Date.parse(limit.resetsAt)
            const clearsIn = isNaN(reset) ? root.blockingHorizonMs : Math.max(0, reset - now)
            const used = clearsIn > 0 ? Math.min(1, Number(limit.usageFraction)) : 0
            if (!(used >= 0)) continue
            pressure = Math.max(pressure, used * Math.min(1, clearsIn / root.blockingHorizonMs))
            load += used
            if (used >= 1) blockedFor = Math.max(blockedFor, clearsIn)
        }
        return pressure < 0 ? null : { record: record, blockedFor: blockedFor, pressure: pressure, load: load }
    }
    function better(a, b, margin) {
        if (a.blockedFor !== b.blockedFor) return a.blockedFor < b.blockedFor
        if (a.pressure !== b.pressure) return a.pressure + margin < b.pressure
        return a.load + margin < b.load
    }
    function limitName(limit) { return String(limit.label).replace(/\s*\(.*\)\s*$/, "") }
    function usageSummary(record) {
        const parts = []
        for (const limit of (record && record.limits || []))
            if (Number(limit.usageFraction) >= 0)
                parts.push(Math.round(Number(limit.usageFraction) * 100) + "% " + limitName(limit))
        return parts.join("  ·  ")
    }
    function resetsIn(iso) {
        const target = Date.parse(iso)
        if (isNaN(target)) return ""
        const minutes = Math.max(0, Math.round((target - shell.clock.date.getTime()) / CalendarMath.MS_PER_MINUTE))
        return Units.spanText(minutes * Units.SECONDS_PER_MINUTE) || "0m"
    }
    function handleKey(event) {
        if (event.key === Qt.Key_R) { refreshRequested(); return true }
        return defaultKey(event)
    }
    function setNotification(key, enabled) {
        const next = Object.assign({}, notificationSettings, {[key]: enabled})
        notificationSettingsFile.setText(JSON.stringify(next, null, 2) + "\n")
        notificationSettings = next
    }
    onCandidateChanged: {
        if (!candidate) return
        const held = recommendationId ? records.find(record => String(record.id) === recommendationId) : null
        const heldRank = held ? rank(held) : null
        if (heldRank && (telemetryStale || !better(candidate, heldRank, switchMargin))) return
        recommendationId = String(candidate.record.id || "")
    }
    onRecommendationIdChanged: {
        const record = records.find(entry => String(entry.id) === recommendationId)
        if (record) shell.run(["hyprshell", "system/agent-recommendation", recommendationId,
            String(record.name || recommendationId), usageSummary(record)])
    }

    FileView {
        id: notificationSettingsFile
        path: root.shell.home + "/.config/quickshell/agents.json"
        watchChanges: true; atomicWrites: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                root.notificationSettings = {
                    notifyRecommendation: saved.notifyRecommendation === true,
                    notifyLimit: saved.notifyLimit === true
                }
            } catch (error) { root.notificationSettings = ({notifyRecommendation: false, notifyLimit: false}) }
        }
    }

    Flickable {
        id: agentsViewport
        width: parent.width
        height: Math.max(0, Math.min(root.viewportHeight,
            root.anchorWindow ? root.maxHeight - root.padding * 2 - root.keyboardHintHeight : root.viewportHeight))
        contentHeight: agentsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: agentsColumn
            width: agentsViewport.width; spacing: Style.sectionGap

        Row {
            width: parent.width; spacing: Style.sm
            Repeater {
                model: ["limits", "costs"]
                PopupTab {
                    required property string modelData
                    width: (agentsColumn.width - Style.sm) / 2
                    shell: root.shell; text: modelData
                    selected: root.activeTab === modelData
                    onClicked: root.activeTab = modelData
                }
            }
        }

        AgentCosts { visible: root.activeTab === "costs"; width: parent.width; popup: root }

        Column {
            visible: root.activeTab === "limits"
            width: parent.width; spacing: Style.sectionGap

        PopupHero {
            shell: root.shell
            title: root.provider ? root.provider.name : "No AI coding subscriptions found"
            status: root.providerSummary
        }

        Row {
            visible: root.records.length > 1
            width: parent.width; spacing: Style.sm
            Repeater {
                model: root.records
                PopupTab {
                    required property int index; required property var modelData
                    width: (agentsColumn.width - Style.sm * (root.records.length - 1)) / root.records.length
                    shell: root.shell
                    text: ({claude: "Claude", kimi: "Kimi"}[modelData.id] || modelData.name) + (root.recommendationId === String(modelData.id) ? "  *" : "")
                    selected: index === root.selected
                    onClicked: root.select(index)
                }
            }
        }
        Column {
            visible: root.limits.length > 0
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: root.isOpenCode ? "GO LIMITS" : "LIMITS" }
            Repeater {
                model: root.limits
                Column {
                    id: limitRow
                    required property var modelData
                    width: agentsColumn.width; spacing: Style.md
                    Row {
                        width: parent.width
                        Text {
                            id: limitName
                            text: root.limitName(limitRow.modelData) + (root.isOpenCode && Number(limitRow.modelData.limitDollars) > 0
                                ? " · $" + Number(limitRow.modelData.limitDollars).toFixed(0) : "")
                            color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                        Item { width: Math.max(0, parent.width - limitName.implicitWidth - limitPercent.implicitWidth); height: 1 }
                        Text {
                            id: limitPercent
                            text: Math.round(Number(limitRow.modelData.usageFraction) * 100) + "%"
                            color: root.shell.mutedText
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                    }
                    Rectangle {
                        width: parent.width; height: Style.trackHeight; radius: Style.trackHeight / 2
                        color: root.shell.alpha(root.shell.foreground, .12)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, Number(limitRow.modelData.usageFraction)))
                            height: parent.height; radius: parent.radius
                            color: Number(limitRow.modelData.usageFraction) >= root.alarmUsage
                                ? root.shell.role("error", root.shell.accent)
                                : root.shell.role("act_br", root.shell.accent)
                        }
                    }
                    Text {
                        readonly property string untilReset: root.open ? root.resetsIn(limitRow.modelData.resetsAt) : ""
                        visible: untilReset !== ""
                        width: parent.width
                        text: "Resets in " + untilReset
                        color: root.shell.mutedText
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }
        }

        Column {
            visible: root.providerUsage.length > 0
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "PROVIDERS" }
            Repeater {
                model: root.providerUsage
                delegate: ProviderUsageRow { popup: root; width: agentsColumn.width }
            }
        }

        Text {
            visible: root.isOpenCode && !!root.provider.goStatus
            width: parent.width; text: root.provider ? String(root.provider.goStatus || "") : ""
            color: root.shell.mutedText
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }

        Column {
            visible: root.days.length > 0
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "RECENT USAGE · " + root.compact(root.recentTotal) + " TOKENS" }
            Canvas {
                id: recentChart
                width: agentsColumn.width; height: Style.px(72)
                antialiasing: true
                readonly property var values: root.days.map(day => Number(day.tokenCount) || 0)
                readonly property color lineColor: root.shell.foreground
                readonly property color peakColor: root.shell.role("act_br", root.shell.accent)
                onValuesChanged: requestPaint()
                onLineColorChanged: requestPaint()
                onPeakColorChanged: requestPaint()
                onWidthChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    const n = values.length
                    if (!n) return
                    const pad = Style.md, base = height - Style.xs
                    const peak = Math.max(1, root.busiestDay)
                    const peakIndex = values.indexOf(root.busiestDay)
                    const x = i => pad + i * (width - 2 * pad) / Math.max(1, n - 1)
                    const y = i => base - Style.sm - values[i] / peak * (base - Style.lg * 2)
                    function trace() {
                        ctx.beginPath()
                        ctx.moveTo(x(0), y(0))
                        for (let i = 1; i < n; i++)
                            ctx.quadraticCurveTo(x(i - 1), y(i - 1), (x(i - 1) + x(i)) / 2, (y(i - 1) + y(i)) / 2)
                        ctx.lineTo(x(n - 1), y(n - 1))
                    }
                    trace()
                    ctx.lineTo(x(n - 1), base)
                    ctx.lineTo(x(0), base)
                    ctx.closePath()
                    const fill = ctx.createLinearGradient(0, 0, 0, base)
                    fill.addColorStop(0, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, .25))
                    fill.addColorStop(1, Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0))
                    ctx.fillStyle = fill
                    ctx.fill()
                    trace()
                    ctx.strokeStyle = lineColor
                    ctx.lineWidth = Style.px(2)
                    ctx.stroke()
                    for (let i = 0; i < n; i++) {
                        ctx.beginPath()
                        ctx.arc(x(i), y(i), i === peakIndex && root.busiestDay > 0 ? Style.sm : Style.xs, 0, 2 * Math.PI)
                        ctx.fillStyle = i === peakIndex && root.busiestDay > 0 ? peakColor : lineColor
                        ctx.fill()
                    }
                }
            }
            Row {
                width: parent.width
                Repeater {
                    model: root.days
                    Column {
                        required property var modelData
                        readonly property bool today: String(modelData.date) === root.todayDate
                        width: agentsColumn.width / root.days.length; spacing: Style.xs
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter
                            text: Qt.formatDate(new Date(String(modelData.date) + "T00:00:00"), "ddd")
                            color: root.shell.alpha(root.shell.foreground, today ? .9 : .55)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: today
                        }
                        Text {
                            width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                            text: root.compact(modelData.tokenCount)
                            color: root.shell.alpha(root.shell.foreground, today ? .9 : .55)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: today
                        }
                    }
                }
            }
        }

        Column {
            visible: !root.isOpenCode && root.models.length > 0
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "TOKENS BY MODEL" }
            Repeater {
                model: root.models.slice(0, 5)
                Item {
                    id: tokenModelRow
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
                            ? parent.width * Math.min(1, tokenModelRow.modelData.total / root.heaviestModel)
                            : 0
                        radius: root.shell.rounding
                        color: root.shell.alpha(root.shell.foreground, .14)
                    }
                    Text {
                        id: modelName
                        text: tokenModelRow.modelData.name; elide: Text.ElideRight
                        color: root.shell.foreground
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        anchors.left: parent.left; anchors.leftMargin: Style.lg
                        anchors.right: modelTokens.left; anchors.rightMargin: Style.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        id: modelTokens
                        text: root.compact(tokenModelRow.modelData.total)
                        color: root.shell.mutedText
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: true
                        anchors.right: parent.right; anchors.rightMargin: Style.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Column {
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "NOTIFICATIONS" }
            PopupToggleRow {
                width: parent.width; shell: root.shell
                title: "Recommendation changes"
                detail: "Notify when the suggested agent changes"
                checked: root.notificationSettings.notifyRecommendation === true
                onToggled: root.setNotification("notifyRecommendation", !checked)
            }
            PopupToggleRow {
                width: parent.width; shell: root.shell
                title: "90% limit"
                detail: "Notify when any agent nears a limit"
                checked: root.notifyLimit
                onToggled: root.setNotification("notifyLimit", !checked)
            }
        }

        }
        }
    }

    component AgentCosts: Column {
        id: costs
        required property var popup
        spacing: Style.sectionGap
        readonly property var entries: popup.records.filter(record => record.costPeriods)
            .map(record => Object.assign({id: record.id, agent: record.name}, record.costPeriods[String(popup.costPeriod)]))
        readonly property var total: {
            const sum = {tokens: 0, costUsd: 0, unpricedTokens: 0, assumedRateTokens: 0, days: []}, days = {}
            for (const entry of entries) {
                sum.tokens += Number(entry.tokens) || 0
                sum.costUsd += Number(entry.costUsd) || 0
                sum.unpricedTokens += Number(entry.unpricedTokens) || 0
                sum.assumedRateTokens += Number(entry.assumedRateTokens) || 0
                for (const day of entry.days || []) {
                    const bucket = days[day.date] || (days[day.date] = {date: day.date, tokens: 0, costUsd: 0, unpricedTokens: 0})
                    bucket.tokens += Number(day.tokens) || 0
                    bucket.costUsd += Number(day.costUsd) || 0
                    bucket.unpricedTokens += Number(day.unpricedTokens) || 0
                }
            }
            sum.days = Object.keys(days).sort().map(date => {
                const day = days[date]
                if (day.tokens > 0 && day.tokens === day.unpricedTokens) day.costUsd = null
                return day
            })
            if (sum.tokens > 0 && sum.tokens === sum.unpricedTokens) sum.costUsd = null
            return sum
        }
        readonly property var models: {
            const models = []
            for (const entry of entries)
                for (const model of entry.models || []) models.push(Object.assign({agent: entry.agent}, model))
            return models.sort((a, b) => (Number(b.costUsd) || 0) - (Number(a.costUsd) || 0) || b.tokens - a.tokens)
        }
        readonly property bool stalePrices: popup.records.some(record => record.pricingStatus === "stale")
        readonly property bool missingPrices: popup.records.some(record => record.pricingStatus === "unavailable")

        function money(cell) {
            return cell.costUsd === null ? "Unpriced" : "$" + Number(cell.costUsd || 0).toLocaleString(Qt.locale(), 'f', 2) + (cell.unpricedTokens > 0 ? "+" : "")
        }
        function dateLabel(day) { return Qt.formatDate(new Date(day.date + "T00:00:00"), "d MMM") }

        Row {
            width: parent.width; spacing: Style.sm
            Repeater {
                model: [{days: 1, text: "Today"}, {days: 7, text: "7 days"}, {days: 30, text: "30 days"}]
                PopupTab {
                    required property var modelData
                    width: (costs.width - Style.sm * 2) / 3
                    shell: costs.popup.shell; text: modelData.text
                    selected: costs.popup.costPeriod === modelData.days
                    onClicked: costs.popup.costPeriod = modelData.days
                }
            }
        }
        PopupHero {
            shell: costs.popup.shell
            title: costs.entries.length ? costs.money(costs.total) + " estimated API value" : "Cost history not scanned"
            status: costs.entries.length ? costs.popup.compact(costs.total.tokens) + " recorded tokens" : "Press R to scan local usage"
        }
        Text {
            width: parent.width; wrapMode: Text.WordWrap
            text: "Recorded tokens valued at current API rates in USD; subscription charges are separate."
                + (costs.total.unpricedTokens > 0 ? " " + costs.popup.compact(costs.total.unpricedTokens) + " tokens have no known price." : "")
                + (costs.total.assumedRateTokens > 0 ? " " + costs.popup.compact(costs.total.assumedRateTokens) + " tokens use default rates where pricing details are missing." : "")
                + (costs.missingPrices ? " Prices unavailable; press R to retry." : costs.stalePrices ? " Using cached prices." : "")
            color: costs.popup.shell.mutedText
            font.family: costs.popup.shell.fontFamily; font.pixelSize: Style.caption
        }
        Text {
            visible: costs.entries.length > 0 && costs.total.tokens === 0
            text: "No recorded usage in this period"
            color: costs.popup.shell.mutedText
            font.family: costs.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        Column {
            visible: costs.total.tokens > 0
            width: parent.width; spacing: Style.sm
            PopupSection { shell: costs.popup.shell; text: "DAILY COST" }
            Stats.HistoryGraph {
                width: costs.width; height: Style.controlHeight * 3
                series: [costs.total.days.map(day => day.costUsd)]
                colors: [costs.popup.shell.role("act_br", costs.popup.shell.accent)]
                gap: Style.sm
                barWidth: Math.max(1, Math.floor((width + gap) / Math.max(1, costs.total.days.length)) - gap)
                minimumCeiling: 0; showGaps: true
                baselineColor: costs.popup.shell.alpha(costs.popup.shell.foreground, .12)
                gapColor: costs.popup.shell.mutedText
            }
            Row {
                width: parent.width
                Text {
                    width: parent.width / 2
                    text: costs.total.days.length ? costs.dateLabel(costs.total.days[0]) : ""
                    color: costs.popup.shell.mutedText
                    font.family: costs.popup.shell.fontFamily; font.pixelSize: Style.caption
                }
                Text {
                    width: parent.width / 2; horizontalAlignment: Text.AlignRight
                    text: costs.total.days.length ? costs.dateLabel(costs.total.days[costs.total.days.length - 1]) : ""
                    color: costs.popup.shell.mutedText
                    font.family: costs.popup.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
        }
        Column {
            visible: costs.total.tokens > 0
            width: parent.width; spacing: Style.sm
            PopupSeparator { shell: costs.popup.shell }
            PopupSection { shell: costs.popup.shell; text: "BY AGENT" }
            Repeater {
                model: costs.entries.filter(entry => entry.tokens > 0)
                PopupRow {
                    required property var modelData
                    width: costs.width; shell: costs.popup.shell; interactive: false
                    title: modelData.agent; detail: costs.popup.compact(modelData.tokens) + " tokens"
                    value: costs.money(modelData)
                }
            }
        }
        Column {
            visible: costs.models.length > 0
            width: parent.width; spacing: Style.md
            PopupSeparator { shell: costs.popup.shell }
            PopupSection { shell: costs.popup.shell; text: "BY MODEL" }
            Repeater {
                model: costs.models
                Column {
                    id: costModel
                    required property var modelData
                    width: costs.width; spacing: Style.xs
                    Row {
                        width: parent.width; spacing: Style.md
                        Text {
                            width: Math.max(0, parent.width - modelCost.implicitWidth - Style.md)
                            text: costModel.modelData.name; wrapMode: Text.WrapAnywhere
                            color: costs.popup.shell.foreground
                            font.family: costs.popup.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: true
                        }
                        Text {
                            id: modelCost
                            text: costs.money(costModel.modelData)
                            color: costs.popup.shell.foreground
                            font.family: costs.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: costModel.modelData.agent + " · " + costs.popup.compact(costModel.modelData.tokens) + " tokens"
                            + "\n" + costs.popup.compact(costModel.modelData.inputTokens) + " in · " + costs.popup.compact(costModel.modelData.outputTokens) + " out"
                            + " · " + costs.popup.compact(costModel.modelData.cacheReadInputTokens) + " cache read · " + costs.popup.compact(costModel.modelData.cacheCreationInputTokens) + " cache write"
                        color: costs.popup.shell.mutedText
                        font.family: costs.popup.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }
        }
    }

    component ProviderUsageRow: Column {
        id: row
        required property var popup
        required property var modelData
        readonly property bool expanded: popup.expandedProviderId === String(modelData.id)
        spacing: Style.xs
        Rectangle {
            id: summaryCard
            readonly property bool navigable: true
            property bool cursored: false
            signal clicked(int button)
            onClicked: row.popup.expandedProviderId = row.expanded ? "" : String(row.modelData.id)
            width: row.width; height: summary.implicitHeight + Style.md * 2
            radius: row.popup.shell.rounding
            color: hit.containsMouse || cursored || row.expanded
                ? row.popup.shell.alpha(row.popup.shell.foreground, .08) : "transparent"
            Column {
                id: summary
                x: Style.md; y: Style.md; width: parent.width - Style.md * 2
                spacing: Style.xs
                Row {
                    width: parent.width; spacing: Style.sm
                    Text {
                        id: arrow
                        width: Style.px(12); text: row.expanded ? "▾" : "▸"
                        color: row.popup.shell.foreground
                        font.family: row.popup.shell.fontFamily; font.pixelSize: Style.bodySmall
                    }
                    Text {
                        width: Math.max(0, parent.width - arrow.width - costLabel.implicitWidth - Style.sm * 2)
                        text: row.modelData.id; elide: Text.ElideRight
                        color: row.popup.shell.foreground
                        font.family: row.popup.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: true
                    }
                    Text {
                        id: costLabel
                        text: "$" + Number(row.modelData.costWeek).toFixed(2) + " / 7d"
                        color: row.popup.shell.foreground
                        font.family: row.popup.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
                Text {
                    text: row.popup.compact(row.modelData.tokensWeek) + " tokens · 7d  ·  "
                        + row.popup.compact(row.modelData.tokensMonth) + " · 30d  ·  $"
                        + Number(row.modelData.costMonth).toFixed(2)
                    width: parent.width; elide: Text.ElideRight
                    color: row.popup.shell.mutedText
                    font.family: row.popup.shell.fontFamily; font.pixelSize: Style.caption
                }
                Rectangle {
                    width: parent.width; height: Style.trackHeight; radius: height / 2
                    color: row.popup.shell.alpha(row.popup.shell.foreground, .12)
                    Rectangle {
                        width: parent.width * Math.min(1, (Number(row.modelData.tokensWeek) || 0)
                            / Math.max(1, row.popup.providerWeekTotal))
                        height: parent.height; radius: parent.radius
                        color: row.popup.shell.role("act_br", row.popup.shell.accent)
                    }
                }
            }
            MouseArea {
                id: hit
                anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: summaryCard.clicked(Qt.LeftButton)
            }
        }
        Column {
            visible: row.expanded
            width: row.width; spacing: Style.sm
            Row {
                width: parent.width
                Repeater {
                    model: row.popup.days.map(day => Qt.formatDate(new Date(String(day.date) + "T00:00:00"), "ddd"))
                    Text {
                        required property string modelData
                        width: row.width / 7; text: modelData
                        horizontalAlignment: Text.AlignHCenter
                        color: row.popup.shell.mutedText
                        font.family: row.popup.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }
            Repeater {
                model: row.expanded ? row.modelData.models || [] : []
                delegate: ProviderModelRow { popup: row.popup; width: row.width }
            }
            Text {
                visible: !(row.modelData.models || []).length
                text: "No model usage in the last 7 days"
                color: row.popup.shell.mutedText
                font.family: row.popup.shell.fontFamily; font.pixelSize: Style.caption
            }
        }
    }

    component ProviderModelRow: Column {
        id: modelRow
        required property var popup
        required property var modelData
        spacing: Style.xs
        Row {
            width: parent.width; spacing: Style.md
            Text {
                width: Math.max(0, parent.width - modelTotal.implicitWidth - Style.md)
                text: modelRow.modelData.name; elide: Text.ElideRight
                color: modelRow.popup.shell.foreground
                font.family: modelRow.popup.shell.fontFamily; font.pixelSize: Style.caption
            }
            Text {
                id: modelTotal
                text: modelRow.popup.compact(modelRow.modelData.tokensWeek)
                color: modelRow.popup.shell.mutedText
                font.family: modelRow.popup.shell.fontFamily; font.pixelSize: Style.caption
            }
        }
        Row {
            width: parent.width
            Repeater {
                model: (modelRow.modelData.daily || []).map(value => value > 0 ? modelRow.popup.compact(value) : "·")
                Text {
                    required property string modelData
                    width: modelRow.width / 7; text: modelData
                    horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    color: modelRow.popup.shell.alpha(modelRow.popup.shell.foreground, modelData === "·" ? .4 : .8)
                    font.family: modelRow.popup.shell.fontFamily; font.pixelSize: Style.caption
                }
            }
        }
    }
}
