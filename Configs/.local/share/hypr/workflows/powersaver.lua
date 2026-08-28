-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "")
vars.set("WORKFLOW_DESCRIPTION", "Saves as much power as possible by disabling all animations and effects, but preserving readability")
vars.set("WORKFLOW_WAYBAR_OPACITY", "1")
runtime.config("decoration.shadow.enabled", 0)
runtime.config("decoration.blur.enabled", 0)
-- the selected shader is a pass-through, so the post-process pass costs a frame copy for no effect
runtime.config("decoration.screen_shader", "")
runtime.config("animations.enabled", 0)
hl.window_rule({name = "workflow-powersaver-opaque", match = {class = "(.*)"}, opacity = "1 override 1 override 1 override", opaque = true})
