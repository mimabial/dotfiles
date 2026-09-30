.pragma library

var BY_KIND = {
    winbar: [
        { pattern: "HH:mm\ndd/MM/yyyy", hasDate: true, hasTime: true },
        { pattern: "HH:mm\ndd|MM", hasDate: true, hasTime: true },
        { pattern: "dd|MM\nHH:mm", hasDate: true, hasTime: true },
        { pattern: "ddd dd\nHH:mm", hasDate: true, hasTime: true },
        { pattern: "HH:mm", hasDate: false, hasTime: true }
    ],
    macos: [
        { pattern: "ddd d MMM  HH:mm", hasDate: true, hasTime: true },
        { pattern: "ddd MMM d  h:mm AP", hasDate: true, hasTime: true },
        { pattern: "HH:mm", hasDate: false, hasTime: true }
    ],
    top: [
        { pattern: "dddd HH:mm", hasDate: true, hasTime: true },
        { pattern: "dddd h:mm AP", hasDate: true, hasTime: true },
        { pattern: "HH:mm", hasDate: false, hasTime: true },
        { pattern: "h:mm AP", hasDate: false, hasTime: true },
        { pattern: "ddd d MMM HH:mm", hasDate: true, hasTime: true },
        { pattern: "ddd d MMM h:mm AP", hasDate: true, hasTime: true },
        { pattern: "d MMMM yyyy", hasDate: true, hasTime: false },
        { pattern: "yyyy-MM-dd HH:mm", hasDate: true, hasTime: true },
        { pattern: "ddd,d HH:mm", hasDate: true, hasTime: true }
    ]
}

function forKind(kind) { return BY_KIND[kind] || BY_KIND.top }
function selected(kind, index) {
    var formats = forKind(kind)
    return formats[((index % formats.length) + formats.length) % formats.length]
}
