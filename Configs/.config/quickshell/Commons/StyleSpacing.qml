import QtQuick

// Named so the grouped tokens carry a type. An inline QtObject declares as bare
// QObject, and every `Style.spacing.md` read then resolves to nothing for tooling.
QtObject {
    property int xs
    property int sm
    property int md
    property int lg
    property int xl
    property int panelPadding
}
