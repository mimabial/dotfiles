pragma Singleton
import QtQuick
import Quickshell

QtObject {
    function alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, (color.a === undefined ? 1 : color.a) * opacity)
    }

    function shellQuote(value) {
        return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
    }

    function execDetached(command) {
        Quickshell.execDetached(["bash", "-lc", command])
    }

    function execArgv(argv) {
        Quickshell.execDetached(argv)
    }

    function editsFilter(event, text) {
        if (!text || (event.modifiers & (Qt.AltModifier | Qt.MetaModifier))) return false
        if (event.key === Qt.Key_U) return event.modifiers === Qt.ControlModifier
        return event.key === Qt.Key_Backspace
    }

    function editedFilter(event, text) {
        if (event.key === Qt.Key_U) return ""
        if (event.modifiers & Qt.ControlModifier)
            return text.replace(/\s+$/, "").replace(/\S+$/, "")
        return text.slice(0, -1)
    }
}
