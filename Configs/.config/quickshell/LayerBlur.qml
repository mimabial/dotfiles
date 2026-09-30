import QtQuick
import Quickshell
import Quickshell.Hyprland

// Blur for one layer-shell surface. Hyprland keys layer rules by name, so
// re-declaring the same name replaces the rule instead of stacking a second
// one, and a rule with blur false is how it gets turned back off — there is no
// way to withdraw a rule. `hyprctl reload` reinstates whatever windowrules.lua
// declared, so the current state is re-applied whenever the config reloads.
QtObject {
    id: root

    required property string surface
    required property bool enabled

    // Blur spans each surface and popup window whole; a threshold at or above
    // zero confines it to the pixels actually painted.
    property real ignoreAlpha: -1

    function apply() {
        const blur = root.enabled ? "true" : "false"
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "quickshell-' + root.surface + '-blur"'
            + ', match = { namespace = "^' + root.surface + '$" }'
            + ', blur = ' + blur + ', blur_popups = ' + blur
            + (root.ignoreAlpha >= 0 ? ', ignore_alpha = ' + root.ignoreAlpha : "")
            + ' })'])
    }

    onEnabledChanged: root.apply()
    onIgnoreAlphaChanged: root.apply()
    Component.onCompleted: root.apply()

    property Connections hyprland: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (String((event && event.name) || "") === "configreloaded") root.apply()
        }
    }
}
