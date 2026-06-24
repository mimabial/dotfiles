-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW", "default")
vars.set("WORKFLOW_ICON", "")
vars.set("WORKFLOW_DESCRIPTION", "Unset workflow configuration")
local workflow_path = vars.get("XDG_DATA_HOME") .. "/hypr/workflows/default.lua"
vars.set("WORKFLOW_PATH", workflow_path)
runtime.load(workflow_path)
