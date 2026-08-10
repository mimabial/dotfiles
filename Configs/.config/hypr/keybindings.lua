local vars = require("vars")

local mod = vars.get("mainMod", "SUPER")
local terminal = vars.get("TERMINAL", "kitty")
local terminal2 = vars.get("TERMINAL2", "alacritty")
local explorer = vars.get("EXPLORER", "dolphin")
local browser = vars.get("BROWSER", "firefox")
local editor = vars.get("EDITOR", "nvim")
local bind_actions = { __probe = hl.dsp.no_op() }
_G.HYPR_BIND_ACTIONS = bind_actions

-- Modifier meanings, applied to letters, arrows and workspace numbers:
--   mod        primary action for the key, or a submap leader
--   mod SHIFT  the other/stronger version of that key's action
--   mod ALT    same action, without following the window
--   mod CTRL   relative/scoped navigation
-- Function, XF86, mouse and Print keys are a hardware class and sit outside it.

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

-- Submaps give each domain its own key namespace, so no bind needs punctuation.
-- That matters here: resolve_binds_by_sym resolves against the active layout's
-- level-1 keysym, and AZERTY puts . / [ ] above level 1, where it cannot reach.
local SUBMAP_MARKER = "[Submap] "

-- Number row, left to right: workspace 1 sits on keycode 10 and workspace 10 on
-- keycode 19, the "0" key. Digits share the punctuation problem above -- AZERTY
-- reaches them at level 2 -- so these bind by keycode, which no layout remaps.
local function workspace_code(workspace)
	return "code:" .. tostring(workspace + 9)
end

-- The leader is tagged with SUBMAP_MARKER because the Lua plugin reports every
-- bind as dispatcher "__lua"; keybinds_hint pairs inner binds back to the key
-- that enters them via this description, not via hyprctl's dispatcher field.
local function submap_leader(name, modifiers, key, body)
	bind(modifiers, key, SUBMAP_MARKER .. name, hl.dsp.submap(name))
	hl.define_submap(name, function()
		body()
		hl.bind("ESCAPE", hl.dsp.submap("reset"), { description = "[" .. name .. "] exit" })
	end)
end

local function run_action(action)
	if type(action) == "function" then
		action()
	else
		hl.dispatch(action)
	end
end

-- Leaves the submap before acting: inner binds are bare keys, so staying would
-- swallow the keystrokes rofi needs. bind_actions keeps the bare dispatcher so
-- keybinds_hint can run the action without entering the submap.
local function submap_action(key, description, dispatcher)
	bind_actions[description] = dispatcher
	hl.bind(key, function()
		hl.dispatch(hl.dsp.submap("reset"))
		run_action(dispatcher)
	end, { description = description })
end

local function submap_exec(key, description, command)
	submap_action(key, description, hl.dsp.exec_cmd(command))
end

local function submap_stay_action(key, description, dispatcher, options)
	options = options or {}
	options.description = description
	bind_actions[description] = dispatcher
	hl.bind(key, dispatcher, options)
end

local function submap_stay_exec(key, description, command)
	submap_stay_action(key, description, hl.dsp.exec_cmd(command))
end

-- Stays in the submap, for repeat actions that never open a picker.
local function submap_repeat_action(key, description, dispatcher)
	submap_stay_action(key, description, dispatcher, { repeating = true })
end

local function submap_cycle(key, description, command)
	submap_repeat_action(key, description, hl.dsp.exec_cmd(command))
end

local function layout_action(layout, action)
	return function()
		local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
		if not workspace or workspace.tiled_layout ~= layout then
			return
		end
		run_action(action)
	end
end

-- Window management
local function usable_area(monitor)
	local scale = monitor.scale
	if not scale or scale <= 0 then
		scale = 1
	end

	local width, height = monitor.size.width / scale, monitor.size.height / scale
	if (monitor.transform or 0) % 2 == 1 then
		width, height = height, width
	end

	local reserved = monitor.reserved
	local border = hl.get_config("general:border_size") or 0
	return width - reserved.left - reserved.right - 2 * border,
		height - reserved.top - reserved.bottom - 2 * border
