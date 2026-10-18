pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs as Active
import qs.Commons as Commons
import qs.Ui as Ui
import "BluetoothModel.js" as Model

Rectangle {
    id: card
    required property var shell
    required property var device
    property bool hiddenDevice: false
    property bool expanded: false
    property bool settingsEnabled: true
    property bool cursored: false
    readonly property var rule: shell.style.box("bluetooth.card" + (device.online ? ".connected" : ""))
    readonly property real pad: Active.Style.px(rule.cardPadding ?? Active.Style.controlPaddingX / Active.Style.uiScale)
    readonly property bool hasSettings: !!(device.dpi || device.smartshift || device.wheel || device.fnswap)
    readonly property bool isOpen: expanded && !!device.online && hasSettings
    readonly property bool navigable: settingsEnabled && !!device.online && hasSettings
    readonly property int lowBatteryPercent: 25
    readonly property int criticalBatteryPercent: 10
    readonly property int dpiFallbackStep: 50
    readonly property var smartshiftLimits: ({minimum: 1, maximum: 50, step: 1, defaultValue: 10})
    signal hiddenToggled(bool value)
    signal expandedToggled()
    signal settingChanged(string key, var value)
    signal clicked(int button)
    onClicked: if (navigable) expandedToggled()
    implicitHeight: cardColumn.implicitHeight + pad * 2
    radius: shell.rounding
    opacity: hiddenDevice ? rule.hiddenOpacity ?? Active.Style.mutedTextAlpha : 1
    color: shell.styleColor(cardHover.hovered ? rule.cardHoverFill : rule.cardFill, "transparent")
    border.width: Commons.Style.normalBorderWidth
    border.color: cursored ? shell.hoverEdge() : shell.styleColor(rule.cardBorder, "transparent")
    HoverHandler { id: cardHover }

    function statusLine() {
        const dev = card.device
        let where = Model.connectionIcon(dev.receiver ? "dongle" : dev.connection) + " " + Model.connectionName(dev.connection)
        if (dev.slot) where += " · slot " + dev.slot
        if (!dev.online) return where + " · not connected"
        const battery = dev.battery
        if (battery && battery.charging) return where + " · charging"
        if (battery && String(battery.status).toLowerCase() === "full" && battery.external_power) return where + " · charged"
        return where + (!battery ? " · no battery reading" : "")
    }
    function batteryIcon() {
        const battery = card.device.battery
        if (!battery) return ""
        if (battery.charging) return "󰂄"
        if (battery.percent === null || battery.percent === undefined)
            return ["critical", "low"].includes(String(battery.level).toLowerCase()) ? "󰁺" : "󰁹"
        const icons = ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        return icons[Math.max(0, Math.min(icons.length - 1, Math.round(battery.percent * (icons.length - 1) / 100)))]
    }
    function batteryColor() {
        const battery = card.device.battery
        if (!battery) return card.shell.mutedText
        if (battery.charging) return card.shell.role("success", card.shell.accent)
        const level = String(battery.level || "").toLowerCase()
        const knownPercent = battery.percent !== null && battery.percent !== undefined
        if (knownPercent ? battery.percent <= criticalBatteryPercent : ["critical", "empty"].includes(level))
            return card.shell.urgent
        if (knownPercent ? battery.percent <= lowBatteryPercent : level === "low")
            return card.shell.role("warning", card.shell.foreground)
        return card.shell.foreground
    }

    Column {
        id: cardColumn
        x: card.pad; y: card.pad
        width: card.width - card.pad * 2; spacing: card.pad

        Item {
            width: parent.width; height: Math.max(badge.height, nameColumn.implicitHeight)
            Rectangle {
                id: badge
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                width: Active.Style.px(card.rule.badgeSize ?? (Active.Style.controlHeight + Active.Style.controlPaddingY) / Active.Style.uiScale)
                height: width; radius: card.shell.rounding > 0 ? width / 2 : 0
                color: card.device.online ? card.shell.accent : card.shell.styleColor(card.rule.badgeFill, "transparent")
                Text {
                    anchors.centerIn: parent; textFormat: Text.PlainText
                    text: Model.monitorKindIcon(card.device.kind)
                    color: card.device.online ? card.shell.background : card.shell.mutedText
                    font.family: card.shell.iconGlyphFont; font.pixelSize: Commons.Style.font.icon
                }
            }
            Column {
                id: nameColumn
                anchors.left: badge.right; anchors.leftMargin: card.pad
                anchors.right: batteryBox.left; anchors.rightMargin: Active.Style.lg
                anchors.verticalCenter: parent.verticalCenter; spacing: Active.Style.xxs
                Text {
                    width: parent.width; textFormat: Text.PlainText; elide: Text.ElideRight
                    text: card.device.name || "Logitech device"
                    color: card.device.online ? card.shell.foreground : card.shell.mutedText
                    font.family: card.shell.fontFamily; font.pixelSize: Active.Style.body; font.bold: true
                }
                Text {
                    width: parent.width; textFormat: Text.PlainText; elide: Text.ElideRight
                    text: card.statusLine() + (card.hiddenDevice ? " · hidden" : "")
                    color: card.shell.mutedText; font.family: card.shell.fontFamily; font.pixelSize: Active.Style.caption
                }
            }
            Row {
                id: batteryBox
                anchors.right: hideButton.left; anchors.rightMargin: Active.Style.md
                anchors.verticalCenter: parent.verticalCenter; spacing: Active.Style.sm
                visible: card.device.online && !!card.device.battery
                width: visible ? implicitWidth : 0
                Text {
                    anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText
                    text: card.batteryIcon(); color: card.batteryColor()
                    font.family: card.shell.iconGlyphFont; font.pixelSize: Active.Style.body
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter; textFormat: Text.PlainText
                    text: Model.batteryText(card.device.battery); color: card.batteryColor()
                    font.family: card.shell.fontFamily; font.pixelSize: Active.Style.caption; font.bold: true
                }
            }
            Ui.PanelActionButton {
                id: hideButton
                anchors.right: chevron.left; anchors.rightMargin: Active.Style.sm
                anchors.verticalCenter: parent.verticalCenter; z: 1
                size: Active.Style.body + Active.Style.xs * 2; fontSize: Active.Style.body
                iconText: card.hiddenDevice ? "󰈈" : "󰈉"; foreground: card.shell.foreground
                fontFamily: card.shell.iconGlyphFont; enabled: card.settingsEnabled
                opacity: card.hiddenDevice || cardHover.hovered || cursored ? 1 : card.rule.eyeIdleOpacity ?? Active.Style.faintTextAlpha
                tooltipText: card.hiddenDevice ? "Show in list" : "Hide from list"
                onClicked: card.hiddenToggled(!card.hiddenDevice)
            }
            Text {
                id: chevron
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                width: Active.Style.xxxl; horizontalAlignment: Text.AlignRight; textFormat: Text.PlainText
                text: card.device.online && card.hasSettings ? card.isOpen ? "󰅀" : "󰅂" : ""
                color: headerMouse.containsMouse ? card.shell.foreground : card.shell.mutedText
                font.family: card.shell.iconGlyphFont; font.pixelSize: Active.Style.body
            }
            MouseArea {
                id: headerMouse
                anchors.fill: parent; enabled: card.navigable; hoverEnabled: true
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: card.expandedToggled()
            }
        }

        Active.PopupSeparator { visible: card.isOpen; shell: card.shell; width: parent.width }
        Active.PopupSlider {
            id: dpiSlider
            visible: card.isOpen && !!card.device.dpi && card.device.dpi.max > 0
            width: parent.width; shell: card.shell; enabled: card.settingsEnabled
            label: "Pointer speed (DPI)"; valueText: Math.round(liveValue) + (card.device.dpi && Math.round(liveValue) === card.device.dpi.default ? " · default" : "")
            minimum: card.device.dpi ? card.device.dpi.min : 0
            maximum: card.device.dpi ? card.device.dpi.max : 1
            step: card.device.dpi && card.device.dpi.step > 0 ? card.device.dpi.step : card.dpiFallbackStep
            value: card.device.dpi ? card.device.dpi.value : 0
            onReleased: value => card.settingChanged("dpi", Math.round(value))
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.RightButton
                onClicked: if (card.device.dpi) card.settingChanged("dpi", card.device.dpi.default)
            }
        }
        Column {
            visible: card.isOpen && !!card.device.smartshift
            width: parent.width; spacing: Active.Style.md
            Text {
                text: "Scroll wheel mode"; color: card.shell.foreground
                font.family: card.shell.fontFamily; font.pixelSize: Active.Style.caption
            }
            Row {
                id: wheelModes
                width: parent.width; spacing: Active.Style.sm
                readonly property var options: [
                    {value: "smartshift", label: "SmartShift", tooltip: "Ratchet that switches to free spin when you flick the wheel"},
                    {value: "ratchet", label: "Ratchet", tooltip: "Always click by click"},
                    {value: "freespin", label: "Free spin", tooltip: "Always spins freely"}
                ]
                readonly property bool navigable: card.settingsEnabled
                property bool cursored: false
                signal clicked(int button)
                onClicked: adjustKeyboard(1)
                function adjustKeyboard(direction) {
                    const index = options.findIndex(option => card.device.smartshift && option.value === card.device.smartshift.mode)
                    card.settingChanged("smartshift", options[(index + direction + options.length) % options.length].value)
                }
                Repeater {
                    model: wheelModes.options
                    Ui.Button {
                        required property var modelData
                        width: (wheelModes.width - wheelModes.spacing * (wheelModes.options.length - 1)) / wheelModes.options.length
                        text: modelData.label; bordered: true
                        selected: !!card.device.smartshift && card.device.smartshift.mode === modelData.value
                        foreground: card.shell.foreground; fontFamily: card.shell.fontFamily; fontSize: Active.Style.caption
                        enabled: card.settingsEnabled; accent: wheelModes.cursored ? card.shell.accent : card.shell.foreground
                        ToolTip.visible: wheelModeHover.hovered; ToolTip.text: modelData.tooltip; ToolTip.delay: Active.Style.tooltipDelay
                        HoverHandler { id: wheelModeHover }
                        onClicked: card.settingChanged("smartshift", modelData.value)
                    }
                }
            }
            Active.PopupSlider {
                id: thresholdSlider
                visible: !!card.device.smartshift && card.device.smartshift.mode === "smartshift"
                width: parent.width; shell: card.shell; enabled: card.settingsEnabled
                label: "Sensitivity"; valueText: Math.round(liveValue)
                minimum: card.smartshiftLimits.minimum; maximum: card.smartshiftLimits.maximum; step: card.smartshiftLimits.step
                value: card.device.smartshift && card.device.smartshift.threshold ? card.device.smartshift.threshold : card.smartshiftLimits.defaultValue
                onReleased: value => card.settingChanged("threshold", Math.round(value))
            }
            Text {
                visible: !!card.device.smartshift && card.device.smartshift.mode === "smartshift"
                width: parent.width; textFormat: Text.PlainText; wrapMode: Text.WordWrap; text: "Lower values switch to free spin with a gentler flick."
                color: card.shell.mutedText; font.family: card.shell.fontFamily; font.pixelSize: Active.Style.caption
            }
        }
        Active.PopupToggleRow {
            visible: card.isOpen && !!card.device.wheel
            width: parent.width; shell: card.shell; enabled: card.settingsEnabled
            title: "Natural scrolling"; detail: "Content follows the wheel, like on a touchpad"
            checked: !!card.device.wheel && card.device.wheel.invert
            onToggled: card.settingChanged("invert", !(card.device.wheel && card.device.wheel.invert))
        }
        Active.PopupToggleRow {
            visible: card.isOpen && !!card.device.wheel
            width: parent.width; shell: card.shell; enabled: card.settingsEnabled
            title: "High-resolution scrolling"; detail: "Smoother, finer steps in apps that support it"
            checked: !!card.device.wheel && card.device.wheel.hires
            onToggled: card.settingChanged("hires", !(card.device.wheel && card.device.wheel.hires))
        }
        Active.PopupToggleRow {
            visible: card.isOpen && !!card.device.fnswap
            width: parent.width; shell: card.shell; enabled: card.settingsEnabled
            title: "Swap Fn keys"; detail: card.device.fnswap && card.device.fnswap.on ? "On: top row gives media and special functions, hold Fn for F1–F12" : "Off: top row gives F1–F12, hold Fn for media and special functions"
            checked: !!card.device.fnswap && card.device.fnswap.on
            onToggled: card.settingChanged("fnswap", !(card.device.fnswap && card.device.fnswap.on))
        }
    }
}
