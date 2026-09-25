pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui as Ui

Ui.BorderSurface {
    id: control
    property bool focused: false
    property bool hovered: false
    property bool selected: false
    property bool pressed: false
    readonly property color stateColor: focused ? Color.accent
        : hovered || selected ? Color.menu.selectedText : Color.menu.text
    radius: Style.cornerRadius
    borderSpec: Border.flat(focused ? Color.accent
        : hovered || selected ? Color.menu.selectedBorder : Color.menu.border,
        focused ? Style.focusBorderWidth : Style.normalBorderWidth)
    color: pressed ? Style.pressedFillFor(Color.menu.text, Color.accent)
        : focused ? Style.focusFillFor(Color.menu.text, Color.accent)
        : hovered ? Style.hoverFillFor(Color.menu.text, Color.accent)
        : selected ? Style.selectedFillFor(Color.menu.text, Color.accent)
        : Style.normalFillFor(Color.menu.text, Color.accent)
}