end

-- Hyprland only sometimes restores a window's pre-tile floating size, so one tiled
-- alone re-floats at the whole usable area. Keep our own record, keyed by address.
local float_geometry = {}
local FLOAT_FALLBACK_FRACTION = 0.9

local function clamp_floating_size(window, selector)
	local max_width, max_height = usable_area(window.monitor)
	local width = math.min(window.size.x, max_width)
	local height = math.min(window.size.y, max_height)
	if width == window.size.x and height == window.size.y then
		return
	end

	hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false, window = selector }))
end

local function restore_float_size(window, selector)
	local remembered = float_geometry[window.address]
	if remembered then
		float_geometry[window.address] = nil
		hl.dispatch(hl.dsp.window.resize({ x = remembered.x, y = remembered.y, relative = false, window = selector }))
		local floated = hl.get_window(selector)
		if floated then
			clamp_floating_size(floated, selector)
		end
		return
	end

	-- Nothing remembered: reuse the tiled footprint, capped so a window that was
	-- tiled alone does not float at full screen.
	local max_width, max_height = usable_area(window.monitor)
	local width = math.min(window.size.x, math.floor(max_width * FLOAT_FALLBACK_FRACTION))
	local height = math.min(window.size.y, math.floor(max_height * FLOAT_FALLBACK_FRACTION))
	hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false, window = selector }))
end

local function toggle_floating()
	local window = hl.get_active_window()
	if not window then
		return
	end

	local selector = "address:" .. window.address
	local was_floating = window.floating

	if was_floating then
		float_geometry[window.address] = { x = window.size.x, y = window.size.y }
	end

	hl.dispatch(hl.dsp.window.float({ action = "toggle", window = selector }))

	if not was_floating then
		restore_float_size(window, selector)
		hl.dispatch(hl.dsp.window.center({ window = selector, respect_reserved = true }))
		hl.dispatch(hl.dsp.window.alter_zorder({ window = selector, mode = "top" }))
	end
end

bind(mod, "Q", "[Window Management] close focused window", hl.dsp.window.close())
bind("ALT", "F4", "[Window Management] close focused window", hl.dsp.window.close())
bind(mod .. " SHIFT", "Q", "[Window Management] force kill focused window", hl.dsp.window.kill())
bind(
	mod,
	"F",
	"[Window Management] toggle fullscreen",
	hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })
)
bind(
	mod,
	"M",
	"[Window Management] toggle maximize",
	hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })
)
exec(mod, "P", "[Window Management] toggle pin", "hyprshell window/windowpin.sh")
bind(mod, "G", "[Window Management] toggle group", hl.dsp.group.toggle())

bind(mod, "LEFT", "[Window Management|Focus] focus left", hl.dsp.focus({ direction = "left" }))
bind(mod, "RIGHT", "[Window Management|Focus] focus right", hl.dsp.focus({ direction = "right" }))
bind(mod, "UP", "[Window Management|Focus] focus up", hl.dsp.focus({ direction = "up" }))
bind(mod, "DOWN", "[Window Management|Focus] focus down", hl.dsp.focus({ direction = "down" }))

local function cycle_window(options)
	return function()
		hl.dispatch(hl.dsp.window.cycle_next(options))
		hl.dispatch(hl.dsp.window.bring_to_top())
	end
end

bind("ALT", "TAB", "[Window Management|Focus] cycle next and reveal", cycle_window())
bind("ALT SHIFT", "TAB", "[Window Management|Focus] cycle previous and reveal", cycle_window({ next = false }))

local function move_window(direction, x, y)
	return function()
		local window = hl.get_active_window()
		if window and window.floating then
			hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = true }))
		else
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
		end
	end
end

local function resize_window(x, y)
	return function()
		local window = hl.get_active_window()
		if not window then
			return
		end

		if window.floating then
			local max_width, max_height = usable_area(window.monitor)
			local width = math.min(window.size.x + x, max_width)
			local height = math.min(window.size.y + y, max_height)
			hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false }))
			return
		end

		hl.dispatch(hl.dsp.window.resize({ x = x, y = y, relative = true }))
	end
