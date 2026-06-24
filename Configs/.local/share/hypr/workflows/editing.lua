-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "")
vars.set("WORKFLOW_DESCRIPTION", "Best for writing and editing // Disables xray and blur that might affect color picking/contrast")
runtime.config("decoration.blur.enabled", 1)
runtime.config("decoration.active_opacity", 1)
runtime.config("decoration.inactive_opacity", 1)
runtime.config("decoration.fullscreen_opacity", 1)
hl.window_rule({["name"] = "lua:workflow:editing:15", ["match"] = {["class"] = "(.*)"}, ["opaque"] = true})
hl.layer_rule({["name"] = "lua:workflow:editing:17", ["match"] = {["namespace"] = "waybar"}, ["blur"] = true})
hl.layer_rule({["name"] = "lua:workflow:editing:18", ["match"] = {["namespace"] = "notifications"}, ["blur"] = true})
hl.layer_rule({["name"] = "lua:workflow:editing:19", ["match"] = {["namespace"] = "rofi"}, ["blur"] = true})
