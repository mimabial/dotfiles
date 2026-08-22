import QtQuick

// The provider emits an empty string outside a submap, so this module is only
// on screen while one is held. The blink is what makes that state hard to miss;
// it stops on its own when the submap exits and the module goes away.
ScriptButton {
    id: root
    property color baseColor: shell.foreground

    css: "submap"
    interval: 86400000
    // the hover fade would fight the animation for the same property
    smoothTextColor: false
    textColor: baseColor

    SequentialAnimation on textColor {
        running: root.visible
        loops: Animation.Infinite
        ColorAnimation { to: root.shell.alpha(root.baseColor, .2); duration: 550; easing.type: Easing.InOutQuad }
        ColorAnimation { to: root.baseColor; duration: 550; easing.type: Easing.InOutQuad }
    }
}
