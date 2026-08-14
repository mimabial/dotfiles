-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "󰽏")
vars.set("WORKFLOW_DESCRIPTION", "Window-focused workspace // Uses scrolling and winbar with effects disabled")
vars.set("WORKFLOW_WAYBAR_OPACITY", "0.5")
vars.set("WORKFLOW_WAYBAR_LAYOUT", "winbar")
runtime.config("decoration.shadow.enabled", 0)
runtime.config("decoration.blur.enabled", 0)
runtime.config("decoration.blur.xray", 1)
runtime.config("decoration.active_opacity", 0.99)
runtime.config("decoration.inactive_opacity", 0.99)
runtime.config("decoration.fullscreen_opacity", 0.99)
runtime.config("general.layout", "scrolling")
runtime.config("general.gaps_in", 3)
runtime.config("general.gaps_out", 6)
runtime.config("general.border_size", 2)
runtime.config("animations.enabled", 1)
hl.layer_rule({ ["name"] = "lua:workflow:windows:29", ["match"] = { ["namespace"] = "waybar" }, ["animation"] = "none" })
hl.layer_rule({
	["name"] = "lua:workflow:windows:30",
	["match"] = { ["namespace"] = "notifications" },
	["animation"] = "none",
})
hl.layer_rule({
	["name"] = "lua:workflow:windows:31",
	["match"] = { ["namespace"] = "awww-daemon" },
	["animation"] = "none",
})
hl.layer_rule({ ["name"] = "lua:workflow:windows:32", ["match"] = { ["namespace"] = "rofi" }, ["animation"] = "none" })
hl.window_rule({
	["name"] = "lua:workflow:windows:34",
	["match"] = { ["class"] = "^(kitty)$" },
	["opacity"] = "0.98 override 0.9 override",
})
hl.window_rule({
	["name"] = "lua:workflow:windows:35",
	["match"] = { ["class"] = "^(Alacritty)$" },
	["opacity"] = "0.98 override 0.9 override",
})
hl.window_rule({
	["name"] = "lua:workflow:windows:36",
	["match"] = { ["class"] = "^(firefox)$" },
	["opacity"] = "1.0 override 0.9 override",
})
hl.window_rule({
	["name"] = "lua:workflow:windows:37",
	["match"] = { ["class"] = "^(org\\.kde\\.dolphin)$" },
	["opacity"] = "0.98 override 0.9 override",
})
