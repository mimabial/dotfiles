local vars = require("vars")
local refill_scrolling_pair = require("core").refill_scrolling_pair
local usable_edges = require("core").usable_edges

local mod = vars.get("mainMod", "SUPER")
local terminal = vars.get("TERMINAL", "alacritty")
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

-- Long-lived apps need their own unit: in the compositor's, oomd kills Hyprland
-- for their memory and their stop jobs stall the next login.
local function app(command)
	return "hyprshell app -- " .. command
end

local function menu(id)
	return "pkill -x rofi || hyprshell rofi/menutree --menu-id " .. id
end

-- Submaps give each domain its own key namespace, so no bind needs punctuation.
-- That matters here: resolve_binds_by_sym resolves against the active layout's
-- level-1 keysym, and AZERTY puts . / [ ] above level 1, where it cannot reach.
local SUBMAP_MARKER = "[Submap] "
-- Binds a submap re-exposes from the global set: they work, but the submap hint
-- already has enough rows. submap_hint.py filters on this same string.
local HIDDEN_MARKER = "[Hidden] "

-- Digits share the punctuation problem above -- AZERTY reaches them at level 2 --
-- so the number row binds by keycode, which no layout remaps.
local KEYCODE_DIGIT_1 = 10
local function workspace_code(workspace)
	return "code:" .. tostring(KEYCODE_DIGIT_1 + workspace - 1)
end

-- The leader is tagged with SUBMAP_MARKER because the Lua plugin reports every
-- bind as dispatcher "__lua"; keybinds_hint pairs inner binds back to the key
-- that enters them via this description, not via hyprctl's dispatcher field.
local function submap_leader(name, modifiers, key, body, exit_on_unbound)
	bind(modifiers, key, SUBMAP_MARKER .. name, hl.dsp.submap(name))
	hl.define_submap(name, function()
		body()
		hl.bind("ESCAPE", hl.dsp.submap("reset"), { description = "[" .. name .. "] exit" })
		-- By default, unclaimed keys end the mode so a stray press cannot leave it
		-- live while bare-letter binds fire window actions. Modmask 0: chords pass through.
		if exit_on_unbound ~= false then
			for _, key in ipairs({"SHIFT_L", "SHIFT_R", "CONTROL_L", "CONTROL_R", "ALT_L", "ALT_R", "SUPER_L", "SUPER_R"}) do
				hl.bind(key, hl.dsp.no_op(), { release = true, ignore_mods = true, description = HIDDEN_MARKER .. name .. " modifier " .. key })
			end
			hl.bind(
				"catchall",
				hl.dsp.submap("reset"),
				{ description = HIDDEN_MARKER .. name .. " exit on unbound key" }
			)
		end
	end)
end

local function run_action(action)
	if type(action) == "function" then
		action()
	else
		hl.dispatch(action)
	end
end

-- Submap actions are one-shot. bind_actions keeps the bare dispatcher so
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

local function submap_repeat_action(key, description, dispatcher)
	bind_actions[description] = dispatcher
	hl.bind(key, dispatcher, { description = description, repeating = true })
end

local function submap_cycle(key, description, command)
	submap_repeat_action(key, description, hl.dsp.exec_cmd(command))
end

local function active_tiled_layout()
	local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
	return workspace and workspace.tiled_layout
end

local function announce_layout()
	hl.dispatch(hl.dsp.event("layout"))
end

local function layout_action(layout, action)
	return function()
		if active_tiled_layout() ~= layout then
			return
		end
		run_action(action)
		announce_layout()
	end
end

local LAYOUT_RATIO_STEP = 0.05
local layouts_by_key = {}
local function layout_submap_action(layout, key, name, action)
	local layouts_on_key = layouts_by_key[key] or {}
	layouts_by_key[key] = layouts_on_key
	layouts_on_key[layout] = true
	local description = "[Window Mode|" .. layout:gsub("^%l", string.upper) .. "] " .. name
	local gated_action = layout_action(layout, action)
	bind_actions[description] = gated_action
	hl.bind(key, function()
		local active = active_tiled_layout()
		local other_layout_bind_acts = active ~= layout and layouts_on_key[active]
		if other_layout_bind_acts then
			return
		end
		hl.dispatch(hl.dsp.submap("reset"))
		gated_action()
	end, { description = description })
end

local function resize_column(direction)
	local step = { [1] = "colresize +conf", [-1] = "colresize -conf" }
	return function()
		local window = hl.get_active_window()
		local width = window and window.size.x
		hl.dispatch(hl.dsp.layout(step[direction]))
		if window and (window.size.x - width) * direction < 0 then
			hl.dispatch(hl.dsp.layout(step[-direction]))
			local left, right = usable_edges(window.workspace)
			local usable_width = right - left + 2 * hl.get_config("general.border_size")
			hl.dispatch(hl.dsp.layout(string.format("colresize %+f", (width - window.size.x) / usable_width)))
		end
		refill_scrolling_pair()
	end
