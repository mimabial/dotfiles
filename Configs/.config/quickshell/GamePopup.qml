pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "GameModel.js" as Model

PopupCard {
    id: root
    popupName: "games"
    contentWidth: Style.px(400)

    property string configText: ""
    property bool configReady: false
    property string gameModeStatus: ""
    property bool copiedLaunchOptions: false
    property bool metricsExpanded: false
    readonly property var options: Model.parse(configText)
    readonly property bool gameModeActive: /gamemode is active/i.test(gameModeStatus)
    readonly property var metrics: [
        {key: "fps", icon: "󰓅", title: "FPS"},
        {key: "frame_timing", icon: "󰄪", title: "Frametime graph"},
        {key: "gpu_stats", icon: "󰢮", title: "GPU load"},
        {key: "gpu_temp", icon: "󰔏", title: "GPU temperature"},
        {key: "cpu_stats", icon: "󰻠", title: "CPU load"},
        {key: "cpu_temp", icon: "󰔏", title: "CPU temperature"},
        {key: "vram", icon: "󰍛", title: "VRAM"},
        {key: "ram", icon: "󰍛", title: "RAM"},
        {key: "gpu_name", icon: "󰆦", title: "GPU name"},
        {key: "gamemode", icon: "󰊴", title: "GameMode indicator"}
    ]
    readonly property int enabledMetricCount: metrics.filter(metric => Model.enabled(options, metric.key)).length

    function option(key, fallback) { return Model.value(options, key, fallback) }
    function setOption(key, value) {
        if (!configReady) return
        const next = Model.update(configText, key, value)
        if (next === configText) return
        configText = next
        configFile.setText(next)
        Quickshell.execDetached(["mangohudctl", "set", "reload_config", "true"])
    }
    function toggleOption(key) { setOption(key, Model.enabled(options, key) ? "0" : "1") }
    function openLauncher(backend) {
        shell.closePopup()
        shell.run(["hyprshell", "gaming/launcher.sh", "--backend", backend])
    }
    function refreshGameMode() { if (!gameModeProc.running) gameModeProc.running = true }

    onOpenChanged: if (open) { configFile.reload(); refreshGameMode() }

    FileView {
        id: configFile
        path: root.shell.home + "/.config/MangoHud/MangoHud.conf"
        watchChanges: true; printErrors: false; atomicWrites: true
        onLoaded: { root.configText = text(); root.configReady = true }
        onFileChanged: reload()
        onLoadFailed: root.configReady = true
    }

    Process {
        id: gameModeProc
        command: ["gamemoded", "-s"]
        stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.gameModeStatus = text.trim() }
    }
    Timer { interval: 3000; repeat: true; running: root.open; triggeredOnStart: true; onTriggered: root.refreshGameMode() }
    Timer { id: copiedTimer; interval: 2500; onTriggered: root.copiedLaunchOptions = false }

    Flickable {
        id: scroll
        width: parent.width
        height: Math.min(contentColumn.implicitHeight, Math.max(Style.px(220), root.maxHeight - root.padding * 2))
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: PopupScrollBar { shell: root.shell }

        Column {
            id: contentColumn
            width: scroll.width
            spacing: Style.sectionGap

            PopupHero {
                shell: root.shell
                title: "Games"
                status: root.gameModeStatus === "" ? "Checking GameMode…"
                    : root.gameModeActive ? "GameMode active" : "GameMode idle"
            }

            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰊴"; title: "Game library"
                detail: "Launch Steam and Lutris games"
                onClicked: root.openLauncher("all")
            }
            Row {
                width: parent.width; spacing: Style.sm
                PopupRow {
                    width: (parent.width - parent.spacing) / 2; shell: root.shell
                    icon: "󰓓"; title: "Steam"; onClicked: root.openLauncher("steam")
                }
                PopupRow {
                    width: (parent.width - parent.spacing) / 2; shell: root.shell
                    icon: "󰺵"; title: "Lutris"; onClicked: root.openLauncher("lutris")
                }
            }

            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "MANGOHUD SESSION" }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰍹"; title: "Show or hide running HUD"
                detail: "Toggles overlays in running games"
                onClicked: root.shell.run(["mangohudctl", "toggle", "no_display"])
            }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰑓"; title: "Reload running HUD"
                detail: "Apply config after an external edit"
                onClicked: root.shell.run(["mangohudctl", "set", "reload_config", "true"])
            }

            PopupSeparator { shell: root.shell }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰓅"; title: "Displayed metrics"
                detail: root.enabledMetricCount + " of " + root.metrics.length + " shown"
                value: root.metricsExpanded ? "▾" : "▸"
                onClicked: root.metricsExpanded = !root.metricsExpanded
            }
            Column {
                width: parent.width
                visible: root.metricsExpanded
                spacing: Style.xs
                Repeater {
                    model: root.metrics
                    delegate: PopupToggleRow {
                        required property var modelData
                        width: parent.width; shell: root.shell
                        icon: modelData.icon; title: modelData.title
                        checked: Model.enabled(root.options, modelData.key)
                        enabled: root.configReady
                        onToggled: root.toggleOption(modelData.key)
                    }
                }
            }

            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "HUD LAYOUT" }
            PopupToggleRow {
                width: parent.width; shell: root.shell
                icon: "󰕮"; title: "Compact layout"
                checked: Model.enabled(root.options, "hud_compact")
                enabled: root.configReady
                onToggled: root.toggleOption("hud_compact")
            }
            PopupSection { shell: root.shell; text: "POSITION" }
            PopupSelect {
                width: parent.width; shell: root.shell
                enabled: root.configReady
                choices: [
                    {label: "Top left"}, {label: "Top right"},
                    {label: "Bottom left"}, {label: "Bottom right"}
                ]
                selectedIndex: Math.max(0, Model.POSITIONS.indexOf(root.option("position", "top-left")))
                onActivated: index => root.setOption("position", Model.POSITIONS[index])
            }
            Row {
                width: parent.width; spacing: Style.sm
                PopupNumberField {
                    width: (parent.width - parent.spacing) / 2; shell: root.shell
                    label: "FPS cap"; value: Number(root.option("fps_limit", "0")) || 0
                    minimum: 0; maximum: 360; enabled: root.configReady
                    onCommitted: next => root.setOption("fps_limit", String(next))
                }
                PopupNumberField {
                    width: (parent.width - parent.spacing) / 2; shell: root.shell
                    label: "Font size"; value: Number(root.option("font_size", "24")) || 24
                    minimum: 10; maximum: 48; enabled: root.configReady
                    onCommitted: next => root.setOption("font_size", String(next))
                }
            }
            Text {
                width: parent.width
                text: "FPS cap 0 leaves the frame rate unlimited. Per-game MangoHud files can override these global settings."
                textFormat: Text.PlainText; wrapMode: Text.WordWrap
                color: root.shell.alpha(root.shell.foreground, .55)
                font.family: root.shell.fontFamily; font.pixelSize: Style.caption
            }
            PopupSlider {
                width: parent.width; shell: root.shell
                label: "Background opacity"
                value: Math.max(0, Math.min(1, Number(root.option("background_alpha", "0.5"))))
                minimum: 0; maximum: 1; step: 0.05
                valueText: Math.round(value * 100) + "%"
                enabled: root.configReady
                onReleased: next => root.setOption("background_alpha", (Math.round(next * 20) / 20).toFixed(2))
            }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰌋"; title: "HUD hotkey"
                detail: root.option("toggle_hud", "Shift_R+F12")
                interactive: false
            }

            PopupSeparator { shell: root.shell }
            PopupSection { shell: root.shell; text: "GAME SESSION" }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: root.gameModeActive ? "󰊴" : "󰗑"
                title: "GameMode"
                detail: root.gameModeActive ? "A game is using GameMode" : "Starts with gamemoderun for each game"
                active: root.gameModeActive; interactive: false
            }
            PopupRow {
                width: parent.width; shell: root.shell
                icon: "󰆏"; title: "Copy Steam launch options"
                detail: root.copiedLaunchOptions ? "Copied to clipboard" : "gamemoderun mangohud %command%"
                onClicked: {
                    root.shell.run(["wl-copy", "gamemoderun mangohud %command%"])
                    root.copiedLaunchOptions = true
                    copiedTimer.restart()
                }
            }
        }
    }
}
