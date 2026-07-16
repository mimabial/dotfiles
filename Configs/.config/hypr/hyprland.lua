local core = require("core")
local vars = core.vars
local runtime = core.runtime

local config_home = vars.get("XDG_CONFIG_HOME")
local state_home = vars.get("XDG_STATE_HOME")

runtime.load(config_home .. "/hypr/themes/theme.lua")
runtime.load(config_home .. "/hypr/userfonts.lua", true)
require("gpu")
runtime.load(state_home .. "/hypr/animations.lua")
runtime.load(state_home .. "/hypr/shaders.lua")

hl.config({misc = {font_family = vars.get("FONT", "Cantarell")}})
hl.env("XCURSOR_THEME", vars.get("CURSOR_THEME", "Bibata-Modern-Ice"), true)
hl.env("XCURSOR_SIZE", vars.get("CURSOR_SIZE", "24"), true)
hl.env("HYPRCURSOR_THEME", vars.get("CURSOR_THEME", "Bibata-Modern-Ice"), true)
hl.env("HYPRCURSOR_SIZE", vars.get("CURSOR_SIZE", "24"), true)
-- Force xcursor: xcursor-only themes have no hyprcursor manifest.
hl.config({cursor = {enable_hyprcursor = false}})

require("windowrules")
require("userprefs")
require("keybindings")
runtime.load(config_home .. "/hypr/monitors.lua")
runtime.load(state_home .. "/hypr/monitor-toggles.lua", true)
runtime.load(state_home .. "/hypr/workflows.lua")
runtime.load(state_home .. "/hypr/window-layout.lua", true)
require("workspaces")
