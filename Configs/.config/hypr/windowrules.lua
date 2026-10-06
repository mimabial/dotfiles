-- Native Hyprland window and layer rules.
local window_profiles = require("window_profiles")

hl.window_rule({
	["name"] = "lua:windowrules:12",
	["match"] = { ["class"] = "^(.*haruna.*)$" },
	["idle_inhibit"] = "fullscreen",
})
hl.window_rule({
	["name"] = "lua:windowrules:13",
	["match"] = { ["class"] = "^(.*firefox.*)$|^(.*chromium.*)$" },
	["idle_inhibit"] = "fullscreen",
})
hl.window_rule({ ["name"] = "center-new-floating-windows", ["match"] = { ["float"] = true }, ["center"] = true })
hl.window_rule({
	["name"] = "lua:windowrules:16",
	["match"] = { ["title"] = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" },
	["tag"] = "+picture-in-picture",
})
hl.window_rule({
	["name"] = "picture-in-picture",
	["match"] = { ["tag"] = "picture-in-picture" },
	["float"] = true,
	["keep_aspect_ratio"] = true,
	["move"] = "73% 72%",
	["size"] = window_profiles.rule_size("overlay"),
	["pin"] = true,
})
hl.window_rule({
	["name"] = "dropdown-terminal",
	["match"] = { ["class"] = "^(dropdown-terminal)$" },
	["float"] = true,
	["opacity"] = "0.80 override 0.80 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:27",
	["match"] = { ["class"] = "^(org\\.kde\\.haruna)$", ["initial_title"] = "^Haruna$" },
	["fullscreen"] = true,
})
hl.window_rule({ ["name"] = "lua:windowrules:28", ["match"] = { ["class"] = "^(org\\.kde\\.haruna)$" }, ["float"] = true })
hl.window_rule({
	["name"] = "lua:windowrules:30",
	["match"] = { ["class"] = "^(firefox)$" },
	["opacity"] = "0.90 override 0.90 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:32",
	["match"] = { ["class"] = "^(kitty|org\\.tui\\..*)$" },
	["opacity"] = "0.80 override 0.80 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:33",
	["match"] = { ["class"] = "^(Alacritty)$" },
	["opacity"] = "0.80 override 0.80 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:34",
	["match"] = { ["class"] = "^(org\\.kde\\.dolphin)$" },
	["opacity"] = "0.80 override 0.80 override 1",
})
hl.window_rule({
	["name"] = "ark",
	["match"] = { ["class"] = "^(org\\.kde\\.ark)$" },
	["opacity"] = "0.80 override 0.80 override 1",
	["float"] = true,
})
hl.window_rule({
	["name"] = "lua:windowrules:36",
	["match"] = { ["class"] = "^(org\\.qbittorrent\\.qBittorrent)$" },
	["opacity"] = "0.80 override 0.80 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:37",
	["match"] = { ["class"] = "^(nwg-look)$" },
	["opacity"] = "0.80 override 0.80 override 1",
})
hl.window_rule({
	["name"] = "nwg-displays",
	["match"] = { ["class"] = "^(nwg-displays)$" },
	["opacity"] = "0.80 override 0.80 override 1",
	["float"] = true,
})
hl.window_rule({
	["name"] = "pavucontrol",
	["match"] = { ["class"] = "^(.*pavucontrol.*)$" },
	["opacity"] = "0.80 override 0.70 override 1",
	["float"] = true,
})
hl.window_rule({
	["name"] = "blueman-manager",
	["match"] = { ["class"] = "^(blueman-manager)$" },
	["opacity"] = "0.80 override 0.70 override 1",
	["float"] = true,
})
hl.window_rule({
	["name"] = "lua:windowrules:43",
	["match"] = { ["class"] = "^(nm-connection-editor)$" },
	["opacity"] = "0.80 override 0.70 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:44",
	["match"] = { ["class"] = "^(org\\.kde\\.polkit-kde-authentication-agent-1)$" },
	["opacity"] = "0.80 override 0.70 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:45",
	["match"] = { ["class"] = "^(polkit-gnome-authentication-agent-1)$" },
	["opacity"] = "0.80 override 0.70 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:46",
	["match"] = { ["class"] = "^(org\\.freedesktop\\.impl\\.portal\\.desktop\\.gtk)$" },
	["opacity"] = "0.80 override 0.70 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:47",
	["match"] = { ["class"] = "^(org\\.freedesktop\\.impl\\.portal\\.desktop\\.hyprland)$" },
	["opacity"] = "0.80 override 0.70 override 1",
})
hl.window_rule({
	["name"] = "lua:windowrules:49",
	["match"] = { ["class"] = "^(gimp)$", ["initial_title"] = "^GNU Image Manipulation Program$" },
	["fullscreen"] = true,
})
hl.window_rule({ ["name"] = "lua:windowrules:54", ["match"] = { ["class"] = "^(signal)$" }, ["opacity"] = "0.80 0.80" })
hl.window_rule({
	["name"] = "lua:windowrules:55",
	["match"] = { ["class"] = "^(org\\.pwmt\\.zathura)$" },
	["opacity"] = "0.80 0.80",
})
hl.window_rule({
	["name"] = "bitwarden",
	["match"] = { ["class"] = "^([Bb]itwarden)$" },
	["opacity"] = "0.80 0.80",
	["no_screen_share"] = true,
	["float"] = true,
})
hl.window_rule({ ["name"] = "lua:windowrules:57", ["match"] = { ["class"] = "^(chromium)$" }, ["opacity"] = "0.90 0.90" })
hl.window_rule({
	["name"] = "lua:windowrules:61",
	["match"] = { ["class"] = "^(com\\.github\\.jeromerobert\\.pdfarranger)$" },
	["opacity"] = "0.80 0.80",
})
hl.window_rule({
	["name"] = "swappy",
	["match"] = { ["class"] = "^(swappy)$" },
	["opacity"] = "0.80 0.80",
	["float"] = true,
	["center"] = true,
})
hl.window_rule({
	["name"] = "lua:windowrules:65",
	["match"] = { ["class"] = "^(org\\.kde\\.gwenview)$", ["modal"] = false },
	["fullscreen"] = true,
})
hl.window_rule({
	["name"] = "lua:windowrules:66",
	["match"] = {
		["class"] = "^([Ll]ibreoffice(-writer|-calc|-impress|-draw|-base|-math|-startcenter)?)$",
		["modal"] = false,
	},
	["workspace"] = "empty",
})
hl.window_rule({ ["name"] = "lua:windowrules:67", ["match"] = { ["class"] = "^(qalculate-gtk)$" }, ["float"] = true })
hl.window_rule({
	["name"] = "qbittorrent-child-float",
	["match"] = { ["class"] = "^(org\\.qbittorrent\\.qBittorrent)$", ["initial_title"] = "negative:^(qBittorrent.*)?$" },
	["float"] = true,
	["center"] = true,
})
hl.window_rule({
	["name"] = "xdg-desktop-portal-gtk",
	["match"] = { ["class"] = "^(xdg-desktop-portal-gtk)$" },
	["float"] = true,
	["center"] = true,
})
hl.window_rule({
	["name"] = "hyprland-share-picker",
	["match"] = { ["class"] = "^(hyprland-share-picker)$" },
	["float"] = true,
	["center"] = true,
})
hl.window_rule({ ["name"] = "localsend", ["match"] = { ["class"] = "^(localsend)$" }, ["float"] = true, ["center"] = true })
hl.window_rule({
	["name"] = "lua:windowrules:97",
	["match"] = { ["class"] = "^(org\\.kde\\.keditfiletype)$" },
	["float"] = true,
})
hl.layer_rule({ ["name"] = "lua:windowrules:105", ["match"] = { ["namespace"] = "rofi" }, ["blur"] = true })
hl.layer_rule({ ["name"] = "lua:windowrules:106", ["match"] = { ["namespace"] = "rofi" }, ["ignore_alpha"] = 0 })
hl.layer_rule({ ["name"] = "lua:windowrules:107", ["match"] = { ["namespace"] = "notifications" }, ["blur"] = true })
hl.layer_rule({ ["name"] = "lua:windowrules:108", ["match"] = { ["namespace"] = "notifications" }, ["ignore_alpha"] = 0 })
hl.layer_rule({ ["name"] = "lua:windowrules:109", ["match"] = { ["namespace"] = "logout_dialog" }, ["blur"] = true })
hl.layer_rule({
	["name"] = "bitwarden-popup-private",
	["match"] = { ["namespace"] = "hypr-shell-bitwarden" },
	["no_screen_share"] = true,
})
hl.window_rule({
	["name"] = "tui-float",
	["match"] = { ["class"] = "^(org\\.tui\\..*|org\\.font\\..*|lazygit|lazydocker)$" },
	["float"] = true,
	["center"] = true,
})
hl.window_rule({
	["name"] = "lockview",
	["match"] = { ["class"] = "^(org\\.quickshell)$", ["title"] = "^(Lock Layouts)$" },
	["float"] = true,
	["opacity"] = "1 override 1 override",
})