end

bind(mod .. " SHIFT", "LEFT", "[Window Management|Move] move left", move_window("left", -30, 0), { repeating = true })
bind(mod .. " SHIFT", "RIGHT", "[Window Management|Move] move right", move_window("right", 30, 0), { repeating = true })
bind(mod .. " SHIFT", "UP", "[Window Management|Move] move up", move_window("up", 0, -30), { repeating = true })
bind(mod .. " SHIFT", "DOWN", "[Window Management|Move] move down", move_window("down", 0, 30), { repeating = true })

bind(mod, "mouse:272", "[Window Management|Mouse] move window", hl.dsp.window.drag(), { mouse = true })
bind(mod, "mouse:273", "[Window Management|Mouse] resize window", hl.dsp.window.resize(), { mouse = true })
bind(mod, "Z", "[Window Management|Mouse] move window", hl.dsp.window.drag(), { mouse = true })
bind(mod, "X", "[Window Management|Mouse] resize window", hl.dsp.window.resize(), { mouse = true })

exec(mod, "L", "[Window Management] lock screen", "hyprshell lock-screen.sh")
exec("CTRL ALT", "DELETE", "[Window Management] logout menu", "hyprshell logout-launch.sh 2")
exec(mod, "ESCAPE", "[Window Management] logout menu", "hyprshell logout-launch.sh 2")

-- Applications and launchers
exec(
	mod,
	"RETURN",
	"[Launcher|Apps] terminal in current directory",
	terminal .. [[ --working-directory "$(hyprshell terminal-cwd.sh)"]]
)
exec(
	mod .. " SHIFT",
	"RETURN",
	"[Launcher|Apps] alternate terminal in current directory",
	terminal2 .. [[ --working-directory "$(hyprshell terminal-cwd.sh)"]]
)
exec(mod, "E", "[Launcher|Apps] file explorer", explorer)
exec(
	mod .. " SHIFT",
	"E",
	"[Launcher|Apps] file explorer in current directory",
	explorer .. [[ "$(hyprshell terminal-cwd.sh)"]]
)
exec(mod, "B", "[Launcher|Apps] web browser", browser)
exec(mod .. " SHIFT", "B", "[Launcher|Apps] private browser", "hyprshell browser.sh --private")
exec(mod, "C", "[Launcher|Apps] text editor", terminal .. " -e " .. editor)

exec(mod, "D", "[Launcher|Menus] application finder", "hyprshell rofi-launch.sh d")
exec(mod .. " SHIFT", "D", "[Launcher|Menus] window switcher", "hyprshell rofi-launch.sh w")
exec(mod, "SPACE", "[Launcher|Menus] menu tree", "pkill -x rofi || hyprshell menutree")
exec(mod, "H", "[Launcher|Menus] keybinding hints", "pkill -x rofi || hyprshell keybinds/keybinds_hint.sh")
exec(mod, "V", "[Launcher|Menus] clipboard", "pkill -x rofi || hyprshell cliphist.sh -c")
exec(mod .. " SHIFT", "V", "[Launcher|Menus] clipboard manager", "pkill -x rofi || hyprshell cliphist.sh")

-- Hardware controls
exec(mod, "F10", "[Hardware|Audio] mute output", "hyprshell volume-control.sh -o m", { locked = true })
exec(mod .. " CTRL", "F10", "[Hardware|Audio] mute focused window", "hyprshell window-mute.py", { locked = true })
exec("", "XF86AudioMute", "[Hardware|Audio] mute output", "hyprshell volume-control.sh -o m", { locked = true })
exec(
	mod,
	"F11",
	"[Hardware|Audio] volume down",
	"hyprshell volume-control.sh -o d",
	{ locked = true, repeating = true }
)
exec(mod, "F12", "[Hardware|Audio] volume up", "hyprshell volume-control.sh -o i", { locked = true, repeating = true })
exec("", "XF86AudioMicMute", "[Hardware|Audio] mute microphone", "hyprshell volume-control.sh -i m", { locked = true })
exec(
	"",
	"XF86AudioLowerVolume",
	"[Hardware|Audio] volume down",
	"hyprshell volume-control.sh -o d",
	{ locked = true, repeating = true }
)
exec(
	"",
	"XF86AudioRaiseVolume",
	"[Hardware|Audio] volume up",
	"hyprshell volume-control.sh -o i",
	{ locked = true, repeating = true }
)

