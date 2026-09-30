local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "")
vars.set("WORKFLOW_DESCRIPTION", "macOS-style desktop // menu bar, bottom dock, floating windows")
vars.set("WORKFLOW_QUICKSHELL_LAYOUT", "macos")

runtime.config("decoration.rounding", 10)
runtime.config("decoration.shadow.enabled", 1)
runtime.config("general.border_size", 1)
hl.animation({leaf = "windowsIn", enabled = true, speed = 4, bezier = "winIn", style = "popin 80%"})
hl.window_rule({name = "workflow-macos-float", match = {class = "(.*)"}, float = true})
