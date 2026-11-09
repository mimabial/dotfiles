local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "󰽏")
vars.set("WORKFLOW_DESCRIPTION", "Window-focused workspace // dwindle layout and winbar")
vars.set("WORKFLOW_QUICKSHELL_LAYOUT", "winbar")
runtime.config_if_supported("decoration.shadow.enabled", false)
runtime.config_if_supported("decoration.blur.enabled", false)
runtime.config_if_supported("decoration.blur.xray", true)
runtime.config_if_supported("decoration.active_opacity", 0.99)
runtime.config_if_supported("decoration.inactive_opacity", 0.99)
runtime.config_if_supported("decoration.fullscreen_opacity", 0.99)
runtime.config_if_supported("general.layout", "dwindle")
runtime.config_if_supported("general.gaps_in", 3)
runtime.config_if_supported("general.gaps_out", 6)
runtime.config_if_supported("general.border_size", 2)
runtime.config_if_supported("animations.enabled", true)
hl.window_rule({
	["name"] = "workflow-windows-translucent-apps",
	["match"] = { ["class"] = "^(kitty|Alacritty|org\\.kde\\.dolphin)$" },
	["opacity"] = "0.98 override 0.9 override",
})
hl.window_rule({
	["name"] = "workflow-windows-firefox-opacity",
	["match"] = { ["class"] = "^(firefox)$" },
	["opacity"] = "1.0 override 0.9 override",
})
