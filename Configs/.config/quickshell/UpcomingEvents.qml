pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "CalendarMath.js" as CalendarMath
import "Units.js" as Units

Item {
    id: root
    required property var shell
    readonly property string helper: root.shell.home + "/.local/lib/hypr/calendar/agenda.sh"
    readonly property string execAt: root.shell.home + "/.local/lib/hypr/calendar/lib/exec_at.py"
    readonly property int announceLeadMinutes: 15
    readonly property int imminentMinutes: 5
    readonly property int snoozeMinutes: 5
    readonly property int announcedTitleLength: 28
    property var events: []
    property var watchedDirs: []
    property var delivery: null
    property bool refreshQueued: false
    property double scheduledWakeMs: 0
    readonly property double nowMs: root.shell.clock.date.getTime()
    readonly property var current: {
        let live = null
        for (const event of root.events)
            if (!event.allDay && root.ms(event.start) <= root.nowMs && root.nowMs < root.ms(event.end) && (!live || event.start > live.start)) live = event
        return live
    }
    readonly property var upcoming: {
        let next = null
        for (const event of root.events)
            if (!event.allDay && root.ms(event.start) > root.nowMs && (!next || event.start < next.start)) next = event
        return next
    }
    readonly property var nextUp: root.current
        || (root.upcoming && CalendarMath.sameDay(new Date(root.ms(root.upcoming.start)), new Date(root.nowMs)) ? root.upcoming : null)
    readonly property var announcement: {
        const minutesLeft = root.upcoming ? Math.ceil(root.secondsUntil(root.upcoming) / Units.SECONDS_PER_MINUTE) : Infinity
        if (minutesLeft <= root.announceLeadMinutes)
            return { text: root.shortTitle(root.upcoming.title) + " in " + minutesLeft + "m", phase: minutesLeft <= root.imminentMinutes ? "imminent" : "soon" }
        return root.current ? { text: "Now: " + root.shortTitle(root.current.title), phase: "live" } : { text: "", phase: "" }
    }

    function ms(seconds) { return seconds * Units.MS_PER_SECOND }
    function secondsUntil(event) { return event.start - root.nowMs / Units.MS_PER_SECOND }
    function shortTitle(title) {
        const full = String(title || "")
        return full.length > root.announcedTitleLength ? full.slice(0, root.announcedTitleLength - 1).replace(/\s+$/, "") + "…" : full
    }
    function alarmTimes(event) { return event.alarms.map(offset => root.ms(event.start + offset)) }
    function usefulUntilMs(event, fireMs) { return fireMs < root.ms(event.start) ? root.ms(event.start) : root.ms(event.end) }
    function refresh() { if (loader.running) refreshQueued = true; else loader.running = true }

    function begin(saved) {
        if (root.delivery) return
        try { root.delivery = JSON.parse(saved) } catch (error) { root.delivery = { deliveredThrough: Date.now(), snoozed: [] } }
        root.refresh()
    }
    function record(next) {
        root.delivery = next
        deliveryFile.setText(JSON.stringify(next))
        root.scheduleWake()
    }
    function deliver() {
        const nowMs = Date.now()
        for (const event of root.events)
            if (root.alarmTimes(event).some(fireMs => fireMs > root.delivery.deliveredThrough && fireMs <= nowMs
                    && nowMs < root.usefulUntilMs(event, fireMs)))
                root.notify(event, nowMs)
        const pending = []
        for (const snoozed of root.delivery.snoozed) {
            const event = root.events.find(candidate => candidate.uid === snoozed.uid && candidate.start === snoozed.start)
            if (snoozed.dueMs > nowMs) pending.push(snoozed)
            else if (event && nowMs < root.ms(event.end)) root.notify(event, nowMs)
        }
        root.record({ deliveredThrough: nowMs, snoozed: pending })
    }
    function snooze(event) {
        root.record({
            deliveredThrough: root.delivery.deliveredThrough,
            snoozed: root.delivery.snoozed.concat({ uid: event.uid, start: event.start, dueMs: Date.now() + root.snoozeMinutes * Units.MS_PER_MINUTE })
        })
    }
    function scheduleWake() {
        const now = new Date()
        let wakeMs = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1).getTime()
        for (const event of root.events)
            for (const fireMs of root.alarmTimes(event))
                if (fireMs > now.getTime()) wakeMs = Math.min(wakeMs, fireMs)
        for (const snoozed of root.delivery.snoozed) wakeMs = Math.min(wakeMs, snoozed.dueMs)
        if (wakeMs === root.scheduledWakeMs && waiter.running) return
        root.scheduledWakeMs = wakeMs
        waiter.running = false
        waiter.command = ["python3", root.execAt, String(wakeMs / Units.MS_PER_SECOND), "true"]
        waiter.running = true
    }
    function reminderBody(event, nowMs) {
        const start = new Date(root.ms(event.start))
        const when = event.allDay
            ? (CalendarMath.relativeDayLabel(CalendarMath.isoDay(start), new Date(nowMs)) || Qt.formatDate(start, "ddd d MMM")) + ", all day"
            : (start.getTime() > nowMs ? "In " + root.shell.duration((start.getTime() - nowMs) / Units.MS_PER_SECOND) : "Now")
                + "  ·  " + Qt.formatTime(start, "HH:mm") + " – " + Qt.formatTime(new Date(root.ms(event.end)), "HH:mm")
        return [when, event.location].filter(part => !!part).join("  ·  ")
    }
    function notify(event, nowMs) {
        const notice = noticeComponent.createObject(root, { command: ["notify-send", "-a", "Calendar", "-i", "appointment-soon",
            "-A", "default=Snooze " + root.snoozeMinutes + "m", "--", String(event.title || ""), root.reminderBody(event, nowMs)] })
        notice.exited.connect(() => {
            if (notice.stdout.text.trim() === "default") root.snooze(event)
            notice.destroy()
        })
        notice.running = true
    }

    Component { id: noticeComponent; Process { stdout: StdioCollector {} } }
    Process {
        id: loader
        command: ["bash", root.helper, "--upcoming"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
            let payload = ({})
            try { payload = JSON.parse(text) || ({}) } catch (error) { payload = ({}) }
            root.events = payload.events || []
            const dirs = payload.dirs || []
            if (JSON.stringify(dirs) !== JSON.stringify(root.watchedDirs)) root.watchedDirs = dirs
            root.deliver()
        } }
        onExited: if (root.refreshQueued) { root.refreshQueued = false; root.refresh() }
    }
    Process { id: waiter; onExited: exitCode => { if (exitCode === 0) root.refresh() } }
    Process {
        command: ["inotifywait", "--monitor", "--quiet", "--event", "close_write,create,delete,move"].concat(root.watchedDirs)
        running: root.watchedDirs.length > 0
        stdout: SplitParser { onRead: root.refresh() }
    }
    FileView {
        id: deliveryFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/hypr/quickshell-calendar-reminders.json"
        printErrors: false
        onLoaded: root.begin(text())
        onLoadFailed: root.begin("")
    }
}
