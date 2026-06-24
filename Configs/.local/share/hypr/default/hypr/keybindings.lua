local vars = require("vars")

local mod = vars.get("mainMod", "SUPER")
local terminal = vars.get("TERMINAL", "kitty")
local terminal2 = vars.get("TERMINAL2", "alacritty")
local explorer = vars.get("EXPLORER", "dolphin")
local browser = vars.get("BROWSER", "firefox")
local editor = vars.get("EDITOR", "nvim")
local bind_actions = {__probe = hl.dsp.no_op()}
_G.HYPR_BIND_ACTIONS = bind_actions

local function chord(modifiers, key)
    local parts = {}
    for item in tostring(modifiers or ""):gsub("%+", " "):gmatch("%S+") do
        parts[#parts + 1] = item
    end
    parts[#parts + 1] = key
    return table.concat(parts, " + ")
end

local function bind(modifiers, key, description, dispatcher, options)
    options = options or {}
    options.description = description
    bind_actions[description] = dispatcher
    hl.bind(chord(modifiers, key), dispatcher, options)
end

local function exec(modifiers, key, description, command, options)
    bind(modifiers, key, description, hl.dsp.exec_cmd(command), options)
end

-- Window management
bind(mod, "Q", "[Window Management] close focused window", hl.dsp.window.close())
bind("ALT", "F4", "[Window Management] close focused window", hl.dsp.window.close())
exec(mod .. " ALT", "Q", "[Window Management] close all windows", "hyprshell window/close-all.sh")
bind(mod, "F", "[Window Management] toggle floating", hl.dsp.window.float({action = "toggle"}))
exec(mod, "P", "[Window Management] toggle pin", "hyprshell window/windowpin.sh")
bind(mod .. " SHIFT", "F", "[Window Management] toggle fullscreen", hl.dsp.window.fullscreen({mode = "fullscreen", action = "toggle"}))
bind(mod .. " ALT", "F", "[Window Management] toggle maximize", hl.dsp.window.fullscreen({mode = "maximized", action = "toggle"}))
bind(mod, "J", "[Window Management] toggle window split", hl.dsp.layout("togglesplit"))
exec(mod .. " SHIFT", "J", "[Window Management] toggle workspace layout", "hyprshell window/layout-toggle.sh")
bind(mod, "PERIOD", "[Window Management] move focused column", hl.dsp.layout("move +col"))
bind(mod, "COMMA", "[Window Management] swap column left", hl.dsp.layout("swapcol l"))

bind(mod, "LEFT", "[Window Management|Focus] focus left", hl.dsp.focus({direction = "left"}))
bind(mod, "RIGHT", "[Window Management|Focus] focus right", hl.dsp.focus({direction = "right"}))
bind(mod, "UP", "[Window Management|Focus] focus up", hl.dsp.focus({direction = "up"}))
bind(mod, "DOWN", "[Window Management|Focus] focus down", hl.dsp.focus({direction = "down"}))
bind("ALT", "TAB", "[Window Management|Focus] cycle next", hl.dsp.window.cycle_next())
bind("ALT SHIFT", "TAB", "[Window Management|Focus] cycle previous", hl.dsp.window.cycle_next({next = false}))
bind("ALT", "TAB", "[Window Management|Focus] reveal active window", hl.dsp.window.bring_to_top())
bind("ALT SHIFT", "TAB", "[Window Management|Focus] reveal active window", hl.dsp.window.bring_to_top())

bind(mod .. " SHIFT", "RIGHT", "[Window Management|Resize] resize right", hl.dsp.window.resize({x = 30, y = 0, relative = true}), {repeating = true})
bind(mod .. " SHIFT", "LEFT", "[Window Management|Resize] resize left", hl.dsp.window.resize({x = -30, y = 0, relative = true}), {repeating = true})
bind(mod .. " SHIFT", "UP", "[Window Management|Resize] resize up", hl.dsp.window.resize({x = 0, y = -30, relative = true}), {repeating = true})
bind(mod .. " SHIFT", "DOWN", "[Window Management|Resize] resize down", hl.dsp.window.resize({x = 0, y = 30, relative = true}), {repeating = true})

local function move_window(direction, x, y)
    return function()
        local window = hl.get_active_window()
        if window and window.floating then
            hl.dispatch(hl.dsp.window.move({x = x, y = y, relative = true}))
        else
            hl.dispatch(hl.dsp.window.move({direction = direction}))
        end
    end
end

bind(mod .. " ALT", "LEFT", "[Window Management|Move] move left", move_window("left", -30, 0), {repeating = true})
bind(mod .. " ALT", "RIGHT", "[Window Management|Move] move right", move_window("right", 30, 0), {repeating = true})
bind(mod .. " ALT", "UP", "[Window Management|Move] move up", move_window("up", 0, -30), {repeating = true})
bind(mod .. " ALT", "DOWN", "[Window Management|Move] move down", move_window("down", 0, 30), {repeating = true})

bind(mod, "mouse:272", "[Window Management|Mouse] move window", hl.dsp.window.drag(), {mouse = true})
bind(mod, "mouse:273", "[Window Management|Mouse] resize window", hl.dsp.window.resize(), {mouse = true})
bind(mod, "Z", "[Window Management|Mouse] move window", hl.dsp.window.drag(), {mouse = true})
bind(mod, "X", "[Window Management|Mouse] resize window", hl.dsp.window.resize(), {mouse = true})

exec(mod, "DELETE", "[Window Management] end session", "hyprshell logout")
exec(mod, "L", "[Window Management] lock screen", "hyprshell lock-screen.sh")
exec("CTRL ALT", "DELETE", "[Window Management] logout menu", "hyprshell logout-launch.sh 2")
exec(mod, "I", "[Window Management] toggle keep awake", "hyprshell session/toggle-keep-awake.sh")

-- Applications and launchers
exec(mod, "RETURN", "[Launcher|Apps] terminal in current directory", terminal .. [[ --working-directory "$(hyprshell terminal-cwd.sh)"]])
exec(mod .. " SHIFT", "RETURN", "[Launcher|Apps] alternate terminal in current directory", terminal2 .. [[ --working-directory "$(hyprshell terminal-cwd.sh)"]])
exec(mod .. " ALT", "RETURN", "[Launcher|Apps] dropdown terminal", "hyprshell window/dropdown-terminal")
exec(mod, "D", "[Launcher|Apps] file explorer", explorer)
exec(mod .. " SHIFT", "D", "[Launcher|Apps] file explorer in current directory", explorer .. [[ "$(hyprshell terminal-cwd.sh)"]])
exec(mod, "B", "[Launcher|Apps] web browser", browser)
exec(mod .. " SHIFT", "B", "[Launcher|Apps] private browser", "hyprshell browser.sh --private")
exec(mod .. " CTRL", "S", "[Launcher|Apps] Signal", "hyprshell launch/summon.sh --empty-workspace-if-occupied class:signal -- signal-desktop")
exec(mod .. " CTRL", "B", "[Launcher|Apps] Bitwarden", "hyprshell launch/summon.sh --align center bitwarden -- bitwarden-desktop")
exec(mod .. " ALT", "G", "[Launcher|Apps] GIMP", "hyprshell launch/summon.sh --empty-workspace-if-occupied gimp -- gimp")
exec(mod, "C", "[Launcher|Apps] text editor", terminal .. " -e " .. editor)

exec(mod, "A", "[Launcher|Menus] application finder", "hyprshell rofi-launch.sh d")
exec(mod .. " CTRL", "TAB", "[Launcher|Menus] window switcher", "hyprshell rofi-launch.sh w")
exec(mod .. " CTRL", "F", "[Launcher|Menus] file finder", "pkill -x rofi || hyprshell launch/file-finder.sh")
exec(mod, "SPACE", "[Launcher|Menus] menu tree", "pkill -x rofi || hyprshell menutree")
exec(mod, "SLASH", "[Launcher|Menus] keybinding hints", "pkill -x rofi || hyprshell keybinds/keybinds_hint.sh")
exec(mod, "E", "[Launcher|Menus] emoji picker", "pkill -x rofi || hyprshell emoji-picker.sh")
exec(mod, "G", "[Launcher|Menus] glyph picker", "pkill -x rofi || hyprshell glyph-picker.sh")
exec(mod, "H", "[Launcher|Menus] box drawing picker", "pkill -x rofi || hyprshell boxdraw-picker.sh")
exec(mod, "V", "[Launcher|Menus] clipboard", "pkill -x rofi || hyprshell cliphist.sh -c")
exec(mod .. " SHIFT", "V", "[Launcher|Menus] clipboard manager", "pkill -x rofi || hyprshell cliphist.sh")

exec(mod .. " CTRL", "G", "[Launcher|Dev Tools] LazyGit", "hyprshell launch/tui.sh --app-id org.tui.LazyGit -- lazygit")
exec(mod .. " CTRL", "D", "[Launcher|Dev Tools] LazyDocker", "hyprshell launch/tui.sh --app-id org.tui.LazyDocker -- lazydocker")
exec(mod .. " CTRL", "T", "[Launcher|Dev Tools] htop", "hyprshell launch/tui.sh --app-id org.tui.Htop -- htop")
exec(mod .. " ALT", "P", "[Launcher|Dev Tools] rmpc", "hyprshell launch/tui.sh --app-id org.tui.Rmpc -- rmpc")

-- Hardware controls
exec(mod .. " SHIFT", "O", "[Hardware|Audio] output switcher", "hyprshell controls/volume-control.sh -t")
exec(mod, "F10", "[Hardware|Audio] mute output", "hyprshell volume-control.sh -o m", {locked = true})
exec(mod .. " CTRL", "F10", "[Hardware|Audio] mute focused window", "hyprshell window-mute.py", {locked = true})
exec("", "XF86AudioMute", "[Hardware|Audio] mute output", "hyprshell volume-control.sh -o m", {locked = true})
exec(mod, "F11", "[Hardware|Audio] volume down", "hyprshell volume-control.sh -o d", {locked = true, repeating = true})
exec(mod, "F12", "[Hardware|Audio] volume up", "hyprshell volume-control.sh -o i", {locked = true, repeating = true})
exec("", "XF86AudioMicMute", "[Hardware|Audio] mute microphone", "hyprshell volume-control.sh -i m", {locked = true})
exec("", "XF86AudioLowerVolume", "[Hardware|Audio] volume down", "hyprshell volume-control.sh -o d", {locked = true, repeating = true})
exec("", "XF86AudioRaiseVolume", "[Hardware|Audio] volume up", "hyprshell volume-control.sh -o i", {locked = true, repeating = true})

exec("", "XF86AudioPlay", "[Hardware|Media] play or pause", "playerctl play-pause", {locked = true})
exec("", "XF86AudioPause", "[Hardware|Media] play or pause", "playerctl play-pause", {locked = true})
exec("", "XF86AudioNext", "[Hardware|Media] next", "playerctl next", {locked = true})
exec("", "XF86AudioPrev", "[Hardware|Media] previous", "playerctl previous", {locked = true})
exec("", "XF86MonBrightnessUp", "[Hardware|Brightness] increase", "hyprshell brightness-control.sh i", {locked = true, repeating = true})
exec("", "XF86MonBrightnessDown", "[Hardware|Brightness] decrease", "hyprshell brightness-control.sh d", {locked = true, repeating = true})

-- Utilities
exec(mod, "K", "[Utilities] switch keyboard layout", "hyprshell keyboard-switch.sh", {locked = true})
exec(mod, "M", "[Utilities] focus mode", "hyprshell util/workflow-toggle.sh focus")
exec(mod .. " SHIFT", "M", "[Utilities] game mode", "hyprshell util/workflow-toggle.sh gaming")
exec(mod .. " SHIFT", "G", "[Utilities] game launcher", "pkill -x rofi || hyprshell gaming/launcher.sh")

exec(mod .. " CTRL", "DELETE", "[Utilities|Monitors] toggle laptop display", "hyprshell system/monitor-internal.sh toggle")
exec(mod .. " CTRL ALT", "DELETE", "[Utilities|Monitors] toggle mirroring", "hyprshell system/monitor-mirror.sh toggle")
exec(mod, "code:51", "[Utilities|Monitors] cycle scale", "hyprshell system/monitor-scale.sh")
exec(mod .. " ALT", "code:51", "[Utilities|Monitors] cycle scale backward", "hyprshell system/monitor-scale.sh --reverse")
exec("", "switch:on:Lid Switch", "[Utilities|Monitors] disable laptop display", "hyprshell system/monitor-internal.sh off", {locked = true})
exec("", "switch:off:Lid Switch", "[Utilities|Monitors] enable laptop display", "hyprshell system/monitor-internal.sh on", {locked = true})

exec(mod .. " SHIFT", "P", "[Utilities|Capture] smart screenshot", "hyprshell screenshot.sh smart")
exec(mod .. " CTRL", "P", "[Utilities|Capture] color picker", "pkill -x rofi || hyprshell rofi/color-picker.sh")
exec("", "Print", "[Utilities|Capture] all monitors", "hyprshell screenshot.sh p", {locked = true})
exec(mod .. " CTRL", "Print", "[Utilities|Capture] extract text", "hyprshell screenshot.sh ocr")
exec(mod .. " SHIFT", "R", "[Utilities|Recording] toggle webcam recording", "hyprshell screenrecord --toggle --audio --webcam")
exec(mod .. " ALT", "R", "[Utilities|Recording] toggle monitor recording", "hyprshell screenrecord --toggle --audio --output")
exec(mod .. " CTRL", "R", "[Utilities|Recording] stop recording", "hyprshell screenrecord --quit")

-- Theme and wallpaper
exec(mod, "APOSTROPHE", "[Theming] next wallpaper", "hyprshell wallpaper next --global")
exec(mod, "SEMICOLON", "[Theming] previous wallpaper", "hyprshell wallpaper previous --global")
exec(mod, "BRACKETRIGHT", "[Theming] next theme", "hyprshell theme.switch.sh -n --quiet")
exec(mod, "BRACKETLEFT", "[Theming] previous theme", "hyprshell theme.switch.sh -p --quiet")
exec(mod, "W", "[Theming] select wallpaper", "hyprshell rofi/run-after-close.sh -- hyprshell wallpaper select --global")
exec(mod, "T", "[Theming] select theme", "hyprshell rofi/run-after-close.sh -- hyprshell theme.select.sh")
exec(mod .. " SHIFT", "COMMA", "[Theming] next Waybar layout", "hyprshell waybar.py --update --next")
exec(mod .. " SHIFT", "PERIOD", "[Theming] previous Waybar layout", "hyprshell waybar.py --update --prev")
exec(mod .. " SHIFT", "W", "[Theming] toggle Waybar", "hyprshell waybar.py --hide")
exec(mod .. " SHIFT", "C", "[Theming] color mode", "pkill -x rofi || hyprshell color-mode.sh -m")
exec(mod, "N", "[Theming] select font", "pkill -x rofi || hyprshell fonts/font-picker.sh")
exec(mod .. " SHIFT", "T", "[Theming] select rofi theme", "hyprshell rofi/run-after-close.sh -- hyprshell theme.select.sh -s")
exec(mod .. " SHIFT", "A", "[Theming] select launcher style", "hyprshell rofi-launch.sh -s")

-- Workspaces
for workspace = 1, 10 do
    local code = "code:" .. tostring(workspace + 9)
    bind(mod, code, "[Workspaces] go to workspace " .. workspace, hl.dsp.focus({workspace = workspace}))
    bind(mod .. " SHIFT", code, "[Workspaces] move window to workspace " .. workspace, hl.dsp.window.move({workspace = workspace}))
    bind(mod .. " ALT", code, "[Workspaces] move window silently to workspace " .. workspace, hl.dsp.window.move({workspace = workspace, follow = false}))
end

bind(mod .. " CTRL", "RIGHT", "[Workspaces] next relative workspace", hl.dsp.focus({workspace = "r+1"}))
bind(mod .. " CTRL", "LEFT", "[Workspaces] previous relative workspace", hl.dsp.focus({workspace = "r-1"}))
bind(mod .. " CTRL", "DOWN", "[Workspaces] nearest empty workspace", hl.dsp.focus({workspace = "empty"}))
bind(mod, "TAB", "[Workspaces] next existing workspace", hl.dsp.focus({workspace = "e+1"}))
bind(mod .. " SHIFT", "TAB", "[Workspaces] previous existing workspace", hl.dsp.focus({workspace = "e-1"}))
bind(mod .. " ALT", "TAB", "[Workspaces] previous workspace", hl.dsp.focus({workspace = "previous"}))

bind(mod .. " SHIFT ALT", "LEFT", "[Workspaces] move workspace left", hl.dsp.workspace.move({monitor = "l"}))
bind(mod .. " SHIFT ALT", "RIGHT", "[Workspaces] move workspace right", hl.dsp.workspace.move({monitor = "r"}))
bind(mod .. " SHIFT ALT", "UP", "[Workspaces] move workspace up", hl.dsp.workspace.move({monitor = "u"}))
bind(mod .. " SHIFT ALT", "DOWN", "[Workspaces] move workspace down", hl.dsp.workspace.move({monitor = "d"}))

bind(mod .. " CTRL ALT", "RIGHT", "[Workspaces] move window to next relative workspace", hl.dsp.window.move({workspace = "r+1"}))
bind(mod .. " CTRL ALT", "LEFT", "[Workspaces] move window to previous relative workspace", hl.dsp.window.move({workspace = "r-1"}))
bind(mod, "mouse_down", "[Workspaces] next existing workspace", hl.dsp.focus({workspace = "e+1"}))
bind(mod, "mouse_up", "[Workspaces] previous existing workspace", hl.dsp.focus({workspace = "e-1"}))
bind(mod .. " SHIFT", "S", "[Workspaces] move to scratchpad", hl.dsp.window.move({workspace = "special"}))
bind(mod .. " ALT", "S", "[Workspaces] move to scratchpad silently", hl.dsp.window.move({workspace = "special", follow = false}))
bind(mod, "S", "[Workspaces] toggle scratchpad", hl.dsp.workspace.toggle_special(""))
