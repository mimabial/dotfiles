.pragma library

var BY_KIND = {
    main: [
        { pattern: "HH\n—\nmm", hasDate: false, hasTime: true },
        { pattern: "h\n—\nmm\nAP", hasDate: false, hasTime: true },
        { pattern: "dd\nMMM\n''yy", hasDate: true, hasTime: false },
        { pattern: "HH\nmm", hasDate: false, hasTime: true }
    ],
    winbar: [
        { pattern: "HH:mm\ndd|MM", hasDate: true, hasTime: true },
        { pattern: "dd|MM\nHH:mm", hasDate: true, hasTime: true },
        { pattern: "ddd dd\nHH:mm", hasDate: true, hasTime: true },
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
