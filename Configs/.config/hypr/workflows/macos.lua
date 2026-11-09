local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "󰀵")
vars.set("WORKFLOW_DESCRIPTION", "macOS-style desktop // menu bar, bottom dock, master layout")
vars.set("WORKFLOW_QUICKSHELL_LAYOUT", "macos")

local layout = vars.get("WORKFLOW_LAYOUT_OVERRIDE", "")
runtime.config_if_supported("general.layout", layout ~= "" and layout or "master")
require("animations.macos")