end

local function cycle_monocle(step)
	return function()
		local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
		local stack = {}
		for _, window in ipairs(workspace:get_windows()) do
			if window.mapped and not window.hidden and not window.floating then
				stack[#stack + 1] = window
			end
		end
		table.sort(stack, function(a, b)
			return tonumber(a.stable_id) < tonumber(b.stable_id)
		end)
		for index, window in ipairs(stack) do
			if window.visible then
				local target = stack[(index - 1 + step) % #stack + 1]
				hl.dispatch(hl.dsp.focus({ window = "address:" .. target.address }))
				return
			end
		end
	end
end

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
	return width - reserved.left - reserved.right - 2 * border, height - reserved.top - reserved.bottom - 2 * border
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

exec(mod, "Q", "[Window Management] close panel or focused window", "hyprshell window/close-focused.sh")
bind("ALT", "F4", "[Window Management] close focused window", hl.dsp.window.close())
bind(mod .. " SHIFT", "Q", "[Window Management] force kill focused window", hl.dsp.window.kill())
local native_fullscreen = hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })
local function toggle_fullscreen()
	if vars.get("WORKFLOW") ~= "macos" then
		hl.dispatch(native_fullscreen)
		return
	end
	local window = hl.get_active_window()
	if window then
		hl.dispatch(hl.dsp.exec_cmd("python3 " .. vars.get("scrPath") .. "/window/mac-spaces.py toggle " .. window.address))
	end
end
bind(mod, "F", "[Window Management] toggle fullscreen", toggle_fullscreen)
bind(
	mod,
	"M",
	"[Window Management] toggle maximize",
	hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })
)
exec(mod .. " SHIFT", "M", "[Window Management] minimize window", "quickshell ipc call dock minimizeActive")
exec(mod, "P", "[Window Management] toggle pin", "hyprshell window/windowpin.sh")
bind(mod, "G", "[Window Management] toggle group", hl.dsp.group.toggle())
bind(mod .. " SHIFT", "F", "[Window Management] toggle floating", toggle_floating)

local function niri_or(niri_action, action)
	return function()
		hl.dispatch(vars.get("WORKFLOW") == "niri" and niri_action or action)
	end
end

bind(mod, "LEFT", "[Window Management|Focus] focus left", hl.dsp.focus({ direction = "left" }))
bind(mod, "RIGHT", "[Window Management|Focus] focus right", hl.dsp.focus({ direction = "right" }))
bind(mod, "UP", "[Window Management|Focus] focus up or previous workspace in niri", niri_or(hl.dsp.focus({ workspace = "r-1" }), hl.dsp.focus({ direction = "up" })))
bind(mod, "DOWN", "[Window Management|Focus] focus down or next workspace in niri", niri_or(hl.dsp.focus({ workspace = "r+1" }), hl.dsp.focus({ direction = "down" })))

dofile(os.getenv("HOME") .. "/.config/hypr/switcher.lua")

local WINDOW_STEP_PX = 30
local WINDOW_STEPS = {
	left = { x = -WINDOW_STEP_PX, y = 0 },
	right = { x = WINDOW_STEP_PX, y = 0 },
	up = { x = 0, y = -WINDOW_STEP_PX },
	down = { x = 0, y = WINDOW_STEP_PX },
}

local function move_window(direction)
	local step = WINDOW_STEPS[direction]
	return function()
		local window = hl.get_active_window()
		if window and window.floating then
			hl.dispatch(hl.dsp.window.move({ x = step.x, y = step.y, relative = true }))
		else
			hl.dispatch(hl.dsp.window.move({ direction = direction }))
		end
		announce_layout()
	end
end

local function resize_window(direction)
	local step = WINDOW_STEPS[direction]
	return function()
		local window = hl.get_active_window()
		if not window then
			return
		end

		if window.floating then
			local max_width, max_height = usable_area(window.monitor)
			local width = math.min(window.size.x + step.x, max_width)
			local height = math.min(window.size.y + step.y, max_height)
			hl.dispatch(hl.dsp.window.resize({ x = width, y = height, relative = false }))
		else
			hl.dispatch(hl.dsp.window.resize({ x = step.x, y = step.y, relative = true }))
			if step.x ~= 0 then
				refill_scrolling_pair()
			end
		end
		announce_layout()
	end
end