exec("", "XF86AudioPlay", "[Hardware|Media] play or pause", "playerctl play-pause", { locked = true })
exec("", "XF86AudioPause", "[Hardware|Media] play or pause", "playerctl play-pause", { locked = true })
exec("", "XF86AudioNext", "[Hardware|Media] next", "playerctl next", { locked = true })
exec("", "XF86AudioPrev", "[Hardware|Media] previous", "playerctl previous", { locked = true })
exec(
	"",
	"XF86MonBrightnessUp",
	"[Hardware|Brightness] increase",
	"hyprshell brightness-control.sh i",
	{ locked = true, repeating = true }
)
exec(
	"",
	"XF86MonBrightnessDown",
	"[Hardware|Brightness] decrease",
	"hyprshell brightness-control.sh d",
	{ locked = true, repeating = true }
)

exec("", "Print", "[Utilities|Capture] all monitors", "hyprshell screenshot.sh p", { locked = true })
-- The compositor sees the switch itself, so locking here needs no init system and
-- survives caffeine stopping hypridle.
exec(
	"",
	"switch:on:Lid Switch",
	"[Utilities|Session] lid close: lock and suspend",
	"hyprshell session/lid-close.sh",
	{ locked = true }
)
-- Stays top-level and locked: the layout must be switchable on the lock screen.
exec(mod, "K", "[Utilities] switch keyboard layout", "hyprshell keyboard-switch.sh", { locked = true })

