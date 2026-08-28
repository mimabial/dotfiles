import QtQuick
import QtQuick.Layouts
import ".."

BarGroup {
    id: root
    shell: root.shell; css: "mark"; reverse: true; Layout.fillWidth: true
    readonly property bool shown: root.shell.workflow === "gaming"
    visible: root.shown
    holdOpen: root.shell.popupName === "cliphist"
    slots: [markSlot, gamemodeSlot]

    Component { id: markSlot; BarButton { shell: root.shell; css: "mark-button"; text: "—"; textColor: root.shell.role("c7", root.shell.foreground) } }
    Component { id: gamemodeSlot; BarButton { shell: root.shell; text: ""; tooltip: "GameMode active" } }
}
