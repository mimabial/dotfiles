pragma ComponentBehavior: Bound
import QtQuick
import ".."

BarGroup {
    id: root
    property bool popupsAllowed: true
    property bool sliderFirst: false
    property bool showSlider: true
    css: "volumecontrol"
    slots: !root.vertical || !root.showSlider ? [audioSlot, microphoneSlot]
        : root.sliderFirst ? [audioSlot, volumeSlot, microphoneSlot]
        : [audioSlot, microphoneSlot, volumeSlot]

    Component { id: audioSlot; AudioButton {
        shell: root.shell; framed: root.vertical; popupEnabled: root.popupsAllowed
    } }
    Component { id: microphoneSlot; MicrophoneButton { shell: root.shell } }
    Component { id: volumeSlot; VolumeSlider { shell: root.shell } }
}