submap_leader("window", mod, "W", function()
	submap_repeat_action("LEFT", "[Window Mode|Focus] focus left", hl.dsp.focus({ direction = "left" }))
	submap_repeat_action("RIGHT", "[Window Mode|Focus] focus right", hl.dsp.focus({ direction = "right" }))
	submap_repeat_action("UP", "[Window Mode|Focus] focus up", hl.dsp.focus({ direction = "up" }))
	submap_repeat_action("DOWN", "[Window Mode|Focus] focus down", hl.dsp.focus({ direction = "down" }))

	submap_repeat_action("SHIFT + LEFT", "[Window Mode|Move] move left", move_window("left", -30, 0))
	submap_repeat_action("SHIFT + RIGHT", "[Window Mode|Move] move right", move_window("right", 30, 0))
	submap_repeat_action("SHIFT + UP", "[Window Mode|Move] move up", move_window("up", 0, -30))
	submap_repeat_action("SHIFT + DOWN", "[Window Mode|Move] move down", move_window("down", 0, 30))

	submap_repeat_action("CTRL + LEFT", "[Window Mode|Resize] shrink width", resize_window(-30, 0))
	submap_repeat_action("CTRL + RIGHT", "[Window Mode|Resize] grow width", resize_window(30, 0))
	submap_repeat_action("CTRL + UP", "[Window Mode|Resize] shrink height", resize_window(0, -30))
	submap_repeat_action("CTRL + DOWN", "[Window Mode|Resize] grow height", resize_window(0, 30))

	submap_stay_action("F", "[Window Mode|State] toggle floating", toggle_floating)
	submap_stay_action(
		"M",
		"[Window Mode|State] toggle maximize",
		hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })
	)
	submap_stay_action("G", "[Window Mode|State] toggle group", hl.dsp.group.toggle())
	submap_stay_exec("P", "[Window Mode|State] toggle pin", "hyprshell window/windowpin.sh")

	for workspace = 1, 10 do
		local code = workspace_code(workspace)
		submap_stay_action(
			code,
			"[Window Mode|Workspace] go to workspace " .. workspace,
			hl.dsp.focus({ workspace = workspace })
		)
		submap_stay_action(
			"SHIFT + " .. code,
			"[Window Mode|Workspace] move window to workspace " .. workspace,
			hl.dsp.window.move({ workspace = workspace })
		)
		submap_stay_action(
			"ALT + " .. code,
			"[Window Mode|Workspace] move window silently to workspace " .. workspace,
			hl.dsp.window.move({ workspace = workspace, follow = false })
		)
	end

	submap_stay_exec("T", "[Window Mode|Layout] cycle global layout", "hyprshell window/layout-toggle.sh")
	submap_stay_action(
		"S",
		"[Window Mode|Dwindle] toggle window split",
		layout_action("dwindle", hl.dsp.layout("togglesplit"))
	)
	submap_repeat_action(
		"H",
		"[Window Mode|Scrolling] previous column",
		layout_action("scrolling", hl.dsp.layout("move -col"))
	)
	submap_repeat_action(
		"L",
		"[Window Mode|Scrolling] next column",
		layout_action("scrolling", hl.dsp.layout("move +col"))
	)
	submap_repeat_action(
		"SHIFT + H",
		"[Window Mode|Scrolling] swap column left",
		layout_action("scrolling", hl.dsp.layout("swapcol l"))
	)
	submap_repeat_action(
		"SHIFT + L",
		"[Window Mode|Scrolling] swap column right",
		layout_action("scrolling", hl.dsp.layout("swapcol r"))
	)
	submap_repeat_action(
		"C",
		"[Window Mode|Scrolling] focus previous column",
		layout_action("scrolling", hl.dsp.layout("focus -col"))
	)
	submap_repeat_action(
		"SHIFT + C",
		"[Window Mode|Scrolling] focus next column",
		layout_action("scrolling", hl.dsp.layout("focus +col"))
	)
	submap_repeat_action(
		"E",
		"[Window Mode|Scrolling] shrink column",
		layout_action("scrolling", hl.dsp.layout("colresize -conf"))
	)
	submap_repeat_action(
		"SHIFT + E",
		"[Window Mode|Scrolling] grow column",
		layout_action("scrolling", hl.dsp.layout("colresize +conf"))
	)
	submap_stay_action(
		"X",
		"[Window Mode|Scrolling] expand column",
		layout_action("scrolling", hl.dsp.layout("colresize expand"))
	)
	submap_stay_action(
		"V",
		"[Window Mode|Scrolling] promote window",
		layout_action("scrolling", hl.dsp.layout("promote"))
	)
	submap_stay_action(
		"B",
		"[Window Mode|Scrolling] consume into column",
		layout_action("scrolling", hl.dsp.layout("consume"))
	)
	submap_stay_action(
		"SHIFT + B",
		"[Window Mode|Scrolling] expel from column",
		layout_action("scrolling", hl.dsp.layout("expel"))
	)
	submap_stay_action(
		"I",
		"[Window Mode|Scrolling] fit column into view",
		layout_action("scrolling", hl.dsp.layout("fit_into_view"))
	)

	submap_stay_action(
		"SHIFT + S",
		"[Window Mode|Dwindle] swap split",
		layout_action("dwindle", hl.dsp.layout("swapsplit"))
	)
	submap_stay_action(
		"R",
		"[Window Mode|Dwindle] rotate split",
		layout_action("dwindle", hl.dsp.layout("rotatesplit"))
	)
	submap_stay_action(
		"SHIFT + R",
		"[Window Mode|Dwindle] move to root",
		layout_action("dwindle", hl.dsp.layout("movetoroot"))
	)
	submap_repeat_action(
		"D",
		"[Window Mode|Dwindle] shrink split",
		layout_action("dwindle", hl.dsp.layout("splitratio -0.05"))
	)
	submap_repeat_action(
		"SHIFT + D",
		"[Window Mode|Dwindle] grow split",
		layout_action("dwindle", hl.dsp.layout("splitratio +0.05"))
	)

	submap_stay_action(
		"W",
		"[Window Mode|Master] focus master",
		layout_action("master", hl.dsp.layout("focusmaster"))
	)
	submap_stay_action(
		"SHIFT + W",
		"[Window Mode|Master] swap with master",
		layout_action("master", hl.dsp.layout("swapwithmaster"))
	)
	submap_repeat_action(
		"N",
		"[Window Mode|Master] focus next",
		layout_action("master", hl.dsp.layout("cyclenext"))
	)
	submap_repeat_action(
		"SHIFT + N",
		"[Window Mode|Master] focus previous",
		layout_action("master", hl.dsp.layout("cycleprev"))
	)
	submap_repeat_action(
		"J",
		"[Window Mode|Master] swap next",
		layout_action("master", hl.dsp.layout("swapnext"))
	)
	submap_repeat_action(
		"SHIFT + J",
		"[Window Mode|Master] swap previous",
		layout_action("master", hl.dsp.layout("swapprev"))
	)
	submap_stay_action(
		"A",
		"[Window Mode|Master] add master",
		layout_action("master", hl.dsp.layout("addmaster"))
	)
	submap_stay_action(
		"SHIFT + A",
		"[Window Mode|Master] remove master",
		layout_action("master", hl.dsp.layout("removemaster"))
	)
	submap_stay_action(
		"O",
		"[Window Mode|Master] cycle orientation",
		layout_action("master", hl.dsp.layout("orientationcycle"))
	)
	submap_stay_action(
		"SHIFT + O",
		"[Window Mode|Master] center orientation",
		layout_action("master", hl.dsp.layout("orientationcenter"))
	)
	submap_repeat_action(
		"K",
		"[Window Mode|Master] roll next",
		layout_action("master", hl.dsp.layout("rollnext"))
	)
	submap_repeat_action(
		"SHIFT + K",
		"[Window Mode|Master] roll previous",
		layout_action("master", hl.dsp.layout("rollprev"))
	)
	submap_repeat_action(
		"Z",
		"[Window Mode|Master] shrink master",
		layout_action("master", hl.dsp.layout("mfact -0.05"))
	)
	submap_repeat_action(
		"SHIFT + Z",
		"[Window Mode|Master] grow master",
		layout_action("master", hl.dsp.layout("mfact +0.05"))
	)

	submap_repeat_action(
		"Y",
		"[Window Mode|Monocle] focus next",
		layout_action("monocle", hl.dsp.layout("cyclenext"))
	)
	submap_repeat_action(
		"SHIFT + Y",
		"[Window Mode|Monocle] focus previous",
		layout_action("monocle", hl.dsp.layout("cycleprev"))
	)
