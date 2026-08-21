-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "")
vars.set("WORKFLOW_DESCRIPTION", "Saves as much power as possible by disabling all animations and effects, but preserving readability")
vars.set("WORKFLOW_WAYBAR_OPACITY", "1")
runtime.config("decoration.shadow.enabled", 0)
runtime.config("decoration.blur.enabled", 0)
runtime.config("decoration.rounding", 0)
runtime.config("general.border_size", 1)
runtime.config("animations.enabled", 0)
hl.window_rule({name = "workflow-powersaver-opaque", match = {class = "(.*)"}, opacity = "1 override 1 override 1 override", opaque = true})