bind(mod .. " SHIFT", "LEFT", "[Window Management|Move] move left", move_window("left"), { repeating = true })
bind(mod .. " SHIFT", "RIGHT", "[Window Management|Move] move right", move_window("right"), { repeating = true })
bind(mod .. " SHIFT", "UP", "[Window Management|Move] move up", move_window("up"), { repeating = true })
bind(mod .. " SHIFT", "DOWN", "[Window Management|Move] move down", move_window("down"), { repeating = true })

-- ALT here is not the convention's "without following": SUPER+CTRL+arrows is
-- relative workspace navigation, so this is the only free arrow modifier.
bind(mod .. " ALT", "LEFT", "[Window Management|Resize] shrink width", resize_window("left"), { repeating = true })
bind(mod .. " ALT", "RIGHT", "[Window Management|Resize] grow width", resize_window("right"), { repeating = true })
bind(mod .. " ALT", "UP", "[Window Management|Resize] shrink height", resize_window("up"), { repeating = true })
bind(mod .. " ALT", "DOWN", "[Window Management|Resize] grow height", resize_window("down"), { repeating = true })

bind(mod, "mouse:272", "[Window Management|Mouse] move window", hl.dsp.window.drag(), { mouse = true })
bind(mod, "mouse:273", "[Window Management|Mouse] resize window", hl.dsp.window.resize(), { mouse = true })
hl.bind(chord(mod, "mouse:273"), refill_scrolling_pair, { drag = true })
bind(mod, "Z", "[Window Management|Mouse] move window", hl.dsp.window.drag(), { mouse = true })
bind(mod, "X", "[Window Management|Mouse] resize window", hl.dsp.window.resize(), { mouse = true })
hl.bind(chord(mod, "X"), function()
	refill_scrolling_pair()
	announce_layout()
end, { drag = true })
hl.bind(chord(mod, "Z"), announce_layout, { drag = true })
for _, button in ipairs({ "mouse:272", "mouse:273" }) do
	hl.bind(button, announce_layout, { drag = true, non_consuming = true, ignore_mods = true })
end

exec("CTRL ALT", "DELETE", "[Window Management] logout menu", "hyprshell logout-launch.sh")
exec(mod, "ESCAPE", "[Window Management] logout menu", "hyprshell logout-launch.sh")

exec(
	mod,
	"RETURN",
	"[Launcher|Apps] terminal in current directory",
	app(terminal .. [[ --working-directory "$(hyprshell terminal-cwd.sh)"]])
)
exec(
	mod .. " SHIFT",
	"RETURN",
	"[Launcher|Apps] tmux session",
	app(terminal .. [[ --working-directory "$(hyprshell terminal-cwd.sh)" tmux new-session -A -s M]])
)
-- Focus the existing window if there is one -- hl.dsp.focus pulls in a hidden
-- special workspace as well as a regular one -- otherwise spawn it on its workspace.
local function summon_app(class, workspace, command, focus_when_opened)
	local scratchpad = workspace:match("^special:(.+)$")
	local pending_focus = false
	if focus_when_opened then
		hl.on("window.open", function(window)
			if not pending_focus or not window or (window.class ~= class and window.initial_class ~= class) then
				return
			end
			pending_focus = false
			local shown = hl.get_active_special_workspace()
			if shown and shown.name == workspace then
				hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
			end
		end)
	end
	return function()
		pending_focus = false
		local shown = hl.get_active_special_workspace()
		for _, window in ipairs(hl.get_windows() or {}) do
			if window.class == class or window.initial_class == class then
				local on_shown_scratchpad = scratchpad
					and shown
					and window.workspace
					and window.workspace.name == shown.name
				if on_shown_scratchpad then
					hl.dispatch(hl.dsp.workspace.toggle_special(shown.name:match("^special:(.*)$") or ""))
				else
					hl.dispatch(hl.dsp.focus({ window = "address:" .. window.address }))
				end
				return
			end
		end
		if scratchpad and not (shown and shown.name == workspace) then
			hl.dispatch(hl.dsp.workspace.toggle_special(scratchpad))
		end
		pending_focus = focus_when_opened
		hl.dispatch(hl.dsp.exec_cmd("[workspace " .. workspace .. "] " .. app(command)))
	end
end

