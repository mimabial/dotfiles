.pragma library

var STATUS_READY = "ready"
var STATUS_PLAYING = "playing"
var STATUS_WON = "won"
var DIFFICULTIES = { easy: 40, medium: 32, hard: 26 }
var SIDE = 9
var BOX_SIDE = 3
var CELLS = SIDE * SIDE
var ALL_DIGITS_MASK = (1 << SIDE) - 1

var PEERS = (function () {
    var out = []
    for (var cell = 0; cell < CELLS; cell++) {
        var row = Math.floor(cell / SIDE), col = cell % SIDE
        var boxRow = Math.floor(row / BOX_SIDE) * BOX_SIDE, boxCol = Math.floor(col / BOX_SIDE) * BOX_SIDE, peers = []
        for (var i = 0; i < SIDE; i++) {
            var candidates = [row * SIDE + i, i * SIDE + col, (boxRow + Math.floor(i / BOX_SIDE)) * SIDE + boxCol + i % BOX_SIDE]
            for (var j = 0; j < candidates.length; j++) if (candidates[j] !== cell && peers.indexOf(candidates[j]) < 0) peers.push(candidates[j])
        }
        out.push(peers)
    }
    return out
})()

function range(count) { return Array.from({length: count}, function (_, i) { return i }) }
function random(randomFn) {
    var value = randomFn ? Number(randomFn()) : Math.random()
    return Math.max(0, Math.min(.999999999, isFinite(value) ? value : 0))
}
function shuffled(values, randomFn) {
    var out = values.slice()
    for (var end = out.length - 1; end > 0; end--) {
        var swap = Math.floor(random(randomFn) * (end + 1)), value = out[end]
        out[end] = out[swap]; out[swap] = value
    }
    return out
}
function generateSolvedGrid(randomFn) {
    var groups = range(BOX_SIDE), bands = shuffled(groups, randomFn), stacks = shuffled(groups, randomFn)
    var rows = [], cols = [], digits = shuffled(range(SIDE).map(function (i) { return i + 1 }), randomFn), grid = []
    for (var b = 0; b < BOX_SIDE; b++) {
        var inner = shuffled(groups, randomFn)
        for (var r = 0; r < BOX_SIDE; r++) rows.push(bands[b] * BOX_SIDE + inner[r])
    }
    for (var s = 0; s < BOX_SIDE; s++) {
        var within = shuffled(groups, randomFn)
        for (var c = 0; c < BOX_SIDE; c++) cols.push(stacks[s] * BOX_SIDE + within[c])
    }
    for (var y = 0; y < SIDE; y++) for (var x = 0; x < SIDE; x++)
        grid.push(digits[(rows[y] * BOX_SIDE + Math.floor(rows[y] / BOX_SIDE) + cols[x]) % SIDE])
    return grid
}

function countSolutions(grid, limit) {
    var rowMask = Array(SIDE).fill(0), colMask = rowMask.slice(), boxMask = rowMask.slice()
    var empty = [], used = []
    for (var i = 0; i < CELLS; i++) {
        var digit = grid[i], row = Math.floor(i / SIDE), col = i % SIDE, box = Math.floor(row / BOX_SIDE) * BOX_SIDE + Math.floor(col / BOX_SIDE)
        if (!digit) empty.push(i)
        else { var bit = 1 << digit - 1; rowMask[row] |= bit; colMask[col] |= bit; boxMask[box] |= bit }
    }
    function solve(remaining, found) {
        if (found >= limit) return found
        if (!remaining) return found + 1
        var best = -1, bestMask = 0, fewest = SIDE + 1
        for (var slot = 0; slot < empty.length; slot++) {
            if (used[slot]) continue
            var index = empty[slot], row = Math.floor(index / SIDE), col = index % SIDE
            var box = Math.floor(row / BOX_SIDE) * BOX_SIDE + Math.floor(col / BOX_SIDE)
            var mask = ~(rowMask[row] | colMask[col] | boxMask[box]) & ALL_DIGITS_MASK, count = 0, scan = mask
            while (scan) { scan &= scan - 1; count++ }
            if (!count) return found
            if (count < fewest) { best = slot; bestMask = mask; fewest = count; if (count === 1) break }
        }
        used[best] = true
        var index = empty[best], row = Math.floor(index / SIDE), col = index % SIDE
        var box = Math.floor(row / BOX_SIDE) * BOX_SIDE + Math.floor(col / BOX_SIDE)
        while (bestMask) {
            var bit = bestMask & -bestMask
            rowMask[row] |= bit; colMask[col] |= bit; boxMask[box] |= bit
            found = solve(remaining - 1, found)
            rowMask[row] ^= bit; colMask[col] ^= bit; boxMask[box] ^= bit; bestMask ^= bit
            if (found >= limit) break
        }
        used[best] = false
        return found
    }
    return solve(empty.length, 0)
}

