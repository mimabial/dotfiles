.pragma library

// Ported from l3aro/omarchy-sudoku (MIT), compacted for the local bar.
var STATUS_READY = "ready"
var STATUS_PLAYING = "playing"
var STATUS_WON = "won"
var DIFFICULTIES = { easy: 40, medium: 32, hard: 26 }

var PEERS = (function () {
    var out = []
    for (var cell = 0; cell < 81; cell++) {
        var row = Math.floor(cell / 9), col = cell % 9
        var boxRow = Math.floor(row / 3) * 3, boxCol = Math.floor(col / 3) * 3, peers = []
        for (var i = 0; i < 9; i++) {
            var candidates = [row * 9 + i, i * 9 + col, (boxRow + Math.floor(i / 3)) * 9 + boxCol + i % 3]
            for (var j = 0; j < 3; j++) if (candidates[j] !== cell && peers.indexOf(candidates[j]) < 0) peers.push(candidates[j])
        }
        out.push(peers)
    }
    return out
})()

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
    var groups = [0, 1, 2], bands = shuffled(groups, randomFn), stacks = shuffled(groups, randomFn)
    var rows = [], cols = [], digits = shuffled([1,2,3,4,5,6,7,8,9], randomFn), grid = []
    for (var b = 0; b < 3; b++) {
        var inner = shuffled(groups, randomFn)
        for (var r = 0; r < 3; r++) rows.push(bands[b] * 3 + inner[r])
    }
    for (var s = 0; s < 3; s++) {
        var within = shuffled(groups, randomFn)
        for (var c = 0; c < 3; c++) cols.push(stacks[s] * 3 + within[c])
    }
    for (var y = 0; y < 9; y++) for (var x = 0; x < 9; x++)
        grid.push(digits[(rows[y] * 3 + Math.floor(rows[y] / 3) + cols[x]) % 9])
    return grid
}

// Candidate bitmasks plus minimum-remaining-values search; stops at limit.
function countSolutions(grid, limit) {
    var rowMask = [0,0,0,0,0,0,0,0,0], colMask = rowMask.slice(), boxMask = rowMask.slice()
    var empty = [], used = []
    for (var i = 0; i < 81; i++) {
        var digit = grid[i], row = Math.floor(i / 9), col = i % 9, box = Math.floor(row / 3) * 3 + Math.floor(col / 3)
        if (!digit) empty.push(i)
        else { var bit = 1 << digit - 1; rowMask[row] |= bit; colMask[col] |= bit; boxMask[box] |= bit }
    }
    function solve(remaining, found) {
        if (found >= limit) return found
        if (!remaining) return found + 1
        var best = -1, bestMask = 0, fewest = 10
        for (var slot = 0; slot < empty.length; slot++) {
            if (used[slot]) continue
            var index = empty[slot], rr = Math.floor(index / 9), cc = index % 9
            var bb = Math.floor(rr / 3) * 3 + Math.floor(cc / 3)
            var mask = ~(rowMask[rr] | colMask[cc] | boxMask[bb]) & 0x1ff, count = 0, scan = mask
            while (scan) { scan &= scan - 1; count++ }
            if (!count) return found
            if (count < fewest) { best = slot; bestMask = mask; fewest = count; if (count === 1) break }
        }
        used[best] = true
        var index = empty[best], rr = Math.floor(index / 9), cc = index % 9
        var bb = Math.floor(rr / 3) * 3 + Math.floor(cc / 3)
        while (bestMask) {
            var bit = bestMask & -bestMask
            rowMask[rr] |= bit; colMask[cc] |= bit; boxMask[bb] |= bit
            found = solve(remaining - 1, found)
            rowMask[rr] ^= bit; colMask[cc] ^= bit; boxMask[bb] ^= bit; bestMask ^= bit
            if (found >= limit) break
        }
        used[best] = false
        return found
    }
    return solve(empty.length, 0)
}

function generate(target, randomFn) {
    var result
    do {
        var solution = generateSolvedGrid(randomFn), puzzle = solution.slice()
        var order = shuffled(Array.from({length: 81}, function (_, i) { return i }), randomFn), clues = 81
        for (var i = 0; i < 81 && clues > target; i++) {
            var index = order[i], saved = puzzle[index]
            puzzle[index] = 0
            if (countSolutions(puzzle, 2) !== 1) puzzle[index] = saved; else clues--
        }
        result = { puzzle: puzzle, solution: solution, clues: clues }
    } while (result.clues > target)
    return result
}
function create(key, randomFn) {
    key = DIFFICULTIES[key] ? key : "easy"
    var made = generate(DIFFICULTIES[key], randomFn)
    return { difficulty: key, clueCount: made.clues, solution: made.solution, givens: made.puzzle,
        entries: Array(81).fill(0), notes: Array(81).fill(0), selected: 40,
        pencilMode: false, mistakes: 0, status: STATUS_READY, elapsed: 0 }
}
function clone(state) {
    return { difficulty: state.difficulty, clueCount: state.clueCount, solution: state.solution.slice(),
        givens: state.givens.slice(), entries: state.entries.slice(), notes: state.notes.slice(),
        selected: state.selected, pencilMode: state.pencilMode, mistakes: state.mistakes,
        status: state.status, elapsed: state.elapsed }
}
function select(state, index) {
    if (index < 0 || index > 80) return state
    var next = clone(state); next.selected = index; return next
}
function moveSelection(state, dx, dy) {
    var row = Math.floor(state.selected / 9), col = state.selected % 9, next = clone(state)
    next.selected = ((row + dy + 9) % 9) * 9 + (col + dx + 9) % 9
    return next
}
function hasNote(mask, digit) { return (mask & 1 << digit - 1) !== 0 }
function togglePencil(state) { var next = clone(state); next.pencilMode = !next.pencilMode; return next }
function erase(state, index) {
    if (state.status === STATUS_WON || index < 0 || index > 80 || state.givens[index]) return state
    var next = clone(state); next.entries[index] = 0; next.notes[index] = 0; return next
}
function isBoardComplete(state) {
    for (var i = 0; i < 81; i++) if (!state.givens[i] && state.entries[i] !== state.solution[i]) return false
    return true
}
function digitCount(state, digit) {
    var count = 0
    for (var i = 0; i < 81; i++) if (state.givens[i] === digit || state.entries[i] === digit) count++
    return count
}
function applyDigit(state, index, digit) {
    if (state.status === STATUS_WON || index < 0 || index > 80 || digit < 1 || digit > 9 || state.givens[index]) return state
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