local numbered_special_workspaces = {
	[6] = {
		description = "[Launcher|Apps] Signal",
		action = summon_app("signal", "special:signal", "signal-desktop"),
		workspace = "special:signal",
		move_description = "[Workspaces] move window to Signal special workspace",
		alt_description = "[Workspaces] move window silently to Signal special workspace",
		alt_action = hl.dsp.window.move({ workspace = "special:signal", follow = false }),
	},
	[8] = {
		description = "[Launcher|Apps] web browser",
		action = summon_app("firefox", "special:browser", browser),
		workspace = "special:browser",
		move_description = "[Workspaces] move window to browser special workspace",
		alt_description = "[Launcher|Apps] private browser",
		alt_action = hl.dsp.exec_cmd("hyprshell browser.sh --private"),
	},
	[9] = {
		description = "[Launcher|Apps] file explorer",
		action = summon_app("org.kde.dolphin", "special:explorer", explorer, true),
		workspace = "special:explorer",
		move_description = "[Workspaces] move window to explorer special workspace",
		alt_description = "[Launcher|Apps] file explorer in current directory",
		alt_action = hl.dsp.exec_cmd(app(explorer .. [[ "$(hyprshell terminal-cwd.sh)"]])),
	},
	[10] = {
		description = "[Workspaces] toggle scratchpad",
		action = hl.dsp.workspace.toggle_special(""),
		workspace = "special",
		move_description = "[Workspaces] move to scratchpad",
		alt_description = "[Workspaces] move to scratchpad silently",
		alt_action = hl.dsp.window.move({ workspace = "special", follow = false }),
	},
}

local function numbered_workspace_action(workspace)
	local special = numbered_special_workspaces[workspace]
	if special then
		return special.description, special.action
	end
	return "[Workspaces] go to workspace " .. workspace, hl.dsp.focus({ workspace = workspace })
end

exec(mod, "C", "[Launcher|Apps] text editor", app(terminal .. " -e " .. editor))

exec(mod, "D", "[Launcher|Menus] application finder", "hyprshell rofi-launch.sh d")
exec(mod .. " SHIFT", "D", "[Launcher|Menus] window switcher", "hyprshell rofi-launch.sh w")
exec(mod .. " CTRL", "D", "[Launcher|Menus] focus dock", "quickshell ipc call dock focus")
bind(mod, "A", "[Launcher|Menus] Exposé window overview", hl.dsp.event("expose.window-overview:toggle"))
bind(mod .. " SHIFT", "A", "[Launcher|Menus] Exposé app windows", hl.dsp.event("expose.window-overview:app"))
exec(mod, "SPACE", "[Launcher|Menus] menu tree", "pkill -x rofi || hyprshell menutree")
exec(mod .. " SHIFT", "SPACE", "[Launcher|Menus] start menu", "quickshell ipc call bar popup start")
exec("CTRL", "F2", "[Launcher|Menus] focus menu bar", "quickshell ipc call bar menuBar")
exec(mod, "V", "[Launcher|Menus] clipboard", "quickshell ipc call bar popup cliphist")
exec(mod, "S", "[Launcher|Menus] spotlight", "quickshell ipc call bar popup spotlight")

exec(mod, "F10", "[Hardware|Audio] mute output", vars.get("scrPath") .. "/controls/volume-control.sh -o m", { locked = true })
exec(mod .. " CTRL", "F10", "[Hardware|Audio] mute focused window", "hyprshell window-mute.py", { locked = true })
exec("", "XF86AudioMute", "[Hardware|Audio] mute output", vars.get("scrPath") .. "/controls/volume-control.sh -o m", { locked = true })
exec(
	mod,
	"F11",
	"[Hardware|Audio] volume down",
	vars.get("scrPath") .. "/controls/volume-control.sh -o d",
	{ locked = true, repeating = true }
)
exec(mod, "F12", "[Hardware|Audio] volume up", vars.get("scrPath") .. "/controls/volume-control.sh -o i", { locked = true, repeating = true })
exec("", "XF86AudioMicMute", "[Hardware|Audio] mute microphone", vars.get("scrPath") .. "/controls/volume-control.sh -i m", { locked = true })
exec(
	"",
	"XF86AudioLowerVolume",
	"[Hardware|Audio] volume down",
	vars.get("scrPath") .. "/controls/volume-control.sh -o d",
	{ locked = true, repeating = true }
)
exec(
	"",
	"XF86AudioRaiseVolume",
	"[Hardware|Audio] volume up",
	vars.get("scrPath") .. "/controls/volume-control.sh -o i",
	{ locked = true, repeating = true }
)

exec("", "XF86AudioPlay", "[Hardware|Media] play or pause", "quickshell ipc call crmne.mpris playPause", { locked = true })
exec("", "XF86AudioPause", "[Hardware|Media] play or pause", "quickshell ipc call crmne.mpris playPause", { locked = true })
exec("", "XF86AudioNext", "[Hardware|Media] next", "quickshell ipc call crmne.mpris next", { locked = true })
exec("", "XF86AudioPrev", "[Hardware|Media] previous", "quickshell ipc call crmne.mpris previous", { locked = true })
exec(
	"",
	"XF86MonBrightnessUp",
	"[Hardware|Brightness] increase",
	vars.get("scrPath") .. "/controls/brightness-control.sh i",
	{ locked = true, repeating = true }
)
exec(
	"",
	"XF86MonBrightnessDown",
	"[Hardware|Brightness] decrease",
	vars.get("scrPath") .. "/controls/brightness-control.sh d",
	{ locked = true, repeating = true }
)
exec("", "XF86PowerOff", "[Hardware|Power] logout menu", "hyprshell logout-launch.sh")
exec("", "XF86TouchpadToggle", "[Hardware|Touchpad] toggle touchpad", "hyprshell controls/touchpad-toggle.sh", { locked = true })

