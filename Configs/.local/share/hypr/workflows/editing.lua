-- Generated native Hyprland Lua. Do not edit manually.
local vars = require("vars")

vars.set("WORKFLOW_ICON", "")
vars.set("WORKFLOW_DESCRIPTION", "Opaque application windows for accurate contrast")
hl.window_rule({name = "workflow-editing-opaque", match = {class = "(.*)"}, opacity = "1 override 1 override 1 override", opaque = true})
