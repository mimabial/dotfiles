pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons

Item {
    id: settingsView

    required property var controller
    required property var hostWindow
    readonly property var slideDirectionOptions: [
        { label: "Left", value: "left" },
        { label: "Right", value: "right" },
        { label: "Up", value: "up" },
        { label: "Down", value: "down" }
    ]





    component SettingsDivider: Rectangle {
        implicitHeight: Math.max(1, Style.normalBorderWidth)
        color: Color.menu.border
    }



    anchors.fill: parent

    function availableFocusItems(candidates) {
        var items = [];
        for (var index = 0; index < candidates.length; index++) {
            var candidate = candidates[index];
            if (candidate && candidate.visible && candidate.enabled)
                items.push(candidate);
        }
        return items;
    }

    function settingsFocusItems() {
        var categoryButton = settingsCategoryRepeater.itemAt(settingsView.controller.settingsCategoryIndex);
        if (settingsView.controller.settingsCategoryIndex === 0)
            return settingsView.availableFocusItems([
                categoryButton,
                backgroundBlurSlider,
                backgroundDimSlider,
                bottomTextToggle
            ]);
        if (settingsView.controller.settingsCategoryIndex === 1)
            return settingsView.availableFocusItems([
                categoryButton,
                hotCornerToggle,
                hotCornerPositionChoices
            ]);
        if (settingsView.controller.settingsCategoryIndex === 2)
            return settingsView.availableFocusItems([
                categoryButton,
                previewPlacementChoices,
                windowFooterChoices,
                movePointerToggle,
                displayModeChoicesControl
            ]);
        return settingsView.availableFocusItems([
            categoryButton,
            motionAnimateButton,
            animationStyleChoices,
            slideDirectionChoices,
            slideDirectionInChoices,
            slideDirectionOutChoices,
            animationSpeedSlider,
            animationInSlider,
            animationOutSlider,
            animationSameSpeedToggle
        ]);
    }

    function footerConfirmationFocusItems() {
        return settingsView.availableFocusItems([
            footerHideAcknowledgement,
            footerHideCancelButton,
            footerHideConfirmButton
        ]);
    }

    function moveFocus(items, forward, forwardFallbackIndex, wrap) {
        if (!items.length)
            return;
        var focusedIndex = -1;
        for (var index = 0; index < items.length; index++) {
            if (items[index].activeFocus) {
                focusedIndex = index;
                break;
            }
        }
        var nextIndex;
        if (focusedIndex < 0)
            nextIndex = forward ? Math.min(forwardFallbackIndex, items.length - 1) : items.length - 1;
        else if (wrap)
            nextIndex = (focusedIndex + (forward ? 1 : items.length - 1)) % items.length;
        else
            nextIndex = focusedIndex + (forward ? 1 : -1);
        if (nextIndex < 0 || nextIndex >= items.length)
            return;
        settingsView.controller.focusSettingsItem(items[nextIndex]);
    }

    function focusSettingsCategory() {
        var categoryButton = settingsCategoryRepeater.itemAt(settingsView.controller.settingsCategoryIndex);
        if (categoryButton)
            categoryButton.forceActiveFocus();
    }

    function moveSettingsFocus(forward, wrap) {
        settingsView.moveFocus(settingsView.settingsFocusItems(), forward, 1, wrap);
    }

    function focusFirstSettingsControl() {
        var items = settingsView.settingsFocusItems();
        if (items.length > 1)
            settingsView.controller.focusSettingsItem(items[1]);
    }

    function moveFooterConfirmationFocus(forward, wrap) {
        settingsView.moveFocus(settingsView.footerConfirmationFocusItems(), forward, 0, wrap);
    }

    MouseArea {
        anchors.fill: parent
        onClicked: settingsView.controller.closeSettings()
    }

    Rectangle {
        id: settingsDialog
        readonly property bool narrow: width < Style.space(760)
        anchors.centerIn: parent
        width: Math.min(Style.space(920), parent.width - Style.space(80))
        height: Math.min(Style.space(narrow ? 720 : 640), parent.height - Style.space(80))
        radius: Style.cornerRadius
        color: Color.menu.background
        border.color: Color.menu.border
        border.width: Math.max(1, Style.normalBorderWidth)
        enabled: !settingsView.controller.footerHideConfirmationOpen

        MouseArea {
            anchors.fill: parent
            onClicked: function (mouse) { mouse.accepted = true; }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(66)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(24)
                    anchors.rightMargin: Style.space(24)
                    spacing: Style.spacing.lg

                    Text {
                        text: "Exposé settings"
                        textFormat: Text.PlainText
                        color: Color.menu.text
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.heading
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "1-4 section   ↑↓ move   ←→ adjust   Esc close"
                        textFormat: Text.PlainText
                        color: Color.menu.text
                        opacity: 0.5
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                    }
                }
            }

            SettingsDivider { Layout.fillWidth: true }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: settingsDialog.narrow ? 1 : 2
                columnSpacing: 0
                rowSpacing: 0

                Item {
                    Layout.fillWidth: settingsDialog.narrow
                    Layout.fillHeight: !settingsDialog.narrow
                    Layout.preferredWidth: settingsDialog.narrow ? 0 : Style.space(218)
                    Layout.preferredHeight: settingsDialog.narrow ? Style.space(54) : 0

                    GridLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        columns: settingsDialog.narrow ? 4 : 1
                        columnSpacing: 0
                        rowSpacing: 0

                        Repeater {
                            id: settingsCategoryRepeater
                            model: [
                                "Appearance",
                                "Hot corner",
                                "Windows",
                                "Motion"
                            ]

                            delegate: SettingsCategoryButton {
                                controller: settingsView.controller
                                required property int index
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(settingsDialog.narrow ? 52 : 48)
                                categoryIndex: index
                                categoryCount: settingsCategoryRepeater.count
                                label: String(modelData)
                                selected: settingsView.controller.settingsCategoryIndex === index
                                horizontal: settingsDialog.narrow
                                onChosen: function (nextIndex) {
                                    settingsView.controller.settingsCategoryIndex = nextIndex;
                                    var nextButton = settingsCategoryRepeater.itemAt(nextIndex);
                                    if (nextButton)
                                        nextButton.forceActiveFocus();
                                }
                                onEntered: settingsView.hostWindow.focusFirstSettingsControl()
                            }
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: settingsDialog.narrow ? parent.width : Math.max(1, Style.normalBorderWidth)
                        height: settingsDialog.narrow ? Math.max(1, Style.normalBorderWidth) : parent.height
                        color: Color.menu.border
                    }
                }

                Item {
                    id: settingsCategoryContent
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    Item {
                        anchors.fill: parent
                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                        visible: settingsView.controller.settingsCategoryIndex === 0
                        enabled: visible

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Style.spacing.md

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacing.xs

                                Text {
                                    text: "Appearance"
                                    textFormat: Text.PlainText
                                    color: Color.accent
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    font.capitalization: Font.AllUppercase
                                }

                                Text {
                                    text: "Backdrop and footer"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.heading
                                    font.bold: true
                                }
                            }

                            Item { Layout.preferredHeight: Style.spacing.sm }
                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Blur"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                SettingSlider {
                                    controller: settingsView.controller
                                    id: backgroundBlurSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 20
                                    value: settingsView.controller.effectiveBackgroundBlur
                                    suffix: " px"
                                    onEdited: function (value) { settingsView.controller.backgroundBlurPreview = value; }
                                    onCommitted: function (value) {
                                        settingsView.controller.backgroundBlurPreview = Math.round(value);
                                        settingsView.controller.setBackgroundBlur(value);
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Dim"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                SettingSlider {
                                    controller: settingsView.controller
                                    id: backgroundDimSlider
                                    Layout.fillWidth: true
                                    from: 0
                                    to: 90
                                    value: settingsView.controller.effectiveBackgroundDim
                                    suffix: "%"
                                    onEdited: function (value) { settingsView.controller.backgroundDimPreview = value; }
                                    onCommitted: function (value) {
                                        settingsView.controller.backgroundDimPreview = Math.round(value);
                                        settingsView.controller.setBackgroundDim(value);
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    text: "Bottom text"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingToggle {
                                    controller: settingsView.controller
                                    id: bottomTextToggle
                                    checked: settingsView.controller.showFooter
                                    onToggled: function (checked) {
                                        if (checked)
                                            settingsView.controller.updatePluginSetting("showFooter", true);
                                        else
                                            settingsView.controller.requestFooterHide();
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                        visible: settingsView.controller.settingsCategoryIndex === 1
                        enabled: visible

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Style.spacing.md

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacing.xs

                                Text {
                                    text: "Hot corner"
                                    textFormat: Text.PlainText
                                    color: Color.accent
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    font.capitalization: Font.AllUppercase
                                }

                                Text {
                                    text: "Overview activation"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.heading
                                    font.bold: true
                                }
                            }

                            Item { Layout.preferredHeight: Style.spacing.sm }
                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    text: "Enabled"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingToggle {
                                    controller: settingsView.controller
                                    id: hotCornerToggle
                                    checked: settingsView.controller.hotCornerEnabled
                                    onToggled: function (checked) { settingsView.controller.setHotCornerEnabled(checked); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Position"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    controller: settingsView.controller
                                    id: hotCornerPositionChoices
                                    value: settingsView.controller.hotCornerPosition
                                    options: [
                                        { label: "TL", value: "top-left" },
                                        { label: "TR", value: "top-right" },
                                        { label: "BL", value: "bottom-left" },
                                        { label: "BR", value: "bottom-right" }
                                    ]
                                    onChosen: function (value) { settingsView.controller.setHotCornerPosition(value); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                        visible: settingsView.controller.settingsCategoryIndex === 2
                        enabled: visible

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Style.spacing.md

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacing.xs

                                Text {
                                    text: "Windows"
                                    textFormat: Text.PlainText
                                    color: Color.accent
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                    font.capitalization: Font.AllUppercase
                                }

                                Text {
                                    text: "Window behavior"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.heading
                                    font.bold: true
                                }
                            }

                            Item { Layout.preferredHeight: Style.spacing.sm }
                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Preview"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    controller: settingsView.controller
                                    id: previewPlacementChoices
                                    value: settingsView.controller.previewPlacement
                                    options: [
                                        { label: "In place", value: "in-place" },
                                        { label: "Centered", value: "centered" }
                                    ]
                                    onChosen: function (value) { settingsView.controller.setPreviewPlacement(value); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Labels"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    controller: settingsView.controller
                                    id: windowFooterChoices
                                    value: settingsView.controller.windowFooterStyle
                                    spacing: Style.spacing.md
                                    options: [
                                        { label: "Floating", value: "floating" },
                                        { label: "Rail", value: "integrated" },
                                        { label: "Overlay", value: "overlay" },
                                        { label: "Centered", value: "centered" }
                                    ]
                                    onChosen: function (value) { settingsView.controller.setWindowFooterStyle(value); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    text: "Move pointer"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingToggle {
                                    controller: settingsView.controller
                                    id: movePointerToggle
                                    checked: settingsView.controller.moveCursorToWindow
                                    onToggled: function (checked) { settingsView.controller.setMoveCursorToWindow(checked); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(76)
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Displays"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                DisplayModeChoices {
                                    controller: settingsView.controller
                                    id: displayModeChoicesControl
                                    Layout.fillWidth: true
                                    value: settingsView.controller.multiMonitorMode
                                    onChosen: function (value) { settingsView.controller.setMultiMonitorMode(value); }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Style.space(settingsDialog.narrow ? 20 : 28)
                        visible: settingsView.controller.settingsCategoryIndex === 3
                        enabled: visible

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Style.spacing.md

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Style.spacing.lg

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Style.spacing.xs

                                    Text {
                                        text: "Motion"
                                        textFormat: Text.PlainText
                                        color: Color.accent
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.caption
                                        font.bold: true
                                        font.capitalization: Font.AllUppercase
                                    }

                                    Text {
                                        text: "Overview transition"
                                        textFormat: Text.PlainText
                                        color: Color.menu.text
                                        font.family: Style.font.menuFamily
                                        font.pixelSize: Style.font.heading
                                        font.bold: true
                                    }
                                }

                                DialogButton {
                                    controller: settingsView.controller
                                    id: motionAnimateButton
                                    label: "Animate"
                                    onClicked: settingsView.controller.previewAnimation()
                                }
                            }

                            Item { Layout.preferredHeight: Style.spacing.sm }
                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Style"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    controller: settingsView.controller
                                    id: animationStyleChoices
                                    value: settingsView.controller.animationStyle
                                    options: [
                                        { label: "Original", value: "original" },
                                        { label: "Fade", value: "fade" },
                                        { label: "Zoom", value: "zoom" },
                                        { label: "Slide", value: "slide" }
                                    ]
                                    onChosen: function (value) {
                                        settingsView.controller.clearAnimationTimingPreview();
                                        settingsView.controller.setAnimationStyle(value);
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationStyle === "slide" && !settingsView.controller.animationTimingFor("slide").separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Direction"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    controller: settingsView.controller
                                    id: slideDirectionChoices
                                    value: String(settingsView.controller.slideDirection["in"])
                                    options: settingsView.slideDirectionOptions
                                    onChosen: function (value) { settingsView.controller.setSlideDirection(value); }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor("slide").separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "In from"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    controller: settingsView.controller
                                    id: slideDirectionInChoices
                                    value: String(settingsView.controller.slideDirection["in"])
                                    options: settingsView.slideDirectionOptions
                                    onChosen: function (value) { settingsView.controller.setSlideDirectionIn(value); }
                                }
                            }

                            SettingsDivider {
                                Layout.fillWidth: true
                                visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor("slide").separate
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationStyle === "slide" && settingsView.controller.animationTimingFor("slide").separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Out to"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingChoices {
                                    controller: settingsView.controller
                                    id: slideDirectionOutChoices
                                    value: String(settingsView.controller.slideDirection["out"])
                                    options: settingsView.slideDirectionOptions
                                    onChosen: function (value) { settingsView.controller.setSlideDirectionOut(value); }
                                }
                            }

                            SettingsDivider {
                                Layout.fillWidth: true
                                visible: settingsView.controller.animationStyle === "slide"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: !settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Speed"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                SettingSlider {
                                    controller: settingsView.controller
                                    id: animationSpeedSlider
                                    Layout.fillWidth: true
                                    from: 100
                                    to: 800
                                    stepSize: 10
                                    value: settingsView.controller.animationInDurationFor(settingsView.controller.animationStyle)
                                    suffix: " ms"
                                    onEdited: function (value) {
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = value;
                                        settingsView.controller.animationOutDurationPreview = value;
                                    }
                                    onCommitted: function (value) {
                                        var next = settingsView.controller.setAnimationDuration(settingsView.controller.animationStyle, value);
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = next;
                                        settingsView.controller.animationOutDurationPreview = next;
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "In"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                SettingSlider {
                                    controller: settingsView.controller
                                    id: animationInSlider
                                    Layout.fillWidth: true
                                    from: 100
                                    to: 800
                                    stepSize: 10
                                    value: settingsView.controller.animationInDurationFor(settingsView.controller.animationStyle)
                                    suffix: " ms"
                                    onEdited: function (value) {
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = value;
                                    }
                                    onCommitted: function (value) {
                                        var next = settingsView.controller.setAnimationDurationIn(settingsView.controller.animationStyle, value);
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationInDurationPreview = next;
                                    }
                                }
                            }

                            SettingsDivider {
                                Layout.fillWidth: true
                                visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                visible: settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
                                Text {
                                    Layout.preferredWidth: Style.space(120)
                                    text: "Out"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                SettingSlider {
                                    controller: settingsView.controller
                                    id: animationOutSlider
                                    Layout.fillWidth: true
                                    from: 100
                                    to: 800
                                    stepSize: 10
                                    value: settingsView.controller.animationOutDurationFor(settingsView.controller.animationStyle)
                                    suffix: " ms"
                                    onEdited: function (value) {
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationOutDurationPreview = value;
                                    }
                                    onCommitted: function (value) {
                                        var next = settingsView.controller.setAnimationDurationOut(settingsView.controller.animationStyle, value);
                                        settingsView.controller.animationDurationPreviewStyle = settingsView.controller.animationStyle;
                                        settingsView.controller.animationOutDurationPreview = next;
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Style.space(48)
                                Text {
                                    text: "Same in and out"
                                    textFormat: Text.PlainText
                                    color: Color.menu.text
                                    font.family: Style.font.menuFamily
                                    font.pixelSize: Style.font.body
                                }
                                Item { Layout.fillWidth: true }
                                SettingToggle {
                                    controller: settingsView.controller
                                    id: animationSameSpeedToggle
                                    checked: !settingsView.controller.animationTimingFor(settingsView.controller.animationStyle).separate
                                    onToggled: function (checked) {
                                        settingsView.controller.clearAnimationTimingPreview();
                                        settingsView.controller.setAnimationTimingSeparate(settingsView.controller.animationStyle, !checked);
                                    }
                                }
                            }

                            SettingsDivider { Layout.fillWidth: true }
                            Item { Layout.fillHeight: true }
                        }
                    }
                }
            }

            SettingsDivider { Layout.fillWidth: true }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(44)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(24)
                    anchors.rightMargin: Style.space(24)
                    spacing: Style.spacing.lg

                    Text {
                        text: "Changes save immediately"
                        textFormat: Text.PlainText
                        color: Color.menu.text
                        opacity: 0.45
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        visible: !settingsDialog.narrow
                        text: "1–4 category   Tab controls"
                        textFormat: Text.PlainText
                        color: Color.menu.text
                        opacity: 0.45
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                    }
                }
            }
        }
    }
    Item {
        id: footerHideConfirmationLayer
        anchors.fill: parent
        visible: settingsView.controller.footerHideConfirmationOpen
        z: 10
        onVisibleChanged: {
            if (visible && settingsView.hostWindow.acceptsKeyboard)
                Qt.callLater(function () {
                    if (footerHideConfirmationLayer.visible)
                        footerHideAcknowledgement.forceActiveFocus();
                });
            else if (!visible && settingsView.controller.settingsOpen && settingsView.hostWindow.acceptsKeyboard)
                Qt.callLater(function () {
                    if (!settingsView.visible || footerHideConfirmationLayer.visible)
                        return;
                    if (settingsView.controller.settingsCategoryIndex === 0
                            && bottomTextToggle.visible && bottomTextToggle.enabled)
                        bottomTextToggle.forceActiveFocus();
                    else
                        settingsView.focusSettingsCategory();
                });
        }

        MouseArea {
            anchors.fill: parent
            onClicked: settingsView.controller.closeFooterHideConfirmation()
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.72
        }

        Rectangle {
            id: footerHideDialog
            anchors.centerIn: parent
            width: Math.min(Style.space(560), parent.width - Style.space(80))
            height: Math.min(parent.height - Style.space(80), footerHideContent.implicitHeight + Style.space(56))
            radius: Style.cornerRadius
            color: Color.menu.background
            border.color: Color.menu.border
            border.width: Math.max(1, Style.normalBorderWidth)

            MouseArea {
                anchors.fill: parent
                onClicked: function (mouse) { mouse.accepted = true; }
            }

            ColumnLayout {
                id: footerHideContent
                anchors.fill: parent
                anchors.margins: Style.space(28)
                spacing: Style.spacing.lg

                Text {
                    Layout.fillWidth: true
                    text: "Hide bottom text?"
                    textFormat: Text.PlainText
                    color: Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.heading
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: "This also hides the Settings link. You can turn it back on while this panel remains open."
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: Color.menu.text
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.body
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: recoveryText.implicitHeight + Style.space(24)
                    color: Color.background
                    border.color: Color.menu.border
                    border.width: Math.max(1, Style.normalBorderWidth)

                    Text {
                        id: recoveryText
                        anchors.fill: parent
                        anchors.margins: Style.space(12)
                        text: "After closing Settings, restore it with: quickshell ipc call expose showFooter on"
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Color.menu.text
                        opacity: 0.72
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                    }
                }

                Item {
                    id: footerHideAcknowledgement
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Style.space(40), acknowledgementText.implicitHeight)
                    activeFocusOnTab: true

                    Keys.onPressed: function (event) {
                        if (settingsView.controller.handleSettingsNavigation(event))
                            return;
                        if (event.key !== Qt.Key_Space && event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter) {
                            event.accepted = false;
                            return;
                        }
                        settingsView.controller.footerHideAcknowledged = !settingsView.controller.footerHideAcknowledged;
                        event.accepted = true;
                    }

                    RowLayout {
                        id: acknowledgementRow
                        anchors.fill: parent
                        spacing: Style.spacing.md

                        Rectangle {
                            Layout.preferredWidth: Style.space(18)
                            Layout.preferredHeight: Style.space(18)
                            color: settingsView.controller.footerHideAcknowledged ? Color.accent : "transparent"
                            border.color: footerHideAcknowledgement.activeFocus || settingsView.controller.footerHideAcknowledged
                                ? Color.accent
                                : Color.menu.border
                            border.width: footerHideAcknowledgement.activeFocus
                                ? Math.max(2, Style.focusBorderWidth)
                                : Math.max(1, Style.normalBorderWidth)

                            Text {
                                anchors.centerIn: parent
                                visible: settingsView.controller.footerHideAcknowledged
                                text: "✓"
                                textFormat: Text.PlainText
                                color: Color.background
                                font.family: Style.font.menuFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                            }
                        }

                        Text {
                            id: acknowledgementText
                            Layout.fillWidth: true
                            text: "I understand that closing Settings while it is hidden requires the IPC command above."
                            textFormat: Text.PlainText
                            wrapMode: Text.WordWrap
                            color: Color.menu.text
                            font.family: Style.font.menuFamily
                            font.pixelSize: Style.font.bodySmall
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: footerHideAcknowledgement.forceActiveFocus()
                        onClicked: settingsView.controller.footerHideAcknowledged = !settingsView.controller.footerHideAcknowledged
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Style.spacing.sm
                    spacing: Style.spacing.md

                    Item { Layout.fillWidth: true }

                    DialogButton {
                        controller: settingsView.controller
                        id: footerHideCancelButton
                        label: "Cancel"
                        onClicked: settingsView.controller.closeFooterHideConfirmation()
                    }

                    DialogButton {
                        controller: settingsView.controller
                        id: footerHideConfirmButton
                        label: "Hide bottom text"
                        destructive: true
                        enabled: settingsView.controller.footerHideAcknowledged
                        onClicked: settingsView.controller.confirmFooterHide()
                    }
                }
            }
        }
    }
}
