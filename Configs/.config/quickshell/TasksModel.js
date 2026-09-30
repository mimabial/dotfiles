var activityWeeks = 26
var topCount = 3
var scopes = ["open", "all", "done", "due", "rec", "today", "later", "overdue"]

function key(item) { return String(item.uid || (item.list + ":" + item.id)) }

function fuzzy(value, query) {
    const source = String(value).toLowerCase(), needle = String(query).toLowerCase()
    let at = 0
    for (const character of source) if (character === needle[at]) at++
    return at === needle.length
}

function scope(query) {
    let result = ""
    for (const word of String(query).trim().split(/\s+/)) {
        const match = word.toLowerCase().match(/^in:(\w+)$/)
        if (match && scopes.includes(match[1])) result = match[1]
    }
    return result
}

function withScope(query, selected) {
    const words = String(query).trim().split(/\s+/).filter(word =>
        word && !/^in:(open|all|done|due|rec|today|later|overdue)$/i.test(word))
    if (selected) words.push("in:" + selected)
    return words.join(" ")
}

function matches(item, query) {
    const priority = Number(item.priority || 0)
    const fields = [item.summary, item.description, item.location, item.list,
        item.priority, priority > 0 && priority <= 4 ? "high" : priority === 5 ? "medium"
            : priority > 5 ? "low" : "none",
        item.due === null || item.due === undefined ? "" : dateKey(new Date(Number(item.due) * 1000))]
        .concat(item.categories || [])
    return String(query).trim().split(/\s+/).filter(Boolean).every(word => {
        if (/^in:(open|all|done|due|rec|today|later|overdue)$/i.test(word)) return true
        const values = word[0] === "+" ? item.categories || []
            : word[0] === "@" ? [item.list] : fields
        const needle = word[0] === "+" || word[0] === "@" ? word.slice(1) : word
        return values.some(value => String(value || "").split(/\s+/).some(part => fuzzy(part, needle)))
    })
}

function sorted(items, mode, order) {
    const ranks = Object.create(null)
    order.forEach((value, index) => ranks[String(value)] = index)
    const due = item => item.due === null || item.due === undefined ? Infinity : Number(item.due)
    const priority = item => Number(item.priority || 0) || Infinity
    return items.map((item, index) => ({item: item, index: index})).sort((left, right) => {
        const a = left.item, b = right.item
        if (mode === "manual") {
            const x = ranks[key(a)], y = ranks[key(b)]
            if (x !== undefined || y !== undefined)
                return (x === undefined ? Infinity : x) - (y === undefined ? Infinity : y)
        } else {
            const first = mode === "priority" ? priority(a) - priority(b) : due(a) - due(b)
            const second = mode === "priority" ? due(a) - due(b) : priority(a) - priority(b)
            if (!isNaN(first) && first !== 0) return first
            if (!isNaN(second) && second !== 0) return second
        }
        return left.index - right.index
    }).map(entry => entry.item)
}

function dateKey(date) {
    return date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0")
        + "-" + String(date.getDate()).padStart(2, "0")
}

function activity(items, now) {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 12)
    const start = new Date(today)
    start.setDate(today.getDate() - today.getDay() - (activityWeeks - 1) * 7)
    const counts = Object.create(null), categories = Object.create(null), calendars = Object.create(null)
    let total = 0
    for (const item of items) {
        if (item.completed !== true || !Number(item.completed_at)) continue
        const day = new Date(Number(item.completed_at) * 1000)
        day.setHours(12, 0, 0, 0)
        if (day < start || day > today) continue
        const key = dateKey(day)
        counts[key] = (counts[key] || 0) + 1
        total++
        for (const name of new Set(item.categories || []))
            categories[name] = (categories[name] || 0) + 1
        if (item.list) calendars[item.list] = (calendars[item.list] || 0) + 1
    }
    const cells = [], months = []
    const monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    for (let week = 0; week < activityWeeks; week++) {
        let label = ""
        for (let day = 0; day < 7; day++) {
            const date = new Date(start)
            date.setDate(start.getDate() + week * 7 + day)
            if (date.getDate() === 1) label = monthNames[date.getMonth()]
            cells.push({date: dateKey(date), count: date > today ? 0 : counts[dateKey(date)] || 0,
                future: date > today})
        }
        months.push(label || (week === 0 ? monthNames[start.getMonth()] : ""))
    }
    const top = values => Object.keys(values).map(name => ({name: name, count: values[name]}))
        .sort((a, b) => b.count - a.count || a.name.localeCompare(b.name)).slice(0, topCount)
    return {cells: cells, months: months, total: total,
        topCategories: top(categories), topCalendars: top(calendars)}
}