end)

-- Theming: arrows cycle and stay, letters pick and leave.
submap_leader("theming", mod, "T", function()
	submap_cycle("RIGHT", "[Theming] next theme", "hyprshell theme.switch.sh -n --quiet")
	submap_cycle("LEFT", "[Theming] previous theme", "hyprshell theme.switch.sh -p --quiet")
	submap_cycle("DOWN", "[Theming] next wallpaper", "hyprshell wallpaper next --global")
	submap_cycle("UP", "[Theming] previous wallpaper", "hyprshell wallpaper previous --global")
	submap_exec("T", "[Theming] select theme", "hyprshell rofi/run-after-close.sh -- hyprshell theme.select.sh")
	submap_exec("SHIFT + T", "[Theming] reapply theme", "hyprshell theme.switch.sh --quiet")
	submap_exec(
		"W",
		"[Theming] select wallpaper",
		"hyprshell rofi/run-after-close.sh -- hyprshell wallpaper select --global"
	)
	submap_exec("F", "[Theming] select font", "pkill -x rofi || hyprshell fonts/font-picker.sh")
	submap_exec(
		"B",
		"[Theming] select Waybar layout",
		"hyprshell rofi/run-after-close.sh -- hyprshell waybar.py --select-layout"
	)
	submap_cycle("C", "[Theming] cycle Waybar layout", "hyprshell waybar/waybar -n")
	submap_cycle("SHIFT + C", "[Theming] cycle Waybar layout backward", "hyprshell waybar/waybar -p")
	submap_exec(
		"SHIFT + B",
		"[Theming] refresh Waybar colors",
		"hypr-theme refresh && hyprshell waybar.py --restart-direct"
	)
	submap_exec("V", "[Theming] toggle Waybar", "hyprshell waybar.py --hide")
	submap_exec("M", "[Theming] color mode", "pkill -x rofi || hyprshell color-mode.sh -m")
	submap_exec("R", "[Theming] select rofi theme", "hyprshell rofi/run-after-close.sh -- hyprshell theme.select.sh -s")
	submap_exec("L", "[Theming] select launcher style", "hyprshell rofi-launch.sh -s")
end)

