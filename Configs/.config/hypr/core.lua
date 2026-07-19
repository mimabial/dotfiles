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
        blur = {special = false},
    },
    animations = {enabled = true},
    input = {accel_profile = "flat", numlock_by_default = true},
    dwindle = {preserve_split = true},
    master = {new_status = "master"},
    misc = {
        vrr = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        anr_missed_pings = 5,
        allow_session_lock_restore = true,
    },
    xwayland = {force_zero_scaling = true},
    general = {snap = {enabled = true}},
})

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
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
env_default("QT_QPA_PLATFORM", "wayland;xcb")
env_default("MOZ_ENABLE_WAYLAND", "1")
env_default("GDK_SCALE", "1")
env_default("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("PATH", home .. "/.local/bin:" .. home .. "/.local/lib/hypr:" .. (os.getenv("PATH") or ""))

-- Generated palette is consumed before the theme override.
runtime.load(config_home .. "/hypr/themes/colors.lua")
local function color(name, fallback)
    return "rgba(" .. vars.get(name, fallback) .. ")"
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
                active = color("color3ee", "89b4faee"),
                inactive = color("color1ee", "f38ba8ee"),
                locked_active = color("color2ee", "a6e3a1ee"),
                locked_inactive = color("color4ee", "89b4faee"),
            },
            text_color = color("color15ee", "cdd6f4ee"),
            text_color_inactive = color("color7ee", "bac2deee"),
            blur = true,
            font_size = tonumber(vars.get("FONT_SIZE", "10")),
            font_family = vars.get("GROUPBAR_FONT", "Cantarell"),
        },
    },
    decoration = {
        screen_shader = cache_home .. "/hypr/shaders/compiled.cache.glsl",
    },
})

hl.exec_cmd("mkdir -p '" .. (vars.get("XDG_RUNTIME_DIR") or "") .. "/hypr' '" .. cache_home .. "/hypr/wal' '" .. config_home .. "/hypr' '" .. data_home .. "/hypr' '" .. state_home .. "/hypr' && python3 '" .. vars.get("scrPath") .. "/keybinds/lib/keybinds_hint.py' --format rofi > '" .. (vars.get("XDG_RUNTIME_DIR") or "") .. "/hypr/keybinds_hint.rofi'")

local startup = {
    "dbus-update-activation-environment --systemd --all",
    vars.get("start.DBUS_SHARE_PICKER"),
    vars.get("start.SYSTEMD_SHARE_PICKER"),
    vars.get("start.XDG_PORTAL_RESET"),
    vars.get("start.KEYBIND_SYNC"),
    vars.get("start.SUBMAP_HINT"),
    vars.get("start.THEME_OUTPUT_SYNC"),
    vars.get("start.AUTO_THEME"),
    vars.get("start.IDLE_DAEMON"),
    vars.get("start.IDLE_MANAGER"),
    vars.get("start.ZSH_ZCOMPDUMP"),
    vars.get("start.AUTH_DIALOGUE"),
    vars.get("start.WALLPAPER"),
    vars.get("start.BAR"),
    vars.get("start.NOTIFICATIONS"),
    "xsettingsd",
    vars.get("start.TEXT_CLIPBOARD"),
    vars.get("start.IMAGE_CLIPBOARD"),
    vars.get("start.NETWORK_MANAGER"),
    vars.get("start.REMOVABLE_MEDIA"),
    vars.get("start.APPTRAY_BLUETOOTH"),
    vars.get("start.BATTERY_NOTIFY"),
    "hyprshell theme/desktop.sync",
    vars.get("start.FFTAB_BRIDGE"),
}

hl.on("hyprland.start", function()
    for _, command in ipairs(startup) do
        if command and command ~= "" then
            hl.exec_cmd(vars.expand(command))
        end
    end
end)

return {vars = vars, runtime = runtime}
