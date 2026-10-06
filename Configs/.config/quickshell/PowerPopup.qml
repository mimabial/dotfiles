pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

PopupCard {
    id: root
    popupName: "power"
    contentWidth: Style.px(480)
    contentHeight: panel.implicitHeight + padding * 2
    keyboardHint: "↑↓/Tab move · 1–4 tabs · Enter · Esc"

    property string tab: "overview"
    property int cycles: -1
    property int sysfsStart: -1
    property int sysfsEnd: -1
    property string sleepStates: ""
    property string memoryStates: ""
    property string swapDevices: ""
    property bool resumeConfigured: false
    property var managerConfig: ({})
    property var draftConfig: ({})
    property int draftLimit: -1
    property int limitRequested: -1
    property string limitMessage: ""
    property bool limitBackendReady: false
    readonly property bool configDirty: JSON.stringify(managerConfig) !== JSON.stringify(draftConfig)
    readonly property var profileChoices: [
        { label: "Power saver", value: "power-saver" },
        { label: "Balanced", value: "balanced" }
    ].concat(PowerProfiles.hasPerformanceProfile ? [{ label: "Performance", value: "performance" }] : [])
    readonly property var actionChoices: [
        { label: "Ignore", value: "ignore" },
        { label: "Suspend", value: "suspend" },
        { label: "Hibernate", value: "hibernate" },
        { label: "Suspend then hibernate", value: "suspend-then-hibernate" },
        { label: "Hybrid sleep", value: "hybrid-sleep" },
        { label: "Power off", value: "poweroff" }
    ]
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery && battery.isPresent
    readonly property string sysfs: battery && battery.nativePath ? "/sys/class/power_supply/" + battery.nativePath : ""
    readonly property color accentColor: shell.role("act_br", shell.accent)
    readonly property int thresholdEnd: sysfsEnd
    readonly property string thresholdText: sysfsStart > 0 && sysfsStart < thresholdEnd
        ? sysfsStart + "–" + thresholdEnd + "%" : thresholdEnd > 0 ? thresholdEnd + "%" : "Unavailable"
    readonly property bool discharging: UPower.onBattery
    readonly property bool thresholdActive: hasBattery && !discharging && thresholdEnd > 0 && thresholdEnd < 99
        && Math.round(battery.percentage * 100) >= thresholdEnd && Math.abs(battery.changeRate) <= 0.2
    readonly property bool full: hasBattery && battery.state === UPowerDeviceState.FullyCharged && !thresholdActive
    readonly property string batteryStatus: !hasBattery ? "NO BATTERY DETECTED" : thresholdActive ? "CHARGE LIMIT REACHED"
        : full ? "FULLY CHARGED" : discharging ? "ON BATTERY" : "CHARGING"
    readonly property var tabs: [
        { id: "overview", label: "Overview", icon: "󰂄" },
        { id: "profiles", label: "Profiles", icon: "󰓅" },
        { id: "advanced", label: "Advanced", icon: "󰒓" },
        { id: "diagnostics", label: "Diag.", icon: "󰋽" }
    ]

    function profileId(profile) { return PowerProfile.toString(profile).replace(/([a-z])([A-Z])/g, "$1-$2").toLowerCase() }
    function profileIcon(profile) { return profile === PowerProfile.Performance ? "󱐌" : profile === PowerProfile.PowerSaver ? "󰌪" : "󰗑" }
    function batteryIcon() {
        if (!hasBattery || !discharging && !thresholdActive) return "󰂄"
        const icons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
        return icons[Math.max(0, Math.min(9, Math.floor(battery.percentage * 10)))]
    }
    function batteryTime() {
        if (!hasBattery) return "—"
        if (thresholdActive) return thresholdText
        if (full) return "Full"
        const seconds = discharging ? battery.timeToEmpty : battery.timeToFull
        return seconds > 0 ? shell.duration(seconds) : "—"
    }
    function setting(key, fallback) {
        let current = draftConfig
        for (const part of key.split(".")) {
            if (!current || current[part] === undefined) return fallback
            current = current[part]
        }
        return current
    }
    function setSetting(key, value) {
        const next = JSON.parse(JSON.stringify(draftConfig))
        const parts = key.split(".")
        let current = next
        for (let i = 0; i < parts.length - 1; i++) {
            if (!current[parts[i]] || typeof current[parts[i]] !== "object") current[parts[i]] = ({})
            current = current[parts[i]]
        }
        current[parts[parts.length - 1]] = value
        draftConfig = next
    }
    function saveRules() {
        if (!configDirty) return
        managerFile.setText(JSON.stringify(draftConfig, null, 2) + "\n")
        managerConfig = JSON.parse(JSON.stringify(draftConfig))
        shell.run(["hyprshell", "system/powerprofiles", "--restore"])
        shell.run(["hyprshell", "system/power-manager", "idle-rearm"])
    }
    function applyLimit(limit) {
        const requested = limit === undefined ? draftLimit : limit
        if (!limitBackendReady || !hasBattery || requested < 50 || requested > 100
                || requested === sysfsEnd || limitApply.running) return
        limitMessage = ""
        draftLimit = requested
        limitRequested = requested
        limitApply.command = ["pkexec", "/usr/local/libexec/hypr-power-manager-charge-limit", String(requested), battery.nativePath]
        limitApply.running = true
    }
    function handleKey(event) {
        const index = Number(event.text) - 1
        if (index >= 0 && index < tabs.length) { tab = tabs[index].id; return true }
        return defaultKey(event)
    }
    onOpenChanged: {
        if (!open) return
        tab = "overview"
        draftConfig = JSON.parse(JSON.stringify(managerConfig))
        draftLimit = -1
        limitMessage = ""
        managerFile.reload()
        limitHelperFile.reload()
    }

    Column {
        id: panel
        anchors.left: parent.left; anchors.right: parent.right
        spacing: Style.sectionGap
        PopupHero {
            shell: root.shell; icon: root.batteryIcon(); title: "Power"
            status: (root.hasBattery ? Math.round(root.battery.percentage * 100) + "% · " : "") + root.batteryStatus
        }
        Row {
            width: parent.width; spacing: Style.sm
            Repeater {
                model: root.tabs
                PopupTab {
                    required property var modelData
                    width: (panel.width - Style.sm * (root.tabs.length - 1)) / root.tabs.length
                    shell: root.shell; icon: modelData.icon; text: modelData.label
                    selected: root.tab === modelData.id; onClicked: root.tab = modelData.id
                }
            }
        }
        Flickable {
            id: viewport
            width: parent.width
            height: Math.min(profileLoader.implicitHeight,
                Math.max(0, root.maxHeight - root.keyboardHintHeight - root.padding * 2 - y))
            contentWidth: width
            contentHeight: root.tab === "profiles" ? profileLoader.implicitHeight : tabLoader.implicitHeight
            interactive: contentHeight > height
            clip: true; boundsBehavior: Flickable.StopAtBounds
            onContentHeightChanged: contentY = 0
            Loader {
                id: profileLoader
                width: viewport.width
                visible: root.tab === "profiles"
                sourceComponent: profilesTab
            }
            Loader {
                id: tabLoader
                width: viewport.width
                visible: root.tab !== "profiles"
                sourceComponent: root.tab === "overview" ? overviewTab : root.tab === "advanced" ? advancedTab
                    : root.tab === "diagnostics" ? diagnosticsTab : null
            }
        }
    }

    component RuleSelect: Row {
        id: rule
        property string label: ""
        property string settingKey: ""
        property string fallback: ""
        property var options: []
        width: viewport.width; spacing: Style.md
        Text {
            width: rule.width - selector.width - rule.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: rule.label; color: root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        PopupSelect {
            id: selector
            width: Style.px(172); shell: root.shell; choices: rule.options
            selectedIndex: Math.max(0, rule.options.findIndex(option => option.value === root.setting(rule.settingKey, rule.fallback)))
            onActivated: index => root.setSetting(rule.settingKey, rule.options[index].value)
        }
    }
    component RuleNumber: Row {
        id: rule
        property string label: ""
        property string settingKey: ""
        property int fallback: 0
        property int minimum: 0
        property int maximum: 1440
        width: viewport.width; spacing: Style.md
        Text {
            width: rule.width - field.width - rule.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: rule.label; color: root.shell.foreground
            font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall
        }
        PopupNumberField {
            id: field
            width: Style.px(110); shell: root.shell
            value: Number(root.setting(rule.settingKey, rule.fallback))
            minimum: rule.minimum; maximum: rule.maximum
            onCommitted: value => root.setSetting(rule.settingKey, value)
        }
    }

    Component {
        id: overviewTab
        Column {
            width: viewport.width; spacing: Style.sectionGap
            Rectangle {
                visible: root.hasBattery
                width: parent.width; height: Style.px(8); radius: height / 2
                color: root.shell.alpha(root.shell.foreground, .13)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, root.battery ? root.battery.percentage : 0))
                    height: parent.height; radius: parent.radius; color: root.accentColor
                    Behavior on width { NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic } }
                }
            }
            Rectangle {
                visible: root.hasBattery
                width: parent.width; height: metricGrid.implicitHeight + Style.px(24)
                radius: root.shell.rounding
                color: root.shell.alpha(root.shell.foreground, .04)
                border.color: root.shell.alpha(root.shell.foreground, .09)
                Grid {
                    id: metricGrid
                    anchors.centerIn: parent; width: parent.width - Style.px(24)
                    columns: 2; rowSpacing: Style.lg; columnSpacing: Style.xxl
                    PopupInfoPair { width: (metricGrid.width - metricGrid.columnSpacing) / 2; shell: root.shell; label: "Battery size"; value: root.battery && root.battery.energyCapacity > 0 ? root.battery.energyCapacity.toFixed(1) + " Wh" : "—" }
                    PopupInfoPair { width: (metricGrid.width - metricGrid.columnSpacing) / 2; shell: root.shell; label: root.discharging ? "Time left" : "Time to full"; value: root.batteryTime() }
                    PopupInfoPair { width: (metricGrid.width - metricGrid.columnSpacing) / 2; shell: root.shell; label: "Charge cycles"; value: root.cycles >= 0 ? String(root.cycles) : "—" }
                    PopupInfoPair { width: (metricGrid.width - metricGrid.columnSpacing) / 2; shell: root.shell; label: root.discharging ? "Discharging" : "Charging"; value: root.full ? "—" : root.battery ? Math.abs(root.battery.changeRate).toFixed(1) + " W" : "—" }
                }
            }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "POWER PROFILE" }
                Row {
                    width: parent.width; spacing: Style.sm
                    Repeater {
                        model: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                        PopupTab {
                            required property var modelData
                            width: (viewport.width - Style.sm * (PowerProfiles.hasPerformanceProfile ? 2 : 1)) / (PowerProfiles.hasPerformanceProfile ? 3 : 2)
                            visible: modelData !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                            shell: root.shell; icon: root.profileIcon(modelData); text: root.shell.profileName(modelData)
                            selected: modelData === PowerProfiles.profile
                            onClicked: root.shell.run(["hyprshell", "system/powerprofiles", "--set", root.profileId(modelData)])
                        }
                    }
                }
            }
        }
    }
    Component {
        id: profilesTab
        Column {
            width: viewport.width; spacing: Style.sectionGap
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "ACTIVE PROFILE" }
                Row {
                    width: parent.width; spacing: Style.sm
                    Repeater {
                        model: [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                        PopupTab {
                            required property var modelData
                            width: (viewport.width - Style.sm * (PowerProfiles.hasPerformanceProfile ? 2 : 1)) / (PowerProfiles.hasPerformanceProfile ? 3 : 2)
                            visible: modelData !== PowerProfile.Performance || PowerProfiles.hasPerformanceProfile
                            shell: root.shell; icon: root.profileIcon(modelData); text: root.shell.profileName(modelData)
                            selected: modelData === PowerProfiles.profile
                            onClicked: root.shell.run(["hyprshell", "system/powerprofiles", "--set", root.profileId(modelData)])
                        }
                    }
                }
            }
            PopupSeparator { shell: root.shell }
            PopupToggleRow {
                width: parent.width; shell: root.shell
                title: "Automatic management"
                detail: "Off keeps your existing power behavior"
                checked: root.setting("enabled", false)
                onToggled: root.setSetting("enabled", !checked)
            }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "AUTOMATIC PROFILE RULES" }
                RuleSelect { label: "On AC power"; settingKey: "profiles.ac"; fallback: "balanced"; options: root.profileChoices }
                RuleSelect { label: "Battery high"; settingKey: "profiles.batteryHigh"; fallback: "balanced"; options: root.profileChoices }
                RuleSelect { label: "Battery low"; settingKey: "profiles.batteryLow"; fallback: "power-saver"; options: root.profileChoices }
                RuleNumber { label: "Low battery threshold (%)"; settingKey: "batteryThreshold"; fallback: 20; minimum: 5; maximum: 95 }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: "With automatic management off, the existing AC and battery choices are still restored."; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
                PopupRow { width: parent.width; shell: root.shell; icon: "󰆓"; title: "Apply profile rules"; detail: root.configDirty ? "Save changes" : "Up to date"; interactive: root.configDirty; onClicked: root.saveRules() }
            }
        }
    }
    Component {
        id: advancedTab
        Column {
            width: viewport.width; spacing: Style.sectionGap
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "BATTERY PROTECTION" }
                PopupInfoPair { shell: root.shell; label: "Charge limit"; value: root.thresholdText }
                PopupRow {
                    visible: root.sysfsEnd > 0
                    width: parent.width; shell: root.shell; icon: "󰂄"; title: "Stop charging at 80%"
                    detail: root.sysfsEnd === 80 ? "Active · restart level set by hardware"
                        : !root.limitBackendReady ? "Privileged helper not installed"
                        : limitApply.running ? "Applying…" : "Restart level set by hardware · authentication required"
                    active: root.sysfsEnd === 80
                    interactive: root.limitBackendReady && root.hasBattery && root.sysfsEnd !== 80 && !limitApply.running
                    onClicked: root.applyLimit(80)
                }
                Row {
                    visible: root.sysfsEnd > 0
                    width: parent.width; spacing: Style.md
                    Text { width: parent.width - limitField.width - parent.spacing; anchors.verticalCenter: parent.verticalCenter; text: "Charge cut-off (%)"; color: root.shell.foreground; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
                    PopupNumberField {
                        id: limitField
                        width: Style.px(110); shell: root.shell
                        value: root.draftLimit >= 0 ? root.draftLimit : root.sysfsEnd
                        minimum: 50; maximum: 100
                        onCommitted: value => root.draftLimit = value
                    }
                }
                PopupRow {
                    visible: root.sysfsEnd > 0
                    width: parent.width; shell: root.shell; icon: "󰆓"; title: "Apply charge limit"
                    detail: root.limitBackendReady ? (root.draftLimit < 0 || root.draftLimit === root.sysfsEnd ? "Up to date" : "Authentication required") : "Privileged helper not installed"
                    interactive: root.limitBackendReady && root.draftLimit >= 50 && root.draftLimit !== root.sysfsEnd && !limitApply.running
                    onClicked: root.applyLimit()
                }
                Text { visible: root.limitMessage !== ""; width: parent.width; text: root.limitMessage; color: root.shell.role("error", root.shell.foreground); font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
            }
            PopupSeparator { shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "SLEEP AFTER INACTIVITY" }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: "The existing 500 second suspend remains active until automatic management is enabled."; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
            }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "AC POWER" }
                RuleNumber { label: "Minutes before sleep"; settingKey: "idle.ac.sleepAfterMinutes"; fallback: 30; minimum: 1 }
                RuleSelect { label: "Action"; settingKey: "idle.ac.action"; fallback: "suspend"; options: root.actionChoices }
            }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "BATTERY HIGH" }
                RuleNumber { label: "Minutes before sleep"; settingKey: "idle.batteryHigh.sleepAfterMinutes"; fallback: 15; minimum: 1 }
                RuleSelect { label: "Action"; settingKey: "idle.batteryHigh.action"; fallback: "suspend"; options: root.actionChoices }
            }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "BATTERY LOW" }
                RuleNumber { label: "Minutes before sleep"; settingKey: "idle.batteryLow.sleepAfterMinutes"; fallback: 5; minimum: 1 }
                RuleSelect { label: "Action"; settingKey: "idle.batteryLow.action"; fallback: "suspend"; options: root.actionChoices }
            }
            PopupSeparator { shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "WHEN LID CLOSES" }
                PopupToggleRow { width: parent.width; shell: root.shell; title: "Ignore lid close"; checked: root.setting("lid.ignoreLidClose", false); onToggled: root.setSetting("lid.ignoreLidClose", !checked) }
                RuleSelect { label: "On AC power"; settingKey: "lid.ac.action"; fallback: "suspend"; options: root.actionChoices }
                RuleSelect { label: "Battery high"; settingKey: "lid.batteryHigh.action"; fallback: "suspend"; options: root.actionChoices }
                RuleSelect { label: "Battery low"; settingKey: "lid.batteryLow.action"; fallback: "suspend"; options: root.actionChoices }
                PopupRow { width: parent.width; shell: root.shell; icon: "󰆓"; title: "Apply sleep and lid rules"; detail: root.configDirty ? "Save changes" : "Up to date"; interactive: root.configDirty; onClicked: root.saveRules() }
            }
        }
    }
    Component {
        id: diagnosticsTab
        Column {
            width: viewport.width; spacing: Style.sectionGap
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "SLEEP STATES" }
                PopupInfoPair { shell: root.shell; label: "Suspend"; value: root.sleepStates.split(/\s+/).includes("mem") ? "Available" : "Unavailable" }
                PopupInfoPair { shell: root.shell; label: "Hibernate"; value: root.sleepStates.split(/\s+/).includes("disk") ? "Kernel supports it" : "Unavailable" }
                PopupInfoPair { shell: root.shell; label: "Memory sleep"; value: root.memoryStates || "Unavailable" }
            }
            PopupSeparator { shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "HIBERNATION CHECKS" }
                PopupInfoPair { shell: root.shell; label: "Swap"; value: root.swapDevices ? "Configured" : "No active swap" }
                PopupInfoPair { shell: root.shell; label: "Resume parameter"; value: root.resumeConfigured ? "Configured" : "Not found" }
                Text { width: parent.width; wrapMode: Text.WordWrap; text: "Kernel support alone does not confirm that hibernation can resume successfully."; color: root.shell.mutedText; font.family: root.shell.fontFamily; font.pixelSize: Style.bodySmall }
            }
            PopupSeparator { shell: root.shell }
            Column {
                width: parent.width; spacing: Style.sm
                PopupSection { shell: root.shell; text: "SYSTEM" }
                PopupInfoPair { shell: root.shell; label: "Profile interface"; value: "UPower PowerProfiles" }
                PopupInfoPair { shell: root.shell; label: "Active profile"; value: root.profileId(PowerProfiles.profile) }
            }
        }
    }

    FileView {
        path: root.sysfs ? root.sysfs + "/cycle_count" : ""
        watchChanges: root.sysfs !== ""; printErrors: false
        onFileChanged: reload()
        onLoaded: root.cycles = parseInt(text()) || 0
    }
    FileView {
        path: root.sysfs ? root.sysfs + "/charge_control_start_threshold" : ""
        watchChanges: root.sysfs !== ""; printErrors: false
        onFileChanged: reload()
        onLoaded: root.sysfsStart = parseInt(text()) || -1
    }
    FileView {
        id: thresholdFile
        path: root.sysfs ? root.sysfs + "/charge_control_end_threshold" : ""
        watchChanges: root.sysfs !== ""; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.sysfsEnd = parseInt(text()) || -1
            if (root.limitRequested < 0) return
            if (root.sysfsEnd === root.limitRequested) root.draftLimit = -1
            else root.limitMessage = "Charge limit was not applied."
            root.limitRequested = -1
        }
    }
    FileView {
        id: managerFile
        path: root.shell.home + "/.config/quickshell/power-manager.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const dirty = root.configDirty
                const loaded = JSON.parse(text())
                root.managerConfig = loaded
                if (!dirty) root.draftConfig = JSON.parse(JSON.stringify(loaded))
            } catch (error) { console.warn("power manager settings: " + error) }
        }
    }
    FileView {
        id: limitHelperFile
        path: "/usr/local/libexec/hypr-power-manager-charge-limit"
        watchChanges: true; printErrors: false
        onLoaded: root.limitBackendReady = true
    }
    Process {
        id: limitApply
        onRunningChanged: {
            if (running || root.limitRequested < 0) return
            thresholdFile.reload()
        }
    }
    FileView { path: "/sys/power/state"; printErrors: false; onLoaded: root.sleepStates = String(text()).trim() }
    FileView { path: "/sys/power/mem_sleep"; printErrors: false; onLoaded: root.memoryStates = String(text()).trim() }
    FileView { path: "/proc/swaps"; printErrors: false; onLoaded: root.swapDevices = String(text()).trim().split("\n").slice(1).filter(Boolean).join(", ") }
    FileView { path: "/proc/cmdline"; printErrors: false; onLoaded: root.resumeConfigured = /(?:^|\s)resume=\S+/.test(String(text())) }
}
