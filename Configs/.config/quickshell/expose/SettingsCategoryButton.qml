pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: categoryButton
    required property var controller
    property int categoryIndex: 0
    property int categoryCount: 1
    property string label: ""
    property bool selected: false
    property bool horizontal: false
    property bool hovered: false
    signal chosen(int nextIndex)
    implicitWidth: Style.space(horizontal ? 140 : 200)
    implicitHeight: Style.space(horizontal ? 52 : 48)
    activeFocusOnTab: selected

    signal entered()

    function choose(nextIndex) {
        categoryButton.chosen(Math.max(0, Math.min(categoryButton.categoryCount - 1, nextIndex)));
    }

    // The sidebar is a list: arrows along its axis pick a section, the
    // arrow pointing at the content (or Enter/Space) moves focus into it.
    Keys.onPressed: function (event) {
        if (categoryButton.controller.handleSettingsTab(event))
            return;
        var previousKey = categoryButton.horizontal ? Qt.Key_Left : Qt.Key_Up;
        var nextKey = categoryButton.horizontal ? Qt.Key_Right : Qt.Key_Down;
        var enterKey = categoryButton.horizontal ? Qt.Key_Down : Qt.Key_Right;
        if (event.key === previousKey)
            categoryButton.choose(categoryButton.categoryIndex - 1);
        else if (event.key === nextKey)
            categoryButton.choose(categoryButton.categoryIndex + 1);
        else if (event.key === Qt.Key_Home)
            categoryButton.choose(0);
        else if (event.key === Qt.Key_End)
            categoryButton.choose(categoryButton.categoryCount - 1);
        else if (event.key === enterKey
                || event.key === Qt.Key_Space
                || event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter)
            categoryButton.entered();
        else {
            event.accepted = false;
            return;
        }
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Color.accent
        opacity: categoryButton.selected ? 0.07 : (categoryButton.hovered ? 0.035 : 0)
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: categoryButton.horizontal ? parent.width : Math.max(2, Style.focusBorderWidth)
        height: categoryButton.horizontal ? Math.max(2, Style.focusBorderWidth) : parent.height
        visible: categoryButton.selected
        color: Color.accent
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Style.space(categoryButton.horizontal ? 8 : 18)
        anchors.rightMargin: Style.space(categoryButton.horizontal ? 8 : 18)
        spacing: Style.spacing.md

        Text {
            Layout.preferredWidth: Style.space(18)
            text: String(categoryButton.categoryIndex + 1)
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            color: categoryButton.selected ? Color.accent : Color.menu.text
            opacity: categoryButton.selected || categoryButton.hovered ? 1 : 0.45
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            font.bold: categoryButton.selected
        }

        Text {
            Layout.fillWidth: true
            text: categoryButton.label
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            color: Color.menu.text
            opacity: categoryButton.selected || categoryButton.hovered ? 1 : 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: categoryButton.selected
            elide: Text.ElideRight
        }

    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: Style.space(2)
        color: "transparent"
        border.color: categoryButton.activeFocus ? Color.accent : "transparent"
        border.width: categoryButton.activeFocus ? Math.max(2, Style.focusBorderWidth) : 0
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: categoryButton.hovered = true
        onExited: categoryButton.hovered = false
        onPressed: categoryButton.forceActiveFocus()
        onClicked: categoryButton.choose(categoryButton.categoryIndex)
    }
}
