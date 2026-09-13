pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQml.Models
import QtMultimedia
import Quickshell.Io

Column {
    id: root
    required property var shell
    required property PopupCard card
    spacing: Style.md

    // IR sensors offer only greyscale; QML cannot name QVideoFrameFormat, so 24 and 25 are Format_Y8 and Format_Y16
    readonly property var greyscaleFormats: [24, 25]
    readonly property var inputs: devices.videoInputs.filter(input => input.videoFormats.some(format => !greyscaleFormats.includes(format.pixelFormat)))
    readonly property var input: inputs.find(input => String(input.id) === shell.store.webcamDevice)
        || inputs.find(input => input.isDefault) || inputs[0] || null
    readonly property string device: input ? String(input.id) : ""
    property var controls: []
    property var pendingWrites: ({})
    property string probedDevice: ""
    property string error: ""

    // section names, their order and the renamed labels follow the original plugin
    readonly property var sections: ["EXPOSURE", "IMAGE", "COLOR", "FOCUS", "FRAMING", "ADVANCED"]
    readonly property var labels: ({auto_exposure: "Exposure mode", exposure_auto: "Exposure mode",
        exposure_dynamic_framerate: "Dynamic frame rate", exposure_auto_priority: "Dynamic frame rate",
        white_balance_automatic: "Automatic white balance", white_balance_temperature: "Color temperature",
        power_line_frequency: "Anti-flicker", focus_auto: "Autofocus"})

    onDeviceChanged: { controls = []; pendingWrites = {}; probe() }

    function write(name, value) {
        pendingWrites = Object.assign({}, pendingWrites, {[name]: value})
        probe()
    }
    // v4l2-ctl applies --set-ctrl before listing, so one run writes and reads back new values and flags
    function probe() {
        if (v4l2.running || !device) return
        const writes = Object.entries(pendingWrites).map(([name, value]) => name + "=" + value)
        v4l2.command = ["v4l2-ctl", "-d", device, "--list-ctrls-menus"].concat(writes.length ? ["--set-ctrl", writes.join(",")] : [])
        pendingWrites = {}
        probedDevice = device
        v4l2.running = true
    }
    function parse(text) {
        const controls = []
        for (const line of text.split("\n")) {
            const control = line.match(/^\s*(\w+) 0x\w+ \((\w+)\)\s*:\s*(.*)$/)
            const option = line.match(/^\t+(-?\w+): (.*)$/)
            if (control) controls.push(Object.assign(describe(control[1], control[2], control[3]), {index: controls.length}))
            else if (option && controls.length) controls[controls.length - 1].options.push({value: option[1], label: option[2]})
        }
        return controls.sort((a, b) => a.rank - b.rank || a.index - b.index)
    }
    function describe(name, type, details) {
        const [fields, flags = ""] = details.split(/\s*flags=/)
        const field = key => (fields.match(new RegExp("\\b" + key + "=(\\S+)")) || [])[1]
        const rank = sectionRank(name)
        const control = {name, type, rank, section: sections[rank], flags: flags.split(", "), options: [],
            label: labels[name] || name.replace(/_absolute$/, "").replace(/_/g, " ").replace(/^./, first => first.toUpperCase()),
            min: Number(field("min")), max: Number(field("max")), step: Number(field("step")) || 1,
            def: field("default"), value: field("value")}
        control.enabled = !control.flags.includes("inactive") && !control.flags.includes("grabbed")
        control.kind = kindOf(control)
        return control
    }
    function sectionRank(name) {
        const patterns = [/exposure|gain|iso|scene|backlight|dynamic_range|hdr/, /brightness|contrast|saturation|sharpness|gamma|black_level/,
            /hue|white_balance|red_balance|blue_balance|power_line|colorfx|color_effects/, /focus/, /zoom|pan_|tilt_|flip|rotate|stabilization|privacy/]
        const rank = patterns.findIndex(pattern => pattern.test(name))
        return rank < 0 ? patterns.length : rank
    }
    function kindOf(control) {
        const flag = name => control.flags.includes(name)
        if (flag("read-only") || flag("has-payload") && control.type !== "str") return "value"
        if (control.type === "button" || flag("write-only")) return "action"
        if (control.type === "bool" || control.type === "int" && control.min === 0 && control.max === 1) return "toggle"
        if (control.type === "menu" || control.type === "intmenu") return "menu"
        if (control.type === "int") return "slider"
        return ["int64", "bitmask", "str"].includes(control.type) ? "field" : "value"
    }
    function limitation(control) {
        if (control.flags.includes("grabbed")) return "Temporarily grabbed by the device or another client."
        if (!control.enabled) return "Currently inactive because of another camera setting."
        if (control.kind === "value") return control.flags.includes("has-payload") ? "Complex V4L2 payload; displayed read-only." : "Reported read-only by the device."
        return ""
    }
    // V4L2 units: exposure in 100 µs, pan and tilt in arc seconds
    function format(control, value) {
        const option = control.options.find(option => option.value === String(value))
        if (option) return option.label
        if (/^exposure_(time_)?absolute$/.test(control.name)) return value / 10 + " ms"
        if (control.name === "white_balance_temperature") return value + " K"
        if (/^(pan|tilt)_absolute$/.test(control.name)) return Math.round(value / 3600) + "°"
        return String(value)
    }

    MediaDevices { id: devices }
    Camera { id: camera; cameraDevice: root.input ?? devices.defaultVideoInput; active: root.card.open && root.input !== null }
    CaptureSession { camera: camera; videoOutput: preview }
    Process {
        id: v4l2
        // a rejected write still lists; stdout is empty only when v4l2-ctl refused the whole command
        stdout: StdioCollector { onStreamFinished: if (text && root.probedDevice === root.device) root.controls = root.parse(text) }
        stderr: StdioCollector { onStreamFinished: root.error = text.trim() }
        onExited: if (root.probedDevice !== root.device || Object.keys(root.pendingWrites).length) root.probe()
    }

    Rectangle {
        visible: root.input !== null
        width: parent.width; height: width * 9 / 16
        radius: root.shell.rounding; clip: true
        color: root.shell.alpha(root.shell.foreground, .06)
        border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
        VideoOutput { id: preview; anchors.fill: parent; anchors.margins: parent.border.width; fillMode: VideoOutput.PreserveAspectCrop }
        Rectangle {
            x: Style.lg; y: Style.lg
            width: badge.implicitWidth + Style.xxl; height: badge.implicitHeight + Style.md
            radius: root.shell.rounding; color: Qt.rgba(0, 0, 0, .68)
            Text {
                id: badge
                anchors.centerIn: parent
                text: "PREVIEW · " + (camera.errorString ? "IN USE / ERROR" : "LIVE")
                color: "white"; font.family: root.shell.fontFamily; font.pixelSize: Style.caption; font.bold: true; font.letterSpacing: .8
            }
        }
    }
    PopupHero {
        shell: root.shell; icon: "\u{f0100}"; title: "Webcam Controls"
        status: !root.input ? "No capture device" : root.controls.length ? root.input.description : "Reading camera settings"
        Text {
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0450}"; color: root.shell.foreground; font.family: root.shell.iconGlyphFont; font.pixelSize: Style.title
            MouseArea { anchors.fill: parent; anchors.margins: -Style.sm; cursorShape: Qt.PointingHandCursor; onClicked: root.probe() }
        }
    }
    PopupSection { visible: root.inputs.length > 0; shell: root.shell; text: "CAPTURE DEVICE" }
    PopupSelect {
        visible: root.inputs.length > 0
        width: parent.width; shell: root.shell
        choices: root.inputs.map(input => ({label: input.description + " · " + input.id}))
        selectedIndex: root.inputs.findIndex(input => String(input.id) === root.device)
        onActivated: index => root.shell.store.webcamDevice = String(root.inputs[index].id)
    }
    Text {
        visible: text !== ""
        width: parent.width; text: camera.errorString || root.error; wrapMode: Text.Wrap
        color: root.shell.role("error", root.shell.foreground)
        font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
    }
    ListView {
        id: list
        width: parent.width
        height: Math.min(contentHeight, root.card.maxHeight - root.card.padding * 2 - y)
        clip: true
        spacing: Style.lg
        model: root.controls
        section.property: "section"
        section.delegate: Column {
            id: header
            required property string section
            width: list.width; topPadding: Style.xs; spacing: Style.md
            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: header.section }
        }
        ScrollBar.vertical: PopupScrollBar { shell: root.shell }
        delegate: DelegateChooser {
            role: "kind"
            DelegateChoice {
                roleValue: "slider"
                CameraControl {
                    id: sliderRow
                    PopupSlider {
                        property real dragged: Number(sliderRow.modelData.value)
                        width: parent.width; shell: root.shell
                        label: sliderRow.modelData.label; valueText: root.format(sliderRow.modelData, Math.round(dragged))
                        minimum: sliderRow.modelData.min; maximum: sliderRow.modelData.max; step: sliderRow.modelData.step; value: Number(sliderRow.modelData.value)
                        onChanged: value => dragged = value
                        onReleased: value => root.write(sliderRow.modelData.name, Math.round(value))
                        // double-clicking the header restores the driver default
                        MouseArea { width: parent.width; height: parent.height - Style.sliderHeight; onDoubleClicked: root.write(sliderRow.modelData.name, sliderRow.modelData.def) }
                    }
                }
            }
            DelegateChoice {
                roleValue: "toggle"
                CameraControl {
                    id: toggleRow
                    Rectangle {
                        width: parent.width; height: Style.px(40)
                        radius: root.shell.rounding; color: "transparent"
                        border.color: root.shell.alpha(root.shell.role("br", root.shell.foreground), .3)
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: toggleSwitch.toggled() }
                        Text {
                            anchors.left: parent.left; anchors.leftMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                            text: toggleRow.modelData.label; color: root.shell.foreground
                            font.family: root.shell.fontFamily; font.pixelSize: Style.body; font.bold: true
                        }
                        ToggleSwitch {
                            id: toggleSwitch
                            anchors.right: parent.right; anchors.rightMargin: Style.controlPaddingX; anchors.verticalCenter: parent.verticalCenter
                            shell: root.shell; checked: toggleRow.modelData.value === "1"
                            onToggled: root.write(toggleRow.modelData.name, checked ? 0 : 1)
                        }
                    }
                }
            }
            DelegateChoice {
                roleValue: "menu"
                CameraControl {
                    id: menuRow
                    ControlLabel { text: menuRow.modelData.label }
                    PopupSelect {
                        width: parent.width; shell: root.shell; choices: menuRow.modelData.options
                        selectedIndex: menuRow.modelData.options.findIndex(option => option.value === menuRow.modelData.value)
                        onActivated: index => root.write(menuRow.modelData.name, menuRow.modelData.options[index].value)
                    }
                }
            }
            DelegateChoice {
                roleValue: "field"
                CameraControl {
                    id: fieldRow
                    ControlLabel { text: fieldRow.modelData.label + " · " + root.format(fieldRow.modelData, fieldRow.modelData.value) }
                    PopupField { width: parent.width; shell: root.shell; text: fieldRow.modelData.value; onAccepted: root.write(fieldRow.modelData.name, text) }
                }
            }
            DelegateChoice {
                roleValue: "action"
                CameraControl {
                    id: actionRow
                    PopupRow { width: parent.width; shell: root.shell; title: actionRow.modelData.label; value: "Run"; onClicked: root.write(actionRow.modelData.name, 1) }
                }
            }
            DelegateChoice {
                CameraControl {
                    id: valueRow
                    PopupRow { width: parent.width; shell: root.shell; interactive: false; title: valueRow.modelData.label; value: root.format(valueRow.modelData, valueRow.modelData.value) }
                }
            }
        }
    }

    component CameraControl: Column {
        id: control
        required property var modelData
        default property alias content: body.data
        width: list.width
        spacing: Style.xs
        enabled: modelData.enabled
        opacity: enabled ? 1 : .45
        Column { id: body; width: parent.width; spacing: Style.xs }
        Text {
            visible: text !== ""
            width: parent.width; leftPadding: Style.controlPaddingX; wrapMode: Text.Wrap
            text: root.limitation(control.modelData)
            color: Qt.darker(root.shell.foreground, 1.45); font.family: root.shell.fontFamily; font.pixelSize: Style.caption
        }
    }
    component ControlLabel: Text {
        width: parent ? parent.width : 0; leftPadding: Style.controlPaddingX; elide: Text.ElideRight
        color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.body
    }
}