submap_leader("open", mod, "O", function()
	submap_exec("F", "[Open] File finder", "pkill -x rofi || hyprshell launch/file-finder.sh")
	submap_exec("L", "[Open] Game launcher", "hyprshell gaming/launcher.sh")
	submap_exec("D", "[Open] Dropdown terminal", "hyprshell window/dropdown-terminal")
	submap_exec(
		"S",
		"[Open] Signal",
		"hyprshell launch/summon.sh --empty-workspace-if-occupied class:signal -- signal-desktop"
	)
	submap_exec("V", "[Open] Bitwarden", "hyprshell launch/summon.sh --align center bitwarden -- bitwarden-desktop")
	submap_exec("G", "[Open] Gimp", "hyprshell launch/summon.sh --empty-workspace-if-occupied gimp -- gimp")
	submap_exec("E", "[Open] Elisa", "hyprshell launch/summon.sh --empty-workspace-if-occupied class:elisa -- elisa")
	submap_exec(
		"R",
		"[Open] rmpc",
		'hyprshell launch/summon.sh --float-if-workspace-occupied class:org.tui.Rmpc -- hyprshell launch/tui.sh --app-id org.tui.Rmpc --title Rmpc -- "$HOME/.config/rmpc/lib/launch"'
	)
	submap_exec("M", "[Open] Mullvad VPN", 'hyprshell launch/summon.sh "class:Mullvad VPN" -- mullvad-vpn')
	submap_exec(
		"Q",
		"[Open] qBittorrent",
		"hyprshell launch/summon.sh --empty-workspace-if-occupied class:qbittorrent -- qbittorrent"
	)
end)

submap_leader("capture", mod, "R", function()
	submap_exec("S", "[Capture] smart screenshot", "hyprshell screenshot.sh smart")
	submap_exec("A", "[Capture] all monitors", "hyprshell screenshot.sh p")
	submap_exec("O", "[Capture] extract text", "hyprshell screenshot.sh ocr")
	submap_exec("C", "[Capture] color picker", "pkill -x rofi || hyprshell rofi/color-picker.sh")
	submap_exec("R", "[Capture] toggle monitor recording", "hyprshell screenrecord --toggle --audio --output")
	submap_exec("W", "[Capture] toggle webcam recording", "hyprshell screenrecord --toggle --audio --webcam")
	submap_exec("X", "[Capture] stop recording", "hyprshell screenrecord --quit")
end)

submap_leader("insert", mod, "I", function()
	submap_exec("E", "[Insert] emoji picker", "pkill -x rofi || hyprshell emoji-picker.sh")
	submap_exec("G", "[Insert] glyph picker", "pkill -x rofi || hyprshell glyph-picker.sh")
	submap_exec("B", "[Insert] box drawing picker", "pkill -x rofi || hyprshell boxdraw-picker.sh")
end)

