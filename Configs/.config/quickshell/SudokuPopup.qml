pragma ComponentBehavior: Bound
import QtQuick
import "SudokuModel.js" as Game

PopupCard {
    id: root
    popupName: "sudoku"
    contentWidth: Style.px(360)
    contentHeight: contentColumn.implicitHeight + padding * 2

    property string difficulty: shell.store.sudokuDifficulty
    property var game: Game.create(difficulty)
    property int activeDigit: 0
    property int elapsed: 0
    property bool confirmNew: false
    property bool confirmYes: false
    readonly property int best: difficulty === "hard" ? shell.store.sudokuBestHard
        : difficulty === "medium" ? shell.store.sudokuBestMedium : shell.store.sudokuBestEasy
    readonly property var digitCounts: {
        const counts = [0,0,0,0,0,0,0,0,0]
        for (let i = 0; i < 81; i++) {
            if (game.givens[i]) counts[game.givens[i] - 1]++
            if (game.entries[i]) counts[game.entries[i] - 1]++
        }
        return counts
    }

    function saveBest() {
        if (best > 0 && elapsed >= best) return
        if (difficulty === "hard") shell.store.sudokuBestHard = elapsed
        else if (difficulty === "medium") shell.store.sudokuBestMedium = elapsed
        else shell.store.sudokuBestEasy = elapsed
    }
    function newGame() { activeDigit = 0; elapsed = 0; game = Game.create(difficulty) }
    function requestNew() { confirmYes = false; confirmNew = true }
    function setDifficulty(key) {
        if (key === difficulty) { requestNew(); return }
        difficulty = key; shell.store.sudokuDifficulty = key; newGame()
    }
    function cycleDifficulty() {
        const keys = ["easy", "medium", "hard"]
        setDifficulty(keys[(keys.indexOf(difficulty) + 1) % keys.length])
    }
    function playDigit(digit) { activeDigit = digit; game = Game.applyDigit(game, game.selected, digit) }
    function move(dx, dy) { game = Game.moveSelection(game, dx, dy) }
    function erase() { game = Game.erase(game, game.selected) }

    function handleKey(event) {
        const key = event.key, text = String(event.text || "").toLowerCase()
        if (confirmNew) {
            if (key === Qt.Key_Left || key === Qt.Key_Right || key === Qt.Key_Tab) confirmYes = !confirmYes
            else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) { confirmNew = false; if (confirmYes) newGame() }
            else if (key === Qt.Key_Escape || text === "n") confirmNew = false
            else if (text === "y") { confirmNew = false; newGame() }
            return true
        }
        if (key >= Qt.Key_1 && key <= Qt.Key_9) { playDigit(key - Qt.Key_0); return true }
        if (key === Qt.Key_Left || text === "h") { move(-1, 0); return true }
        if (key === Qt.Key_Right || text === "l") { move(1, 0); return true }
        if (key === Qt.Key_Up || text === "k") { move(0, -1); return true }
        if (key === Qt.Key_Down || text === "j") { move(0, 1); return true }
        if (key === Qt.Key_Backspace || key === Qt.Key_Delete || text === "e" || text === "x") { erase(); return true }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) { if (activeDigit) playDigit(activeDigit); return true }
        if (text === "p") { game = Game.togglePencil(game); return true }
        if (text === "r") { requestNew(); return true }
        if (text === "d") { cycleDifficulty(); return true }
        if (key === Qt.Key_Escape) { shell.closePopup(); return true }
        return false
    }

    onGameChanged: if (game.status === Game.STATUS_WON) saveBest()
    onOpenChanged: if (!open) confirmNew = false
    property Timer gameClock: Timer { interval: 1000; running: root.open && root.game.status === Game.STATUS_PLAYING; repeat: true; onTriggered: root.elapsed++ }

    component GameButton: BarButton {
        property bool selected: false
        height: Style.controlHeight; shell: root.shell; radius: root.shell.rounding
        active: false; fill: selected ? root.shell.alpha(root.shell.foreground, .14) : "transparent"
        outline: "transparent"; textColor: root.shell.alpha(root.shell.foreground, selected ? 1 : .8)
        fontWeight: selected ? Font.DemiBold : Font.Normal
    }
    component Stat: Column {
        id: stat
        required property string label
        required property string value
        spacing: Style.xxs
        Text { text: stat.label; color: root.shell.alpha(root.shell.foreground, .5); font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true }
        Text { text: stat.value; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.title; font.bold: true }
    }

    Column {
        id: contentColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.md

        PopupHero {
            shell: root.shell; title: "Sudoku"
            status: root.difficulty + " · " + (root.game.status === Game.STATUS_WON ? "solved" : root.game.clueCount + " clues")
        }
        Item {
            width: parent.width; height: Style.px(34)
            Row {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; spacing: Style.xxl
                Stat { label: "TIME"; value: Game.formatTime(root.elapsed) }
                Stat { label: "MISTAKES"; value: String(root.game.mistakes) }
                Stat { visible: root.best > 0; label: "BEST"; value: Game.formatTime(root.best) }
            }
            GameButton {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: Style.controlHeight; text: "✎"; selected: root.game.pencilMode
                tooltip: "Pencil notes (P)"; onClicked: root.game = Game.togglePencil(root.game)
            }
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.sm
            Repeater {
                model: [{key:"easy", label:"EASY"}, {key:"medium", label:"MED"}, {key:"hard", label:"HARD"}]
                GameButton {
                    required property var modelData
                    width: Style.px(48); text: modelData.label
                    selected: root.difficulty === modelData.key; onClicked: root.setDifficulty(modelData.key)
                }
            }
            GameButton { width: Style.px(48); text: "NEW"; onClicked: root.requestNew() }
        }
        Rectangle {
            id: board
            readonly property int cellSize: Style.px(36)
            anchors.horizontalCenter: parent.horizontalCenter
            width: cellSize * 9; height: width; radius: root.shell.rounding; clip: true
            color: root.shell.alpha(root.shell.foreground, .035)
            border.width: 2; border.color: root.shell.alpha(root.shell.foreground, .42)

            Grid {
                anchors.fill: parent; columns: 9; rows: 9
                Repeater {
                    model: 81
                    Item {
                        id: cell
                        required property int index
                        readonly property bool given: root.game.givens[index] !== 0
                        readonly property int entry: root.game.entries[index]
                        readonly property int value: given ? root.game.givens[index] : entry
                        readonly property bool selected: index === root.game.selected
                        readonly property bool peer: !selected && Game.PEERS[index].indexOf(root.game.selected) >= 0
                        readonly property int selectedValue: root.game.givens[root.game.selected] || root.game.entries[root.game.selected]
                        readonly property bool same: !selected && value !== 0 && value === selectedValue
                        readonly property bool wrong: !given && entry !== 0 && entry !== root.game.solution[index]
                        width: board.cellSize; height: board.cellSize

                        Rectangle {
                            anchors.fill: parent; border.width: 1
                            border.color: root.shell.alpha(root.shell.foreground, .12)
                            color: cell.selected ? root.shell.alpha(root.shell.accent, .28)
                                : cell.same ? root.shell.alpha(root.shell.accent, .16)
                                : cell.peer ? root.shell.alpha(root.shell.foreground, .055) : "transparent"
                        }
                        Loader {
                            anchors.fill: parent
                            active: cell.entry === 0 && root.game.notes[cell.index] !== 0
                            sourceComponent: Component {
                                Grid {
                                    anchors.fill: parent; anchors.margins: 2; columns: 3; rows: 3
                                    Repeater {
                                        model: 9
                                        Item {
                                            id: note
                                            required property int index
                                            width: parent.width / 3; height: parent.height / 3
                                            visible: Game.hasNote(root.game.notes[cell.index], index + 1)
                                            Text { anchors.centerIn: parent; text: note.index + 1; color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: Math.max(6, board.cellSize * .24) }
                                        }
                                    }
                                }
                            }
                        }
                        Text {
                            anchors.centerIn: parent; visible: cell.value !== 0; text: cell.value
                            color: cell.wrong ? root.shell.role("error", root.shell.foreground)
                                : cell.given ? root.shell.foreground : root.shell.accent
                            font.family: root.shell.fontFamily; font.pixelSize: board.cellSize * .52; font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: event => { root.game = Game.select(root.game, cell.index); if (event.button === Qt.RightButton) root.erase() }
                        }
                    }
                }
            }
            Repeater {
                model: [3, 6]
                Rectangle { required property int modelData; z: 2; x: modelData * board.cellSize - 1; width: 2; height: board.height; color: root.shell.alpha(root.shell.foreground, .45) }
            }
            Repeater {
                model: [3, 6]
                Rectangle { required property int modelData; z: 2; y: modelData * board.cellSize - 1; width: board.width; height: 2; color: root.shell.alpha(root.shell.foreground, .45) }
            }
            Rectangle {
                anchors.centerIn: parent; visible: root.game.status === Game.STATUS_WON
                width: wonText.implicitWidth + Style.xxl * 2; height: wonText.implicitHeight + Style.lg * 2
                radius: root.shell.rounding; color: root.shell.background
                border.width: 1; border.color: root.shell.accent
                Text { id: wonText; anchors.centerIn: parent; text: "SOLVED · " + Game.formatTime(root.elapsed); color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.title; font.bold: true }
            }
        }
        Grid {
            id: keypad
            anchors.horizontalCenter: parent.horizontalCenter; columns: 5; spacing: Style.sm
            Repeater {
                model: 9
                GameButton {
                    required property int index
                    readonly property int digit: index + 1
                    width: Style.px(28); text: digit; selected: root.activeDigit === digit
                    opacity: root.digitCounts[index] === 9 ? .35 : 1
                    onClicked: root.playDigit(digit)
                }
            }
            GameButton { width: Style.px(28); text: "⌫"; tooltip: "Erase (E)"; onClicked: root.erase() }
        }
        Text {
            width: parent.width; text: "Arrows / hjkl move · 1–9 place · P pencil · E erase · D difficulty · R new"
            wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
            color: root.shell.alpha(root.shell.foreground, .45); font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
    }

    Rectangle {
        anchors.fill: parent; visible: root.confirmNew; z: 20
        color: root.shell.alpha(root.shell.background, .88); radius: root.shell.rounding
        MouseArea { anchors.fill: parent }
        Rectangle {
            anchors.centerIn: parent; width: parent.width - Style.px(48); height: confirmColumn.implicitHeight + Style.xxl * 2
            radius: root.shell.rounding; color: root.shell.background
            border.width: 1; border.color: root.shell.alpha(root.shell.foreground, .35)
            Column {
                id: confirmColumn
                anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Style.xxl
                anchors.verticalCenter: parent.verticalCenter; spacing: Style.xxl
                Text { width: parent.width; text: "Start a new game?\nCurrent progress will be lost."; horizontalAlignment: Text.AlignHCenter; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body }
                Row {
                    width: parent.width; spacing: Style.sm
                    GameButton { width: (parent.width - parent.spacing) / 2; text: "CANCEL"; selected: !root.confirmYes; onClicked: root.confirmNew = false }
                    GameButton { width: (parent.width - parent.spacing) / 2; text: "NEW GAME"; selected: root.confirmYes; onClicked: { root.confirmNew = false; root.newGame() } }
                }
            }
        }
    }
}
