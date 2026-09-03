import QtQuick
import QtQuick.Layouts
import ".."

ScriptButton {
    property bool popupsAllowed: true
    property bool randomizeProgressShape: false
    // false gives the stacked countdown the vertical bars have room for
    property bool iconMode: true
    id: mediaButton
    // left bar: the stacked countdown; main bar: --icon, the state glyph
    // alone. One instance either way, so only one daemon runs
    shell: mediaButton.shell; css: "mediaplayer"; Layout.fillWidth: true; useAlt: true
    command: iconMode ? ["hyprshell", "mediaplayer.py", "--icon"] : ["hyprshell", "mediaplayer.py"]
    interval: 5000; textColor: mediaButton.shell.mediaColor(output)
    onClicked: button => button === Qt.RightButton ? mediaButton.shell.run(["hyprshell", "mediaplayer.py", "--action", "play-pause"]) : mediaButton.shell.togglePopup("media")
    onWheeled: delta => mediaButton.shell.run(["hyprshell", "mediaplayer.py", "--action", delta > 0 ? "cycle-next" : "cycle-previous"])
    MediaPopup { anchorItem: mediaButton; shell: mediaButton.shell; popupEnabled: mediaButton.popupsAllowed; randomizeProgressShape: mediaButton.randomizeProgressShape }
}