exec("", "Print", "[Utilities|Capture] all monitors", "hyprshell screenshot.sh p", { locked = true })
exec("SHIFT", "Print", "[Utilities|Capture] smart screenshot", "hyprshell screenshot.sh smart", { locked = true })
-- The compositor sees the switch itself, so locking here needs no init system and
-- survives caffeine stopping hypridle.
exec(
	"",
	"switch:on:Lid Switch",
	"[Utilities|Session] lid close: configured action",
	"hyprshell session/lid-close.sh",
	{ locked = true }
)
-- Stays top-level and locked: the layout must be switchable on the lock screen.
exec(mod, "K", "[Utilities] switch keyboard layout", "hyprshell keyboard-switch.sh", { locked = true })
exec(mod, "L", "[Utilities|Session] lock screen", "hyprshell lock-screen.sh")

submap_leader("window", mod, "W", function()
	submap_action("LEFT", "[Window Mode|Focus] focus left", hl.dsp.focus({ direction = "left" }))
	submap_action("RIGHT", "[Window Mode|Focus] focus right", hl.dsp.focus({ direction = "right" }))
	submap_action("UP", "[Window Mode|Focus] focus up", hl.dsp.focus({ direction = "up" }))
	submap_action("DOWN", "[Window Mode|Focus] focus down", hl.dsp.focus({ direction = "down" }))

	submap_action("SHIFT + LEFT", "[Window Mode|Move] move left", move_window("left"))
	submap_action("SHIFT + RIGHT", "[Window Mode|Move] move right", move_window("right"))
	submap_action("SHIFT + UP", "[Window Mode|Move] move up", move_window("up"))
	submap_action("SHIFT + DOWN", "[Window Mode|Move] move down", move_window("down"))

	submap_action("ALT + LEFT", "[Window Mode|Resize] shrink width", resize_window("left"))
	submap_action("ALT + RIGHT", "[Window Mode|Resize] grow width", resize_window("right"))
	submap_action("ALT + UP", "[Window Mode|Resize] shrink height", resize_window("up"))
	submap_action("ALT + DOWN", "[Window Mode|Resize] grow height", resize_window("down"))

	submap_action("F", "[Window Mode|State] toggle fullscreen", toggle_fullscreen)
	submap_action("SHIFT + F", "[Window Mode|State] toggle floating", toggle_floating)
	submap_action(
		"M",
		"[Window Mode|State] toggle maximize",
		hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })
	)
	submap_action("G", "[Window Mode|State] toggle group", hl.dsp.group.toggle())
	submap_exec("P", "[Window Mode|State] toggle pin", "hyprshell window/windowpin.sh")
	submap_exec("C", "[Window Mode|Placement] snap placement menu", vars.get("scrPath") .. "/window/snap.sh")
	submap_exec("D", "[Window Mode|State] show desktop", "quickshell ipc call dock showDesktop")

	for workspace = 1, 10 do
		local code = workspace_code(workspace)
		submap_action(
			code,
			"[Window Mode|Workspace] go to workspace " .. workspace,
			hl.dsp.focus({ workspace = workspace })
		)
		submap_action(
			"SHIFT + " .. code,
			"[Window Mode|Workspace] move window to workspace " .. workspace,
			hl.dsp.window.move({ workspace = workspace })
		)
		submap_action(
			"ALT + " .. code,
			"[Window Mode|Workspace] move window silently to workspace " .. workspace,
			hl.dsp.window.move({ workspace = workspace, follow = false })
		)
	end

	submap_cycle("T", "[Window Mode|Layout] cycle global layout", "hyprshell window/layout-toggle.sh")
	submap_cycle(
		"SHIFT + T",
		"[Window Mode|Layout] cycle global layout backward",
		"hyprshell window/layout-toggle.sh previous"
	)
	submap_exec("L", "[Window Mode|Layout] select global layout", menu("trigger_toggle_workspace_layout"))
	layout_submap_action("dwindle", "S", "toggle window split", hl.dsp.layout("togglesplit"))
	layout_submap_action("dwindle", "SHIFT + S", "swap split", hl.dsp.layout("swapsplit"))
	layout_submap_action("dwindle", "R", "rotate split", hl.dsp.layout("rotatesplit"))
	layout_submap_action("dwindle", "SHIFT + R", "move to root", hl.dsp.layout("movetoroot"))
	layout_submap_action("dwindle", "Z", "grow parent split", hl.dsp.layout("splitratio +" .. LAYOUT_RATIO_STEP))
	layout_submap_action("dwindle", "SHIFT + Z", "shrink parent split", hl.dsp.layout("splitratio -" .. LAYOUT_RATIO_STEP))

	layout_submap_action("scrolling", "N", "focus next column", hl.dsp.layout("focus r"))
	layout_submap_action("scrolling", "SHIFT + N", "focus previous column", hl.dsp.layout("focus l"))
	layout_submap_action("scrolling", "J", "swap column right", hl.dsp.layout("swapcol r"))
	layout_submap_action("scrolling", "SHIFT + J", "swap column left", hl.dsp.layout("swapcol l"))
	layout_submap_action("scrolling", "C", "scroll view to next column", hl.dsp.layout("move +col"))
	layout_submap_action("scrolling", "SHIFT + C", "scroll view to previous column", hl.dsp.layout("move -col"))
	layout_submap_action("scrolling", "Z", "grow column", resize_column(1))
	layout_submap_action("scrolling", "SHIFT + Z", "shrink column", resize_column(-1))
	layout_submap_action("scrolling", "X", "expand column", hl.dsp.layout("fit expand"))
	layout_submap_action("scrolling", "V", "promote window", hl.dsp.layout("promote"))
	layout_submap_action("scrolling", "B", "consume into column", hl.dsp.layout("consume"))
	layout_submap_action("scrolling", "SHIFT + B", "expel from column", hl.dsp.layout("expel"))
	layout_submap_action("scrolling", "I", "fit column into view", hl.dsp.layout("fit_into_view"))

	layout_submap_action("master", "W", "focus master", hl.dsp.layout("focusmaster"))
	layout_submap_action("master", "SHIFT + W", "swap with master", hl.dsp.layout("swapwithmaster"))
	layout_submap_action("master", "N", "focus next", hl.dsp.layout("cyclenext"))
	layout_submap_action("master", "SHIFT + N", "focus previous", hl.dsp.layout("cycleprev"))
	layout_submap_action("master", "J", "swap next", hl.dsp.layout("swapnext"))
	layout_submap_action("master", "SHIFT + J", "swap previous", hl.dsp.layout("swapprev"))
	layout_submap_action("master", "A", "add master", hl.dsp.layout("addmaster"))
	layout_submap_action("master", "SHIFT + A", "remove master", hl.dsp.layout("removemaster"))
	layout_submap_action("master", "O", "cycle orientation", hl.dsp.layout("orientationcycle"))
	layout_submap_action("master", "SHIFT + O", "center orientation", hl.dsp.layout("orientationcenter"))
	layout_submap_action("master", "K", "roll next", hl.dsp.layout("rollnext"))
	layout_submap_action("master", "SHIFT + K", "roll previous", hl.dsp.layout("rollprev"))
	layout_submap_action("master", "Z", "grow master", hl.dsp.layout("mfact +" .. LAYOUT_RATIO_STEP))
	layout_submap_action("master", "SHIFT + Z", "shrink master", hl.dsp.layout("mfact -" .. LAYOUT_RATIO_STEP))

	layout_submap_action("monocle", "N", "focus next", cycle_monocle(1))
	layout_submap_action("monocle", "SHIFT + N", "focus previous", cycle_monocle(-1))
