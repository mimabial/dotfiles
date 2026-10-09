pragma ComponentBehavior: Bound
import QtQuick
import "../LanguageModel.js" as Model
import ".."

LanguageButton {
    id: root
    popupName: "language-menu"
    property bool macInputItems: true
    MacCard {
        anchorItem: root; shell: root.shell; popupEnabled: root.popupsAllowed; popupName: "language-menu"; settings: root.macInputItems ? "Keyboard" : ""; settingsPopup: "language"
        onOpenChanged: if (open) root.settingsPanel.ensureCatalog()
        Repeater {
            model: root.output.configured ?? []
            PopupRow {
                required property var modelData
                required property int index
                width: parent.width; shell: root.shell; icon: "󰌌"
                iconColor: index === root.output.activeIndex ? root.shell.accent : root.shell.alpha(root.shell.foreground, .55)
                title: Model.descriptionFor(root.settingsPanel.catalog, modelData.layout, modelData.variant)
                onClicked: { root.shell.closePopup(); root.shell.run(["hyprshell", "util/keyboard-layout", "--use", String(index)]) }
            }
        }
        PopupSeparator { shell: root.shell; visible: root.macInputItems }
        PopupRow { width: parent.width; shell: root.shell; visible: root.macInputItems; title: "Show Emoji & Symbols"; onClicked: { root.shell.closePopup(); root.shell.run(["hyprshell", "emoji-picker.sh"]) } }
    }
}
