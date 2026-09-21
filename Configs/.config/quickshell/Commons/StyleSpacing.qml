import QtQuick

// Named so the grouped tokens carry a type. An inline QtObject declares as bare
// QObject, and every `Style.spacing.md` read then resolves to nothing for tooling.
QtObject {
    property int hairline
    property int xxs
    property int xs
    property int sm
    property int md
    property int lg
    property int xl
    property int huge
    property int controlGap
    property int controlPaddingX
    property int controlPaddingY
    property int inputPaddingY
    property int controlHeight
    property int popupRowHeight
    property int dropdownWidth
    property int numberFieldWidth
    property int rowPaddingX
    property int labelGap
    property int panelPadding
    property int popupPadding
}