end)

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
	submap_exec("F", "[Theming] select font", "pkill -x rofi || hyprshell rofi/menutree --action style_font")
	submap_exec(
		"SHIFT + F",
		"[Theming] install Nerd Font",
		"pkill -x rofi || hyprshell rofi/menutree --action install_font"
	)
	submap_exec("B", "[Theming] select bar layout", menu("style_bar_layout"))
	submap_exec("SHIFT + B", "[Theming] reload bar", "quickshell ipc call bar reload")
	submap_exec("C", "[Theming] cycle bar layout", "hyprshell quickshell/layout next")
	submap_exec("SHIFT + C", "[Theming] cycle bar layout backward", "hyprshell quickshell/layout previous")
	submap_exec("H", "[Theming] toggle bar", "hyprshell quickshell/visibility toggle")
	submap_exec("SHIFT + H", "[Theming] toggle floating bar", "quickshell ipc call bar floating")
	submap_exec("L", "[Theming] look and feel", "hyprshell window/settings.sh")
	submap_exec("A", "[Theming] select animation", menu("style_animations"))
	submap_exec("S", "[Theming] select shader", menu("style_shaders"))
	submap_exec("M", "[Theming] color mode", menu("style_color_mode"))
	submap_exec("R", "[Theming] select rofi theme", "hyprshell rofi/run-after-close.sh -- hyprshell theme.select.sh -s")
	submap_exec("SHIFT + R", "[Theming] select launcher style", "hyprshell rofi-launch.sh -s")
	submap_exec("K", "[Theming] select lock layout", "quickshell ipc call lockview open")
	for workspace = 1, 10 do
		local description, action = numbered_workspace_action(workspace)
		submap_action(
			chord(mod, workspace_code(workspace)),
			HIDDEN_MARKER .. description,
			action
		)
	end
