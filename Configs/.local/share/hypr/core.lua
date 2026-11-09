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
        focus_on_activate = true,
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

local COLUMN_ROUNDING_SLACK_PX = 1

local function scrolling_columns(workspace)
    local windows = hl.get_windows({workspace = workspace, floating = false, mapped = true})
    table.sort(windows, function(a, b) return a.at.x < b.at.x end)
    local columns = {}
    for _, window in ipairs(windows) do
        if #columns == 0 or columns[#columns].at.x ~= window.at.x then columns[#columns + 1] = window end
    end
    return columns
end

local function monitor_usable_box(monitor)
    local width, height = monitor.size.width / monitor.scale, monitor.size.height / monitor.scale
    if monitor.transform % 2 == 1 then width, height = height, width end
    local reserved = monitor.reserved
    return monitor.position.x + reserved.left, monitor.position.y + reserved.top,
        width - reserved.left - reserved.right, height - reserved.top - reserved.bottom
end

local function tiled_area(monitor)
    local gaps = hl.get_config("general.gaps_out")
    local x, y, width, height = monitor_usable_box(monitor)
    return x + gaps.left, y + gaps.top, width - gaps.left - gaps.right, height - gaps.top - gaps.bottom
end

local function floating_area(monitor)
    local x, y, width, height = tiled_area(monitor)
    local border = hl.get_config("general.border_size")
    return x + border, y + border, width - 2 * border, height - 2 * border
end

local function usable_edges(workspace)
    local x, _, width = tiled_area(workspace.monitor)
    local border = hl.get_config("general.border_size")
    return x + border, x + width - border
end

local function column_end(column)
    return column.at.x + column.size.x
end

local function fills_screen(workspace, columns)
    local left, right = usable_edges(workspace)
    return column_end(columns[#columns]) - columns[1].at.x >= right - left - COLUMN_ROUNDING_SLACK_PX
end

local function column_index(columns, window)
    for index, column in ipairs(columns) do
        if column.at.x == window.at.x then return index end
    end
    return 0
end

local function pair_centring_offset(columns, active_index, left, right)
    local pair_start = math.min(active_index, #columns - 2)
    local pair_centre = (columns[pair_start].at.x + column_end(columns[pair_start + 1])) / 2
    return (left + right) / 2 - pair_centre
end

local function edge_gap_offset(columns, left, right)
    local first_start, last_end = columns[1].at.x, column_end(columns[#columns])
    if first_start > left then return left - first_start end
    if last_end < right then return right - last_end end
    return 0
end

local function sync_scrolling(window, expand_to_fill)
    local workspace = hl.get_active_special_workspace() or hl.get_active_workspace()
    if not workspace or workspace.tiled_layout ~= "scrolling" or window and (window.workspace ~= workspace or window.floating) then return end
    local active = hl.get_active_window()
    if not active or active.floating or active.workspace ~= workspace then return end
    local columns = scrolling_columns(workspace)
    if expand_to_fill and not fills_screen(workspace, columns) then hl.dispatch(hl.dsp.layout("fit expand")) end
    if #columns <= 2 then return end
    local left, right = usable_edges(workspace)
    local active_index = column_index(columns, active)
    local scroll_offset
    if #columns > 3 and active_index > 1 and active_index < #columns then
        scroll_offset = pair_centring_offset(columns, active_index, left, right)
    else
        scroll_offset = edge_gap_offset(columns, left, right)
    end
    if scroll_offset == 0 then return end
    hl.dispatch(hl.dsp.layout("move " .. (scroll_offset > 0 and "+" or "") .. scroll_offset))
    focus_without_warp(active)
end

local function refill_scrolling_pair()
    local workspace, active = hl.get_active_special_workspace() or hl.get_active_workspace(), hl.get_active_window()
    if not (workspace and active and workspace.tiled_layout == "scrolling") or active.floating then return end
    local columns = scrolling_columns(workspace)
    if #columns ~= 2 or fills_screen(workspace, columns) then return end
    focus_without_warp(columns[1].at.x == active.at.x and columns[2] or columns[1])
    hl.dispatch(hl.dsp.layout("fit expand"))
    focus_without_warp(active)
end

local function expand_scrolling_column()
    local workspace, active = hl.get_active_special_workspace() or hl.get_active_workspace(), hl.get_active_window()
    if not (workspace and active and workspace.tiled_layout == "scrolling") or active.floating then return end
    local gaps, border = hl.get_config("general.gaps_in"), hl.get_config("general.border_size")
    local left, right = usable_edges(workspace)
    local window_left, window_right = left + gaps.left, right - gaps.right
    local first, last = active, active
    for _, column in ipairs(scrolling_columns(workspace)) do
        if column.at.x >= window_left - COLUMN_ROUNDING_SLACK_PX and column_end(column) <= window_right + COLUMN_ROUNDING_SLACK_PX then
            if column.at.x < first.at.x then first = column end
            if column_end(column) > column_end(last) then last = column end
        end
    end
    local free = window_right - window_left - (column_end(last) - first.at.x)
    if free <= COLUMN_ROUNDING_SLACK_PX then return end
    hl.dispatch(hl.dsp.layout(string.format("colresize %+f", free / (right - left + 2 * border))))
    local scroll_offset = window_left - first.at.x
    if math.abs(scroll_offset) <= COLUMN_ROUNDING_SLACK_PX then return end
    hl.dispatch(hl.dsp.layout("move " .. (scroll_offset > 0 and "+" or "") .. scroll_offset))
    focus_without_warp(active)
end
for _, event in ipairs({"window.open", "window.move_to_workspace"}) do hl.on(event, function(window) sync_scrolling(window) end) end
local mouse_focus_reasons = hl.version():match("^0%.56%.") and {hover = 1, click = 5}
    or {hover = 1, click = 16, click_down = 48, click_up = 80}
local mouse_focus = {}
for _, reason in pairs(mouse_focus_reasons) do mouse_focus[reason] = true end
local expand_after_close = false
hl.on("window.close", function(window) expand_after_close = not window.floating and window.workspace == (hl.get_active_special_workspace() or hl.get_active_workspace()) end)
for _, event in ipairs({"window.destroy", "window.active", "workspace.active"}) do
    hl.on(event, function(_, reason)
        if mouse_focus[reason] then return end
        sync_scrolling(nil, expand_after_close)
        expand_after_close = false
    end)
end
sync_scrolling()

local function fit_floating_window(window)
    if not window.floating then return end
    local _, _, width, height = floating_area(window.monitor)
    if window.size.x <= width and window.size.y <= height then return end
    local target = "address:" .. window.address
    hl.dispatch(hl.dsp.window.resize({window = target, x = math.min(window.size.x, math.floor(width)), y = math.min(window.size.y, math.floor(height)), exact = true}))
    hl.dispatch(hl.dsp.window.center({window = target, respect_reserved = true}))
end
hl.on("window.open", fit_floating_window)

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

local startup = {
    vars.get("start.ACTIVATION_ENVIRONMENT"),
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
    vars.get("start.XSETTINGS"),
    vars.get("start.TEXT_CLIPBOARD"),
    vars.get("start.IMAGE_CLIPBOARD"),
    vars.get("start.CLIPBOARD_PERSIST"),
    vars.get("start.APPTRAY_BLUETOOTH"),
    vars.get("start.BATTERY_NOTIFY"),
    vars.get("start.DESKTOP_SYNC"),
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

return {vars = vars, runtime = runtime, refill_scrolling_pair = refill_scrolling_pair,
    expand_scrolling_column = expand_scrolling_column, usable_edges = usable_edges, floating_area = floating_area}
