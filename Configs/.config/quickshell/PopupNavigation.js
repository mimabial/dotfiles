.pragma library

function collectRows(container, rows) {
    for (const child of container.children) {
        if (!child.visible) continue
        if (child.navigable === true) rows.push(child)
        collectRows(child, rows)
    }
    return rows
}

function setCursor(rows, index) {
    rows.forEach((row, rowIndex) => {
        if (row) row.cursored = rowIndex === index
    })
}

function activate(row) {
    if (!row) return
    if (row.activateKeyboard) row.activateKeyboard()
    else if (row.clicked) row.clicked(Qt.LeftButton)
}

function adjust(row, direction) {
    return !!row && !!row.adjustKeyboard && row.adjustKeyboard(direction) !== false
}
