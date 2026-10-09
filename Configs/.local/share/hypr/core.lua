local vars = require("vars")
local runtime = require("runtime")

local home = vars.get("HOME")
local config_home = vars.get("XDG_CONFIG_HOME")
local cache_home = vars.get("XDG_CACHE_HOME")
local data_home = vars.get("XDG_DATA_HOME")
local state_home = vars.get("XDG_STATE_HOME")

hl.monitor({output = "", mode = "preferred", position = "auto", scale = "auto"})

hl.config({
    decoration = {
        dim_special = 0.5,
        active_opacity = 0.90,
        inactive_opacity = 0.75,
        fullscreen_opacity = 1,
        blur = {special = false, popups = true},
    },
    animations = {enabled = true},
    input = {accel_profile = "flat", numlock_by_default = true, resolve_binds_by_sym = true},
    dwindle = {preserve_split = true},
    master = {new_status = "master"},
    scrolling = {column_width = 0.5},
    misc = {
        vrr = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        anr_missed_pings = 5,
        allow_session_lock_restore = true,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },
    xwayland = {force_zero_scaling = true},
    general = {snap = {enabled = true}},
})

local function focus_without_warp(window)
    local no_warps = hl.get_config("cursor.no_warps")
    hl.config({cursor = {no_warps = true}})
    hl.dispatch(hl.dsp.focus({window = "address:" .. window.address}))
    hl.config({cursor = {no_warps = no_warps}})
end

local function scrolling_columns(ws)
    local windows = hl.get_windows({workspace = ws, floating = false, mapped = true})
    table.sort(windows, function(a, b) return a.at.x < b.at.x end)
    local columns = {}
    for _, window in ipairs(windows) do
        if #columns == 0 or columns[#columns].at.x ~= window.at.x then columns[#columns + 1] = window end
    end
    return columns
end

local function usable_area(m)
    local gaps = hl.get_config("general.gaps_out")
    local left, top = m.reserved.left + gaps.left, m.reserved.top + gaps.top
    local right, bottom = m.reserved.right + gaps.right, m.reserved.bottom + gaps.bottom
    return m.position.x + left, m.position.y + top, m.size.width / m.scale - left - right, m.size.height / m.scale - top - bottom
end

local function usable_edges(ws)
    local x, _, width = usable_area(ws.monitor)
    local border = hl.get_config("general.border_size")
    return x + border, x + width - border
end

