pragma ComponentBehavior: Bound
import QtQuick
import qs

Behavior {
    id: behavior
    enabled: !Style.reduceMotion
    onEnabledChanged: if (!enabled && animation) { animation.complete(); snap.start() }
    property PropertyAction snap: PropertyAction {
        target: behavior.targetProperty.object
        property: behavior.targetProperty.name
        value: behavior.targetValue
    }
}
