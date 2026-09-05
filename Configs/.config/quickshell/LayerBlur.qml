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

    // Blur covers the whole layer surface — and an xdg popup counts as part of
    // its parent surface, so a bar rule blurs every popup's full area too, far
    // past the bar itself. A threshold at or above zero leaves pixels that faint
    // alone, confining the effect to what the surface actually paints: the panel
    // and its cards, not the empty room reserved around them. A fully
    // transparent surface paints nothing and so blurs nothing — reach for an
    // opacity preset rather than the transparency toggle to get frosted glass.
    property real ignoreAlpha: -1

    function apply() {
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ name = "quickshell-' + root.surface + '-blur"'
            + ', match = { namespace = "^' + root.surface + '$" }'
            + ', blur = ' + (root.enabled ? "true" : "false")
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