function hasUniqueSolution(grid) { return countSolutions(grid, 2) === 1 }
function generate(target, randomFn) {
    var result
    do {
        var solution = generateSolvedGrid(randomFn), puzzle = solution.slice()
        var order = shuffled(range(CELLS), randomFn), clues = CELLS
        for (var i = 0; i < CELLS && clues > target; i++) {
            var index = order[i], saved = puzzle[index]
            puzzle[index] = 0
            if (!hasUniqueSolution(puzzle)) puzzle[index] = saved; else clues--
        }
        result = { puzzle: puzzle, solution: solution, clues: clues }
    } while (result.clues > target)
    return result
}
function create(key, randomFn) {
    key = DIFFICULTIES[key] ? key : "easy"
    var made = generate(DIFFICULTIES[key], randomFn)
    return { difficulty: key, clueCount: made.clues, solution: made.solution, givens: made.puzzle,
        entries: Array(CELLS).fill(0), notes: Array(CELLS).fill(0), selected: Math.floor(CELLS / 2),
        pencilMode: false, mistakes: 0, status: STATUS_READY, elapsed: 0 }
}
function clone(state) {
    return { difficulty: state.difficulty, clueCount: state.clueCount, solution: state.solution.slice(),
        givens: state.givens.slice(), entries: state.entries.slice(), notes: state.notes.slice(),
        selected: state.selected, pencilMode: state.pencilMode, mistakes: state.mistakes,
        status: state.status, elapsed: state.elapsed }
}
function select(state, index) {
    if (index < 0 || index >= CELLS) return state
    var next = clone(state); next.selected = index; return next
}
function moveSelection(state, dx, dy) {
    var row = Math.floor(state.selected / SIDE), col = state.selected % SIDE, next = clone(state)
    next.selected = ((row + dy + SIDE) % SIDE) * SIDE + (col + dx + SIDE) % SIDE
    return next
}
function hasNote(mask, digit) { return (mask & 1 << digit - 1) !== 0 }
function togglePencil(state) { var next = clone(state); next.pencilMode = !next.pencilMode; return next }
function erase(state, index) {
    if (state.status === STATUS_WON || index < 0 || index >= CELLS || state.givens[index]) return state
    var next = clone(state); next.entries[index] = 0; next.notes[index] = 0; return next
}
function isBoardComplete(state) {
    for (var i = 0; i < CELLS; i++) if (!state.givens[i] && state.entries[i] !== state.solution[i]) return false
    return true
}
function applyDigit(state, index, digit) {
    if (state.status === STATUS_WON || index < 0 || index >= CELLS || digit < 1 || digit > SIDE || state.givens[index]) return state
    var next = clone(state); next.selected = index
    if (next.pencilMode) { next.notes[index] ^= 1 << digit - 1; return next }
    if (next.entries[index] === digit) { next.entries[index] = 0; return next }
    next.entries[index] = digit; next.notes[index] = 0
    if (next.status === STATUS_READY) next.status = STATUS_PLAYING
    if (digit !== next.solution[index]) next.mistakes++
    else {
        var bit = 1 << digit - 1, peers = PEERS[index]
        for (var p = 0; p < peers.length; p++) next.notes[peers[p]] &= ~bit
        if (isBoardComplete(next)) next.status = STATUS_WON
    }
    return next
}
function tick(state) {
    if (state.status !== STATUS_PLAYING) return state
    var next = clone(state); next.elapsed++; return next
}
function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    return String(Math.floor(value / 60)).padStart(2, "0") + ":" + String(value % 60).padStart(2, "0")
}
