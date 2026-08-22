import QtQuick
import QtQuick.Layouts

// One option row. Reuses PopupSlider and ToggleSwitch rather than drawing new
// controls, so the panel inherits the same feel as every other popup surface.
// PopupSlider collapses its own header when label, icon and valueText are all
// empty, which is what lets it sit inline here with the label drawn alongside.
//
// The three controls are siblings rather than a Loader over inline Components:
// a Component has its own scope, so every `root.` reference across that boundary
// is unqualified access. Only one section's rows exist at a time, so the two
// hidden controls per row cost nothing worth reaching for a Loader over.
Rectangle {
    id: root

    required property var shell
    required property var row
    property var value: null
    property bool overridden: false
    property bool selected: false

    signal changed(real value)
    signal released(real value)
    signal toggled
    signal cycled(int direction)

    readonly property bool isSlider: row.type === "int" || row.type === "float"
    readonly property bool isToggle: row.type === "bool"

    readonly property string valueText: {
        if (value === null || value === undefined) return "—"
        if (row.type === "float") return Number(value).toFixed(row.step < 0.01 ? 3 : 2)
        return String(value)
    }

    implicitHeight: Style.popupRowHeight + Style.sm
    radius: shell.rounding
    color: selected ? shell.hoverFill(1) : "transparent"
    border.width: selected ? 1 : 0
    border.color: selected ? shell.hoverEdge(1) : "transparent"
    Behavior on color { ColorAnimation { duration: Style.hoverDuration } }

    // The panel's core question is "which of these have I changed", so an
    // overridden row is marked rather than merely differing from a remembered
    // default.
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: Style.xs
        anchors.verticalCenter: parent.verticalCenter
        width: Style.xxs
        height: parent.height - Style.md
        radius: width / 2
        color: root.shell.role("act_br", root.shell.accent)
        opacity: root.overridden ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Style.hoverDuration } }
    }

    RowLayout {
        id: layout
        anchors.fill: parent
        anchors.leftMargin: Style.controlPaddingX
        anchors.rightMargin: Style.controlPaddingX
        spacing: Style.controlGap

        Text {
            text: root.row.label
            color: root.shell.foreground
            font.family: root.shell.fontFamily
            font.pixelSize: Style.body
            elide: Text.ElideRight
            Layout.preferredWidth: Math.round(layout.width * 0.42)
        }

        PopupSlider {
            visible: root.isSlider
            shell: root.shell
            label: ""
            icon: ""
            valueText: ""
            minimum: root.row.min === undefined ? 0 : root.row.min
            maximum: root.row.max === undefined ? 1 : root.row.max
            step: root.row.step === undefined ? 0 : root.row.step
            value: Number(root.value === null || root.value === undefined
                ? (root.row.min === undefined ? 0 : root.row.min) : root.value)
            onChanged: value => root.changed(value)
            onReleased: value => root.released(value)
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
        }

        ToggleSwitch {
            visible: root.isToggle
            shell: root.shell
            checked: root.value === true
            onToggled: root.toggled()
            Layout.alignment: Qt.AlignVCenter
        }

        // Enum and pipeline rows share a presentation: the current value with
        // arrows, cycled by the same keys that adjust a slider.
        Item {
            visible: !root.isSlider && !root.isToggle
            implicitHeight: Style.controlHeight
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter

            Text {
                id: prev
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily
                font.pixelSize: Style.body
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.sm
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycled(-1)
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily
                font.pixelSize: Style.body
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.sm
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cycled(1)
                }
            }
        }

        // Numbers need a narrow column; enum and pipeline values are words and
        // need room, or "optimized" reads as "…imized".
        Text {
            visible: !root.isToggle
            text: root.valueText
            color: root.shell.alpha(root.shell.foreground, .65)
            font.family: root.shell.fontFamily
            font.pixelSize: Style.bodySmall
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            Layout.preferredWidth: Style.px(root.isSlider ? 52 : 104)
        }
    }

}
