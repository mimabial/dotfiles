pragma ComponentBehavior: Bound
import QtQuick
import "../Commons" as Commons

Item {
    id: root

    property bool opened: false
    property string message: ""
    property string cancelText: "Cancel"
    property string confirmText: "Confirm"
    property int selectedIndex: 1
    property color background: Commons.Color.background
    property color foreground: Commons.Color.foreground
    property color scrim: Commons.Util.alpha(Commons.Color.background, 0.7)
    property color selectedBackground: Commons.Util.alpha(Commons.Color.foreground, 0.08)
    property color selectedText: Commons.Color.accent
    property string fontFamily: Commons.Style.font.family
    property int cornerRadius: Commons.Style.cornerRadius

    signal canceled()
    signal confirmed()

    function handleKey(event) {
        if (!root.opened) return false
        if (event.key === Qt.Key_Escape) root.canceled()
        else if ([Qt.Key_Left, Qt.Key_Right, Qt.Key_Tab, Qt.Key_Backtab].includes(event.key))
            root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.selectedIndex === 0 ? root.canceled() : root.confirmed()
        else return false
        return true
    }

    visible: opened

    Rectangle {
        anchors.fill: parent
        color: root.scrim
        MouseArea { anchors.fill: parent; onClicked: root.canceled() }

        BorderSurface {
            id: card
            width: Math.min(parent.width - Commons.Style.space(32), Commons.Style.space(370))
            height: contentTopInset + contentBottomInset + messageText.implicitHeight + Commons.Style.space(54)
            anchors.centerIn: parent
            color: root.background
            borderSpec: Commons.Border.flat(root.selectedText, Commons.Style.normalBorderWidth)
            padding: Commons.Style.space(18)
            radius: root.cornerRadius
            MouseArea { anchors.fill: parent; onClicked: {} }

            Text {
                id: messageText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: card.contentLeftInset
                text: root.message
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Commons.Style.font.title
                wrapMode: Text.WordWrap
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: card.contentRightInset
                anchors.bottom: parent.bottom
                anchors.bottomMargin: card.contentBottomInset
                spacing: Commons.Style.space(10)

                Repeater {
                    model: [root.cancelText, root.confirmText]
                    delegate: Button {
                        id: choiceButton
                        required property int index
                        required property string modelData
                        width: Commons.Style.space(88)
                        height: Commons.Style.space(34)
                        text: modelData
                        bordered: true
                        selected: root.selectedIndex === index
                        foreground: index === 1 ? Commons.Color.urgent : root.foreground
                        accent: index === 1 ? Commons.Color.urgent : root.selectedText
                        onClicked: index === 0 ? root.canceled() : root.confirmed()
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: root.selectedIndex = choiceButton.index
                            onClicked: choiceButton.index === 0 ? root.canceled() : root.confirmed()
                        }
                    }
                }
            }
        }
    }
}
