pragma ComponentBehavior: Bound
import QtQuick

PopupRow {
    hoverBorder: shell.mode !== "winbar" || shell.popupName !== "start"
}
