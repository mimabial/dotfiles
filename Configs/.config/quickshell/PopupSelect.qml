import QtQuick
import QtQuick.Controls

ComboBox {
    id: root
    required property var shell
    property var choices: []
    property int selectedIndex: 0
    property bool keyboardNavigation: true
    focusPolicy: keyboardNavigation ? Qt.StrongFocus : Qt.NoFocus
    model: choices
    textRole: "label"
    onSelectedIndexChanged: currentIndex = selectedIndex
    onChoicesChanged: Qt.callLater(() => currentIndex = selectedIndex)
    Component.onCompleted: currentIndex = selectedIndex
    implicitHeight: Style.px(40)
    leftPadding: Style.controlPaddingX; rightPadding: Style.px(30)

    contentItem: Text {
        text: root.displayText; color: root.shell.foreground; elide: Text.ElideRight
        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        verticalAlignment: Text.AlignVCenter
    }
    indicator: Text {
        anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX
        anchors.verticalCenter: parent.verticalCenter; text: "▾"
        color: root.shell.alpha(root.shell.foreground, .6); font.pixelSize: Style.subtitle
    }
    background: Rectangle {
        radius: root.shell.rounding; color: root.shell.alpha(root.shell.foreground, .06)
        border.color: root.shell.alpha(root.shell.role(root.down ? "act_br" : "br", root.shell.foreground), root.down ? .55 : .3)
        Behavior on border.color { ColorAnimation { duration: Style.hoverDuration } }
    }
    delegate: ItemDelegate {
        id: option
        required property int index
        required property var modelData
        width: root.width; height: Style.popupRowHeight
        focusPolicy: root.keyboardNavigation ? Qt.StrongFocus : Qt.NoFocus
        highlighted: root.highlightedIndex === index
        contentItem: Text {
            text: (option.index === root.currentIndex ? "●  " : "   ") + option.modelData.label
            color: root.shell.foreground; elide: Text.ElideRight
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: root.shell.rounding
            color: option.highlighted ? root.shell.hoverFill() : "transparent"
        }
    }
    popup: Popup {
        y: root.height + Style.xxs; width: root.width
        height: Math.min(list.contentHeight + padding * 2, Style.px(250)); padding: Style.xxs
        popupType: Popup.Item
        background: Rectangle {
            radius: root.shell.rounding; color: root.shell.alpha(root.shell.role("bg", root.shell.background), .98)
            border.width: 1; border.color: root.shell.alpha(root.shell.role("alt_br", root.shell.foreground), .45)
        }
        contentItem: ListView {
            id: list; clip: true; model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