local function fills_screen(ws, columns)
    local left, right = usable_edges(ws)
    return columns[#columns].at.x + columns[#columns].size.x - columns[1].at.x >= right - left - 1
end

local function sync_scrolling(window, expand_to_fill)
    local ws = hl.get_active_special_workspace() or hl.get_active_workspace()
    if not ws or ws.tiled_layout ~= "scrolling" or window and (window.workspace ~= ws or window.floating) then return end
    local active = hl.get_active_window()
    if not active or active.floating or active.workspace ~= ws then return end
    local columns = scrolling_columns(ws)
    if expand_to_fill and not fills_screen(ws, columns) then hl.dispatch(hl.dsp.layout("fit expand")) end
    if #columns <= 2 then return end
    local left, right = usable_edges(ws)
    local index, shift = 0, 0
    for i, w in ipairs(columns) do if w.at.x == active.at.x then index = i; break end end
    if #columns > 3 and index > 1 and index < #columns then
        local pair = math.min(index, #columns - 2)
        shift = (left + right - columns[pair].at.x - columns[pair + 1].at.x - columns[pair + 1].size.x) / 2
    else
        local first, last = columns[1], columns[#columns]
        shift = first.at.x > left and left - first.at.x or last.at.x + last.size.x < right and right - last.at.x - last.size.x or 0
    end
    if shift == 0 then return end
    hl.dispatch(hl.dsp.layout("move " .. (shift > 0 and "+" or "") .. shift))
    focus_without_warp(active)
end

local function refill_scrolling_pair()
    local ws, active = hl.get_active_special_workspace() or hl.get_active_workspace(), hl.get_active_window()
    if not (ws and active and ws.tiled_layout == "scrolling") or active.floating then return end
    local columns = scrolling_columns(ws)
    if #columns ~= 2 or fills_screen(ws, columns) then return end
    focus_without_warp(columns[1].at.x == active.at.x and columns[2] or columns[1])
    hl.dispatch(hl.dsp.layout("fit expand"))
    focus_without_warp(active)
end
for _, event in ipairs({"window.open", "window.move_to_workspace"}) do hl.on(event, function(window) sync_scrolling(window) end) end
local expand_after_close = false
hl.on("window.close", function(window) expand_after_close = not window.floating and window.workspace == (hl.get_active_special_workspace() or hl.get_active_workspace()) end)
for _, event in ipairs({"window.destroy", "window.active", "workspace.active"}) do hl.on(event, function() sync_scrolling(nil, expand_after_close); expand_after_close = false end) end
sync_scrolling()

local function fit_floating_window(window)
    if not window.floating then return end
    local _, _, width, height = usable_area(window.monitor)
    if window.size.x <= width and window.size.y <= height then return end
    local target = "address:" .. window.address
    hl.dispatch(hl.dsp.window.resize({window = target, x = math.min(window.size.x, math.floor(width)), y = math.min(window.size.y, math.floor(height)), exact = true}))
    hl.dispatch(hl.dsp.window.center({window = target, respect_reserved = true}))
end
hl.on("window.open", fit_floating_window)

hl.curve("wind", {type = "bezier", points = {{0.05, 0.9}, {0.1, 1.05}}})
hl.curve("winIn", {type = "bezier", points = {{0.1, 1.1}, {0.1, 1.1}}})
hl.curve("winOut", {type = "bezier", points = {{0.3, -0.3}, {0, 1}}})
hl.curve("liner", {type = "bezier", points = {{1, 1}, {1, 1}}})
hl.animation({leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide"})
hl.animation({leaf = "windowsIn", enabled = true, speed = 6, bezier = "winIn", style = "slide"})
hl.animation({leaf = "windowsOut", enabled = true, speed = 5, bezier = "winOut", style = "slide"})
hl.animation({leaf = "windowsMove", enabled = true, speed = 5, bezier = "wind", style = "slide"})
hl.animation({leaf = "border", enabled = true, speed = 1, bezier = "liner"})
hl.animation({leaf = "borderangle", enabled = true, speed = 30, bezier = "liner", style = "once"})
hl.animation({leaf = "fade", enabled = true, speed = 10, bezier = "default"})
hl.animation({leaf = "workspaces", enabled = true, speed = 5, bezier = "wind"})

local function env_default(name, value)
    hl.env(name, os.getenv(name) or value)
end

env_default("XDG_CURRENT_DESKTOP", "Hyprland")
env_default("XDG_SESSION_TYPE", "wayland")
env_default("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_CONFIG_HOME", config_home)
hl.env("XDG_CACHE_HOME", cache_home)
hl.env("XDG_DATA_HOME", data_home)
hl.env("XDG_STATE_HOME", state_home)
env_default("XCURSOR_PATH", data_home .. "/icons:" .. home .. "/.icons:/usr/share/icons")
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_FONT_DPI", "96")
env_default("QT_QPA_PLATFORM", "wayland;xcb")
env_default("MOZ_ENABLE_WAYLAND", "1")
env_default("GDK_SCALE", "1")
env_default("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("PATH", home .. "/.local/bin:" .. home .. "/.local/lib/hypr:" .. (os.getenv("PATH") or ""))

-- Generated palette is consumed before the theme override.
runtime.load(config_home .. "/hypr/themes/colors.lua")
local function color(name)
    return "rgba(" .. vars.get(name) .. ")"
end
hl.config({
    group = {
        groupbar = {
            enabled = true,
            gradients = true,
            render_titles = true,
            font_weight_inactive = "normal",
            font_weight_active = "semibold",
            col = {
                active = color("color3ee"),
                inactive = color("color1ee"),
                locked_active = color("color2ee"),
                locked_inactive = color("color4ee"),
            },
            text_color = color("color15ee"),
            text_color_inactive = color("color7ee"),
            blur = true,
            font_size = tonumber(vars.get("FONT_SIZE")),
            font_family = vars.get("GROUPBAR_FONT"),
        },
    },
    decoration = {
        screen_shader = cache_home .. "/hypr/shaders/compiled.cache.glsl",
    },
})

hl.exec_cmd("mkdir -p '" .. (vars.get("XDG_RUNTIME_DIR") or "") .. "/hypr' '" .. config_home .. "/hypr' '" .. data_home .. "/hypr' '" .. state_home .. "/hypr' && python3 '" .. vars.get("scrPath") .. "/keybinds/lib/keybinds_hint.py' --format rofi > '" .. (vars.get("XDG_RUNTIME_DIR") or "") .. "/hypr/keybinds_hint.rofi'")

local startup = {
    "dbus-update-activation-environment --systemd --all",
    vars.get("start.USER_SUPERVISOR"),
    vars.get("start.XDG_PORTAL_RESET"),
    vars.get("start.KEYBIND_SYNC"),
    vars.get("start.SUBMAP_HINT"),
    vars.get("start.DISPLAY_PROFILES"),
    vars.get("start.AUTO_THEME"),
    vars.get("start.LOGIND_INHIBITOR"),
    vars.get("start.IDLE_MANAGER"),
    vars.get("start.POWER_PROFILE_AUTO"),
    vars.get("start.ZSH_ZCOMPDUMP"),
    vars.get("start.AUTH_DIALOGUE"),
    vars.get("start.LOCATION_AGENT"),
    vars.get("start.WALLPAPER"),
    vars.get("start.QUICKSHELL"),
    vars.get("start.STYLE_MAP"),
    vars.get("start.NOTIFICATIONS"),
    vars.get("start.WORKFLOW_RECONCILE"),
    "hyprshell app -t service xsettingsd",
    vars.get("start.TEXT_CLIPBOARD"),
    vars.get("start.IMAGE_CLIPBOARD"),
    vars.get("start.CLIPBOARD_PERSIST"),
    vars.get("start.APPTRAY_BLUETOOTH"),
    vars.get("start.BATTERY_NOTIFY"),
    "hyprshell theme/desktop.sync",
    vars.get("start.FFTAB_BRIDGE"),
    vars.get("start.GAMEMODE"),
    vars.get("start.TORRENT"),
    vars.get("start.CALDAV"),
    vars.get("start.CALDAV_SYNC"),
}

hl.on("hyprland.start", function()
    for _, command in ipairs(startup) do
        if command and command ~= "" then
            hl.exec_cmd(vars.expand(command))
        end
    end
end)

return {vars = vars, runtime = runtime, refill_scrolling_pair = refill_scrolling_pair, usable_edges = usable_edges}
