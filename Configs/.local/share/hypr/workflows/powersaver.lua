local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "")
vars.set("WORKFLOW_DESCRIPTION", "Saves as much power as possible by disabling all animations and effects, but preserving readability")
runtime.config_if_supported("decoration.shadow.enabled", false)
runtime.config_if_supported("decoration.blur.enabled", false)
-- the selected shader is a pass-through, so the post-process pass costs a frame copy for no effect
runtime.config_if_supported("decoration.screen_shader", "")
runtime.config_if_supported("animations.enabled", false)
hl.window_rule({name = "workflow-powersaver-opaque", match = {class = "(.*)"}, opacity = "1 override 1 override 1 override", opaque = true})
