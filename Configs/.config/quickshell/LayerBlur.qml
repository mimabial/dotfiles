import QtQuick
import Quickshell
import Quickshell.Hyprland

QtObject {
    id: root

    required property string surface
    required property bool enabled

    property real ignoreAlpha: -1
    readonly property string ruleName: "quickshell-" + root.surface + "-blur"

    function replaceSurfaceBlurRule() {
        const blur = root.enabled ? "true" : "false"
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "' + root.ruleName + '"'
            + ', match = { namespace = "^' + root.surface + '$" }'
            + ', blur = ' + blur + ', blur_popups = ' + blur
            + (root.ignoreAlpha >= 0 ? ', ignore_alpha = ' + root.ignoreAlpha : "")
            + ' })'])
    }

    onEnabledChanged: root.replaceSurfaceBlurRule()
    onIgnoreAlphaChanged: root.replaceSurfaceBlurRule()
    Component.onCompleted: root.replaceSurfaceBlurRule()

    property Connections hyprland: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (String((event && event.name) || "") === "configreloaded") root.replaceSurfaceBlurRule()
        }
    }
}
