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

-- Manifest-less themes must stay on the xcursor path: their hyprcursor
-- fallback ignores the requested size.
local function has_hyprcursor_manifest(theme)
    local dirs = {
        vars.get("XDG_DATA_HOME", os.getenv("HOME") .. "/.local/share") .. "/icons/",
        os.getenv("HOME") .. "/.icons/",
        "/usr/share/icons/",
    }
    for _, dir in ipairs(dirs) do
        local f = io.open(dir .. theme .. "/manifest.hl", "r")
        if f then
            f:close()
            return true
        end
    end
    return false
end

local cursor_theme = vars.get("CURSOR_THEME", "Bibata-Modern-Ice")
local cursor_size = vars.get("CURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", cursor_theme, true)
hl.env("XCURSOR_SIZE", cursor_size, true)
hl.env("HYPRCURSOR_THEME", cursor_theme, true)
hl.env("HYPRCURSOR_SIZE", cursor_size, true)
hl.config({cursor = {
    enable_hyprcursor = has_hyprcursor_manifest(cursor_theme),
    sync_gsettings_theme = false,
}})

require("windowrules")
require("userprefs")
require("keybindings")
runtime.load(config_home .. "/hypr/monitors.lua")
runtime.load(state_home .. "/hypr/monitor-toggles.lua", true)
runtime.load(state_home .. "/hypr/workflows.lua")
runtime.load(state_home .. "/hypr/window-layout.lua", true)
require("workspaces")