end, false)

submap_leader("open", mod, "O", function()
	submap_exec("F", "[Open] File finder", "pkill -x rofi || hyprshell launch/file-finder.sh")
	submap_exec("B", "[Open] Bookmarks", "quickshell ipc call bar bookmarks")
	submap_exec("N", "[Open] Notifications", "quickshell ipc call bar popup notifications")
	submap_exec("T", "[Open] Tray", "quickshell ipc call bar tray")
	submap_exec("L", "[Open] Game launcher", "hyprshell gaming/launcher.sh")
	submap_exec(
		"SHIFT + L",
		"[Open] Lutris",
		"hyprshell launch/summon.sh --empty-workspace-if-occupied class:net.lutris.Lutris -- lutris"
	)
	submap_exec("V", "[Open] Bitwarden vault", "quickshell ipc call bar popup bitwarden")
	submap_exec("SHIFT + V", "[Open] Bitwarden desktop", "hyprshell launch/summon.sh --align center bitwarden -- bitwarden-desktop")
	submap_exec(
		"W",
		"[Open] LibreOffice Writer",
		"hyprshell launch/summon.sh class:libreoffice-writer -- libreoffice --writer"
	)
	submap_exec("G", "[Open] Gimp", "hyprshell launch/summon.sh --empty-workspace-if-occupied gimp -- gimp")
	submap_exec("E", "[Open] Elisa", "hyprshell launch/summon.sh --empty-workspace-if-occupied class:elisa -- elisa")
	submap_exec("M", "[Open] Mullvad VPN", "hyprshell launch/summon.sh class:mullvad-vpn -- mullvad-vpn")
	submap_exec(
		"Q",
		"[Open] qBittorrent",
		"hyprshell launch/summon.sh --empty-workspace-if-occupied class:qbittorrent -- qbittorrent"
	)
end)

local function tui_app(key, name, app_id, command, category)
	submap_exec(
		key,
		"[" .. (category or "Terminal") .. "] " .. name,
		"hyprshell launch/focus.sh "
			.. app_id
			.. " -- hyprshell launch/tui.sh --app-id "
			.. app_id
			.. " --title '"
			.. name
			.. "' -- "
			.. command
	)
end

submap_leader("terminal", mod, "J", function()
	submap_exec("A", "[Terminal] Agent Hub", "hyprshell system/agent-hub")
	tui_app("H", "Htop", "org.tui.Htop", "htop")
	tui_app("N", "Nvtop", "org.tui.Nvtop", "nvtop")
	tui_app("B", "Bluetui", "org.tui.Bluetui", "bluetui")
	tui_app("W", "Impala", "org.tui.Impala", "impala")
	tui_app("V", "Wiremix", "org.tui.Wiremix", "wiremix")
	tui_app("U", "Dua", "org.tui.Dua", "dua i")
	submap_exec("C", "[Terminal] Calculator", "hyprshell util/calc-launch")
	tui_app("D", "Display layout", "org.tui.Displays", "hyprmoncfg")
	submap_exec("L", "[Terminal] Look and feel", "hyprshell window/settings.sh")
	submap_exec("T", "[Terminal] Dropdown terminal", "hyprshell window/dropdown-terminal")
	submap_exec(
		"R",
		"[Terminal] rmpc",
		'hyprshell launch/summon.sh --float-if-workspace-occupied class:org.tui.Rmpc -- hyprshell launch/tui.sh --app-id org.tui.Rmpc --title Rmpc -- "$HOME/.config/rmpc/lib/launch"'
	)
end)

submap_leader("capture", mod, "R", function()
	submap_exec("S", "[Capture] smart screenshot", "hyprshell screenshot.sh smart")
	submap_exec("A", "[Capture] all monitors", "hyprshell screenshot.sh p")
	submap_exec("O", "[Capture] extract text", "hyprshell screenshot.sh ocr")
	submap_exec("Q", "[Capture] decode qr code", "hyprshell capture/qr")
	submap_exec("C", "[Capture] color picker", "pkill -x rofi || hyprshell rofi/color-picker.sh")
	submap_exec("R", "[Capture] toggle monitor recording", "hyprshell screenrecord --toggle --audio --output")
	submap_exec("W", "[Capture] toggle webcam recording", "hyprshell screenrecord --toggle --audio --with-webcam")
	submap_exec("X", "[Capture] stop recording", "hyprshell screenrecord --quit")
end)

