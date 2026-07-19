local M = {}

local values = {
    HOME = os.getenv("HOME") or "/home/rifle",
    XDG_CONFIG_HOME = os.getenv("XDG_CONFIG_HOME") or ((os.getenv("HOME") or "/home/rifle") .. "/.config"),
    XDG_CACHE_HOME = os.getenv("XDG_CACHE_HOME") or ((os.getenv("HOME") or "/home/rifle") .. "/.cache"),
    XDG_DATA_HOME = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "/home/rifle") .. "/.local/share"),
    XDG_STATE_HOME = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "/home/rifle") .. "/.local/state"),
    XDG_RUNTIME_DIR = os.getenv("XDG_RUNTIME_DIR") or ("/run/user/" .. tostring(os.getenv("UID") or "1000")),
    scrPath = (os.getenv("HOME") or "/home/rifle") .. "/.local/lib/hypr",
    mainMod = "SUPER",
    BROWSER = "firefox",
    EDITOR = "nvim",
    EXPLORER = "dolphin",
    TERMINAL = "kitty",
    TERMINAL2 = "alacritty",
    TERMINAL_TUI = "kitty",
    LOCKSCREEN = "hyprlock",
    ["list.environment"] = "WAYLAND_DISPLAY XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CONFIG_HOME QT_QPA_PLATFORM QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE XCURSOR_THEME XCURSOR_SIZE XCURSOR_PATH",
    ["start.XDG_PORTAL_RESET"] = "hyprshell reset-xdg-portal.sh",
    ["start.KEYBIND_SYNC"] = "hyprshell keyboard-switch.sh --sync-current --quiet",
    ["start.SUBMAP_HINT"] = "hyprshell app -u hyprland-submap-hint.service -t service -- hyprshell keybinds/submap-hint",
    ["start.FFTAB_BRIDGE"] = "hyprshell media/fftab-bridge/ensure",
    ["start.THEME_OUTPUT_SYNC"] = "hyprshell theme/startup-sync.sh",
    ["start.AUTH_DIALOGUE"] = "hyprshell app -t service -- hyprshell session/polkit-kde-auth",
    ["start.BAR"] = "hyprshell app -u hyprland-waybar-watcher.service -t service -- hyprshell waybar/waybar --watch",
    ["start.WALLPAPER"] = "hyprshell app -u hyprland-wallpaper.service -t service -- hyprshell wallpaper start --global",
    ["start.NOTIFICATIONS"] = "hyprshell app -t service dunst",
    ["start.TEXT_CLIPBOARD"] = "hyprshell app -t service wl-paste --type text --watch cliphist store",
    ["start.IMAGE_CLIPBOARD"] = "hyprshell app -t service wl-paste --type image --watch cliphist store",
    ["start.CLIPBOARD_PERSIST"] = "hyprshell app -t service wl-clip-persist --clipboard regular",
    ["start.NETWORK_MANAGER"] = "hyprshell system/start-if-available.sh HYPR_START_NETWORK_MANAGER nm-applet -- hyprshell app -t service nm-applet --indicator",
    ["start.REMOVABLE_MEDIA"] = "hyprshell system/start-if-available.sh HYPR_START_REMOVABLE_MEDIA udiskie -- hyprshell app -t service udiskie --no-automount --smart-tray",
    ["start.APPTRAY_BLUETOOTH"] = "hyprshell system/start-if-available.sh HYPR_START_BLUETOOTH_APPLET blueman-applet -- hyprshell app -t service blueman-applet",
    ["start.BATTERY_NOTIFY"] = "hyprshell app -t service -- hyprshell sysinfo/battery-notify",
    ["start.IDLE_DAEMON"] = "systemctl --user start --no-block hyprland-hypridle.service",
    ["start.AUTO_THEME"] = "hyprshell auto-theme-startup",
    ["start.IDLE_MANAGER"] = "systemctl --user start --no-block hyprland-idle-manager.service",
    ["start.ZSH_ZCOMPDUMP"] = "systemctl --user start --no-block zsh-zcompdump-clean.timer",
    ICON_THEME = "Tela-circle-dracula",
    COLOR_SCHEME = "prefer-dark",
    BUTTON_LAYOUT = "",
    CURSOR_THEME = "Bibata-Modern-Ice",
    CURSOR_SIZE = "24",
    FONT = "Cantarell",
    FONT_SIZE = "10",
    DOCUMENT_FONT = "Cantarell",
    DOCUMENT_FONT_SIZE = "10",
    MONOSPACE_FONT = "JetBrainsMono Nerd Font",
    MONOSPACE_FONT_SIZE = "9",
    NOTIFICATION_FONT = "Mononoki Nerd Font Mono",
    BAR_FONT = "JetBrainsMono Nerd Font",
    MENU_FONT = "JetBrainsMono Nerd Font",
    GROUPBAR_FONT = "Cantarell",
    FONT_ANTIALIASING = "rgba",
    FONT_HINTING = "",
}

values["start.DBUS_SHARE_PICKER"] = "dbus-update-activation-environment --systemd " .. values["list.environment"]
values["start.SYSTEMD_SHARE_PICKER"] = "systemctl --user import-environment " .. values["list.environment"]

function M.set(name, value)
    values[name] = tostring(value or "")
end

function M.get(name, fallback)
    local value = values[name]
    if value == nil then
        value = os.getenv(name)
    end
    if value == nil then
        value = fallback
    end
    return value
end

function M.expand(value)
    local expanded = tostring(value or "")
    for _ = 1, 12 do
        local changed = false
        expanded = expanded:gsub("%$([%w_.&%-]+)", function(name)
            local replacement = M.get(name)
            if replacement == nil then
                return "$" .. name
            end
            changed = true
            return replacement
        end)
        if not changed then
            break
        end
    end
    return expanded
end

function M.all()
    return values
end

return M