submap_leader("utilities", mod, "U", function()
	submap_exec("Q", "[System] close all windows", "hyprshell window/close-all.sh")
	submap_exec("N", "[System] toggle nightlight", "hyprshell system/hyprsunset.sh toggle")
	submap_exec("A", "[System] toggle keep awake", "hyprshell session/toggle-keep-awake.sh")
	submap_exec("F", "[System] focus mode", "hyprshell util/workflow-toggle.sh focus")
	submap_exec("G", "[System] gaming mode", "hyprshell util/workflow-toggle.sh gaming")
	submap_exec("W", "[System] select workflow", "pkill -x rofi || hyprshell workflows --select")
	submap_exec("O", "[System] audio output switcher", "hyprshell controls/volume-control.sh -t")
	submap_cycle("S", "[System] cycle monitor scale", "hyprshell system/monitor-scale.sh")
	submap_cycle("SHIFT + S", "[System] cycle monitor scale backward", "hyprshell system/monitor-scale.sh --reverse")
	submap_exec("D", "[System] toggle laptop display", "hyprshell system/monitor-internal.sh toggle")
	submap_exec("M", "[System] toggle mirroring", "hyprshell system/monitor-mirror.sh toggle")
end)

-- Workspaces
for workspace = 1, 10 do
	local code = workspace_code(workspace)
	bind(mod, code, "[Workspaces] go to workspace " .. workspace, hl.dsp.focus({ workspace = workspace }))
	bind(
		mod .. " SHIFT",
		code,
		"[Workspaces] move window to workspace " .. workspace,
		hl.dsp.window.move({ workspace = workspace })
	)
	bind(
		mod .. " ALT",
		code,
		"[Workspaces] move window silently to workspace " .. workspace,
		hl.dsp.window.move({ workspace = workspace, follow = false })
	)
end

bind(mod .. " CTRL", "RIGHT", "[Workspaces] next relative workspace", hl.dsp.focus({ workspace = "r+1" }))
bind(mod .. " CTRL", "LEFT", "[Workspaces] previous relative workspace", hl.dsp.focus({ workspace = "r-1" }))
bind(mod .. " CTRL", "UP", "[Workspaces] previous workspace", hl.dsp.focus({ workspace = "previous" }))
bind(mod .. " CTRL", "DOWN", "[Workspaces] nearest empty workspace", hl.dsp.focus({ workspace = "empty" }))
bind(mod, "TAB", "[Workspaces] next existing workspace", hl.dsp.focus({ workspace = "e+1" }))
bind(mod .. " SHIFT", "TAB", "[Workspaces] previous existing workspace", hl.dsp.focus({ workspace = "e-1" }))

bind(mod .. " SHIFT ALT", "LEFT", "[Workspaces] move workspace left", hl.dsp.workspace.move({ monitor = "l" }))
bind(mod .. " SHIFT ALT", "RIGHT", "[Workspaces] move workspace right", hl.dsp.workspace.move({ monitor = "r" }))
bind(mod .. " SHIFT ALT", "UP", "[Workspaces] move workspace up", hl.dsp.workspace.move({ monitor = "u" }))
bind(mod .. " SHIFT ALT", "DOWN", "[Workspaces] move workspace down", hl.dsp.workspace.move({ monitor = "d" }))

bind(
	mod .. " CTRL SHIFT",
	"RIGHT",
	"[Workspaces] move window to next relative workspace",
	hl.dsp.window.move({ workspace = "r+1" })
)
bind(
	mod .. " CTRL SHIFT",
	"LEFT",
	"[Workspaces] move window to previous relative workspace",
	hl.dsp.window.move({ workspace = "r-1" })
)
bind(mod, "mouse_down", "[Workspaces] next existing workspace", hl.dsp.focus({ workspace = "e+1" }))
bind(mod, "mouse_up", "[Workspaces] previous existing workspace", hl.dsp.focus({ workspace = "e-1" }))
bind(mod .. " SHIFT", "S", "[Workspaces] move to scratchpad", hl.dsp.window.move({ workspace = "special" }))
bind(
	mod .. " ALT",
	"S",
	"[Workspaces] move to scratchpad silently",
	hl.dsp.window.move({ workspace = "special", follow = false })
)
bind(mod, "S", "[Workspaces] toggle scratchpad", hl.dsp.workspace.toggle_special(""))