submap_leader("insert", mod, "I", function()
	submap_exec("E", "[Insert] emoji picker", "pkill -x rofi || hyprshell emoji-picker.sh")
	submap_exec("G", "[Insert] glyph picker", "pkill -x rofi || hyprshell glyph-picker.sh")
	submap_exec("B", "[Insert] box drawing picker", "pkill -x rofi || hyprshell boxdraw-picker.sh")
end)

submap_leader("hints", mod, "H", function()
	submap_exec("H", "[Hints] Hyprland keybindings", "pkill -x rofi || hyprshell keybinds/keybinds_hint.sh")
	submap_exec("K", "[Hints] kitty keybindings", "pkill -x rofi || hyprshell keybinds/app-hints.sh kitty")
	submap_exec("T", "[Hints] tmux keybindings", "pkill -x rofi || hyprshell keybinds/app-hints.sh tmux")
	submap_exec("W", "[Hints] focused window details", "quickshell ipc call bar popup windowinfo")
end)

local unzoomed, max_zoom, magnifier_step = 1, 10, 1.25
local function magnify_by(factor)
	return function()
		local zoom = hl.get_config("cursor.zoom_factor") * factor
		hl.config({ cursor = { zoom_factor = math.min(math.max(zoom, unzoomed), max_zoom) } })
	end
end

submap_leader("utilities", mod, "U", function()

	submap_exec("B", "[Notifications] actions", "dunstctl context")
	submap_exec("SHIFT + B", "[Notifications] dismiss all", "dunstctl close-all")
	submap_exec("C", "[Notifications] copy latest verification code", "quickshell ipc call notifications copyLatest")
	submap_exec("Q", "[System] close all windows", "hyprshell window/close-all.sh")
	submap_exec("N", "[System] toggle nightlight", "hyprshell system/hyprsunset.sh -t")
	submap_exec("A", "[System] toggle keep awake", "hyprshell session/toggle-keep-awake.sh")
	submap_exec("SHIFT + A", "[System] toggle keep running with lid closed", "hyprshell session/toggle-system-keep-awake.sh")
	submap_exec("W", "[System] select workflow", menu("style_workflow"))
	submap_exec("O", "[System] audio output switcher", "hyprshell controls/volume-control.sh -t")
	submap_exec("S", "[System] cycle monitor scale", "hyprshell system/monitor-scale.sh")
	submap_exec("SHIFT + S", "[System] cycle monitor scale backward", "hyprshell system/monitor-scale.sh --reverse")
	submap_exec("D", "[System] toggle laptop display", "hyprshell system/monitor-internal.sh toggle")
	submap_exec("M", "[System] toggle mirroring", "hyprshell system/monitor-mirror.sh toggle")
	submap_repeat_action("Z", "[System] zoom in", magnify_by(magnifier_step))
	submap_repeat_action("SHIFT + Z", "[System] zoom out", magnify_by(1 / magnifier_step))
end)

for workspace = 1, 10 do
	local code = workspace_code(workspace)
	local special = numbered_special_workspaces[workspace]
	local description, action = numbered_workspace_action(workspace)
	bind(mod, code, description, action)
	bind(
		mod .. " SHIFT",
		code,
		special and special.move_description or "[Workspaces] move window to workspace " .. workspace,
		hl.dsp.window.move({ workspace = special and special.workspace or workspace })
	)
	bind(
		mod .. " ALT",
		code,
		special and special.alt_description or "[Workspaces] move window silently to workspace " .. workspace,
		special and special.alt_action or hl.dsp.window.move({ workspace = workspace, follow = false })
	)
end

bind(mod .. " CTRL", "RIGHT", "[Workspaces] next relative workspace", hl.dsp.focus({ workspace = "r+1" }))
bind(mod .. " CTRL", "LEFT", "[Workspaces] previous relative workspace", hl.dsp.focus({ workspace = "r-1" }))
bind(
	mod .. " CTRL",
	"UP",
	"[Workspaces] previous workspace",
	niri_or(hl.dsp.focus({ workspace = "r-1" }), hl.dsp.focus({ workspace = "previous" }))
)
bind(
	mod .. " CTRL",
	"DOWN",
	"[Workspaces] nearest empty workspace",
	niri_or(hl.dsp.focus({ workspace = "r+1" }), hl.dsp.focus({ workspace = "empty" }))
)
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
