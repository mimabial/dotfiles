pragma ComponentBehavior: Bound
import QtQuick

PopupCard {
    id: root
    popupName: "agents"
    contentWidth: Style.px(380)
    contentHeight: agentsViewport.height + hintHeight + padding * 2

    property var records: []
    property int selected: 0
    property string expandedProviderId: ""
    property string recommendationId: ""
    signal select(int index)
    signal refreshRequested()

    readonly property int blockingHorizonMs: 5 * 3600000
    readonly property int staleAfterMs: 40 * 60000
    readonly property int viewportHeight: Style.px(520)
    readonly property int hintHeight: Style.px(24)
    readonly property real switchMargin: 0.05

    readonly property var provider: records.length ? records[Math.min(selected, records.length - 1)] : null
    readonly property bool selectedRecommended: provider !== null && String(provider.id) === recommendationId
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
    readonly property real recentTotal: days.reduce((total, day) => total + (Number(day.messageCount) || 0), 0)
    readonly property real providerWeekTotal: providerUsage.reduce((total, entry) => total + (Number(entry.tokensWeek) || 0), 0)
    readonly property real busiestDay: {
        let peak = 0
        for (const day of days) peak = Math.max(peak, Number(day.messageCount) || 0)
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
            const used = clearsIn > 0 ? Math.min(1, Number(limit.percent)) : 0
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
            if (Number(limit.percent) >= 0)
                parts.push(Math.round(Number(limit.percent) * 100) + "% " + limitName(limit))
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
    function handleKey(event) {
        if (event.key === Qt.Key_R) { refreshRequested(); return true }
        return defaultKey(event)
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

    Flickable {
        id: agentsViewport
        width: parent.width
        height: Math.max(0, Math.min(root.viewportHeight,
            root.anchorWindow ? root.maxHeight - root.padding * 2 : root.viewportHeight) - root.hintHeight)
        contentHeight: agentsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: agentsColumn
            width: agentsViewport.width; spacing: Style.sectionGap

        PopupHero {
            shell: root.shell
            title: root.provider ? root.provider.name : "No AI coding subscriptions found"
            status: root.providerSummary
        }

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
                    text: modelData.name + (root.recommendationId === String(modelData.id) ? "  *" : "")
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
                            text: Math.round(Number(limitRow.modelData.percent) * 100) + "%"
                            color: root.shell.alpha(root.shell.foreground, .65)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
                        }
                    }
                    Rectangle {
                        width: parent.width; height: Style.trackHeight; radius: Style.trackHeight / 2
                        color: root.shell.alpha(root.shell.foreground, .12)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, Number(limitRow.modelData.percent)))
                            height: parent.height; radius: parent.radius
                            color: Number(limitRow.modelData.percent) >= 0.9
                                ? root.shell.role("error", root.shell.accent)
                                : root.shell.role("act_br", root.shell.accent)
                        }
                    }
                    Text {
                        readonly property string untilReset: root.open ? root.resetsIn(limitRow.modelData.resetsAt) : ""
                        visible: untilReset !== ""
                        width: parent.width
                        text: "Resets in " + untilReset
                        color: root.shell.alpha(root.shell.foreground, .55)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
                    }
                }
            }
        }

        Column {
            visible: root.providerUsage.length > 0
            width: parent.width; spacing: Style.md
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
            color: root.shell.alpha(root.shell.foreground, .55)
            font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }

        Column {
            visible: root.days.length > 0
            width: parent.width; spacing: Style.md
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "RECENT USAGE · " + root.compact(root.recentTotal) + " TOKENS" }
            Canvas {
                id: recentChart
                width: agentsColumn.width; height: Style.px(72)
                antialiasing: true
                readonly property var values: root.days.map(day => Number(day.messageCount) || 0)
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
                            text: root.compact(modelData.messageCount)
                            color: root.shell.alpha(root.shell.foreground, today ? .9 : .55)
                            font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: today
                        }
                    }
                }
            }
        }

        Column {
            visible: !root.isOpenCode && root.models.length > 0
            width: parent.width; spacing: Style.md
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
                        color: root.shell.alpha(root.shell.foreground, .65)
                        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall; font.bold: true
                        anchors.right: parent.right; anchors.rightMargin: Style.lg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        }
    }

    Text {
        y: agentsViewport.height + (root.hintHeight - implicitHeight) / 2
        width: parent.width
        text: "R refresh" + (root.records.length > 1 && root.selectedRecommended
            ? "  ·  * Recommended" : "")
        horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
        color: root.shell.alpha(root.shell.foreground, .55)
        font.family: root.shell.fontFamily; font.pixelSize: Style.caption
    }

    component ProviderUsageRow: Column {
        id: row
        required property var popup
        required property var modelData
        readonly property bool expanded: popup.expandedProviderId === String(modelData.id)
        spacing: Style.xs
        Rectangle {
            width: row.width; height: summary.implicitHeight + Style.md * 2
            radius: row.popup.shell.rounding
            color: hit.containsMouse || row.expanded
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
                    color: row.popup.shell.alpha(row.popup.shell.foreground, .55)
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
                onClicked: row.popup.expandedProviderId = row.expanded ? "" : String(row.modelData.id)
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
                        color: row.popup.shell.alpha(row.popup.shell.foreground, .55)
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
                color: row.popup.shell.alpha(row.popup.shell.foreground, .55)
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
                color: modelRow.popup.shell.alpha(modelRow.popup.shell.foreground, .65)
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
