import QtQuick

// The target and destination choices screenshot.sh takes positionally, so the
// three-way click on the module is not the only way in.
PopupCard {
    id: root
    popupName: "screenshot"
    contentWidth: 320

    property string target: "smart"
    property string destination: "annotate"

    readonly property var targets: [
        {id: "smart",       icon: "\u{f0cfd}", label: "Smart",       detail: "Click a window or drag"},
        {id: "area",        icon: "\u{f0a6d}", label: "Area",        detail: "Drag a rectangle"},
        {id: "area-freeze", icon: "\u{f0717}", label: "Frozen area", detail: "Freeze first, then drag"},
        {id: "w",           icon: "\u{f05af}", label: "Window",      detail: "Pick from visible windows"},
        {id: "m",           icon: "\u{f0379}", label: "Monitor",     detail: "The focused output"},
        {id: "p",           icon: "\u{f037a}", label: "All outputs", detail: "Every monitor at once"}
    ]
    readonly property var destinations: [
        {id: "annotate",  label: "Annotate"},
        {id: "clipboard", label: "Clipboard"},
        {id: "save",      label: "Save"}
    ]

    function shoot() {
        const args = ["hyprshell", "screenshot", target]
        // annotate is the script's default and is not a positional value
        if (destination !== "annotate") args.push(destination)
        shell.run(args)
        shell.closePopup()
    }

    Column {
        id: shotColumn
        anchors.left: parent.left; anchors.right: parent.right; spacing: Style.sm

        PopupSection { shell: root.shell; text: "SCREENSHOT" }

        Column {
            width: parent.width; spacing: 2
            Repeater {
                model: root.targets
                PopupRow {
                    required property var modelData
                    width: shotColumn.width; shell: root.shell
                    icon: modelData.icon
                    title: modelData.label
                    detail: modelData.detail
                    active: root.target === modelData.id
                    onClicked: root.target = modelData.id
                }
            }
        }

        PopupSeparator { shell: root.shell }
        PopupSection { shell: root.shell; text: "GOES TO" }

        Row {
            width: parent.width; spacing: Style.xs
            Repeater {
                model: root.destinations
                PopupRow {
                    required property var modelData
                    width: (shotColumn.width - Style.xs * 2) / 3
                    shell: root.shell
                    centerTitle: true
                    title: modelData.label
                    active: root.destination === modelData.id
                    onClicked: root.destination = modelData.id
                }
            }
        }

        PopupSeparator { shell: root.shell }
        PopupRow {
            width: parent.width; shell: root.shell
            icon: "\u{f0100}"; title: "Take screenshot"
            detail: root.destination === "annotate" ? "Opens the annotator" : "Saves to ~/Pictures"
            onClicked: root.shoot()
        }
    }
}
