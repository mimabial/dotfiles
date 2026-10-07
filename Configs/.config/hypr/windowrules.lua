local window_profiles = require("window_profiles")

hl.window_rule({
	["name"] = "video-idle-inhibit",
	["match"] = { ["class"] = "^(.*(haruna|firefox|chromium).*)$" },
	["idle_inhibit"] = "fullscreen",
})
hl.window_rule({ ["name"] = "center-new-floating-windows", ["match"] = { ["float"] = true }, ["center"] = true })
hl.window_rule({
	["name"] = "tag-picture-in-picture",
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
	["name"] = "haruna-fullscreen",
	["match"] = { ["class"] = "^(org\\.kde\\.haruna)$", ["initial_title"] = "^Haruna$" },
	["fullscreen"] = true,
})
hl.window_rule({
	["name"] = "float-apps",
	["match"] = { ["class"] = "^(org\\.kde\\.haruna|qalculate-gtk|org\\.kde\\.keditfiletype)$" },
	["float"] = true,
})
hl.window_rule({
	["name"] = "firefox-opacity",
	["match"] = { ["class"] = "^(firefox)$" },
	["opacity"] = "0.90 override 0.90 override 1",
})
hl.window_rule({
	["name"] = "translucent-apps",
	["match"] = {
		["class"] = "^(kitty|org\\.tui\\..*|Alacritty|org\\.kde\\.dolphin|org\\.qbittorrent\\.qBittorrent|nwg-look)$",
	},
	["opacity"] = "0.80 override 0.80 override 1",
})
hl.window_rule({
	["name"] = "ark",
	["match"] = { ["class"] = "^(org\\.kde\\.ark)$" },
	["opacity"] = "0.80 override 0.80 override 1",
	["float"] = true,
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
	["name"] = "translucent-dialogs",
	["match"] = {
		["class"] = "^(nm-connection-editor|org\\.kde\\.polkit-kde-authentication-agent-1|polkit-gnome-authentication-agent-1|org\\.freedesktop\\.impl\\.portal\\.desktop\\.(gtk|hyprland))$",
	},
	["opacity"] = "0.80 override 0.70 override 1",
})
hl.window_rule({
	["name"] = "gimp-fullscreen",
	["match"] = { ["class"] = "^(gimp)$", ["initial_title"] = "^GNU Image Manipulation Program$" },
	["fullscreen"] = true,
})
hl.window_rule({
	["name"] = "translucent-apps-relative",
	["match"] = { ["class"] = "^(signal|org\\.pwmt\\.zathura|com\\.github\\.jeromerobert\\.pdfarranger)$" },
	["opacity"] = "0.80 0.80",
})
hl.window_rule({
	["name"] = "bitwarden",
	["match"] = { ["class"] = "^([Bb]itwarden)$" },
	["opacity"] = "0.80 0.80",
	["no_screen_share"] = true,
	["float"] = true,
})
hl.window_rule({ ["name"] = "chromium-opacity", ["match"] = { ["class"] = "^(chromium)$" }, ["opacity"] = "0.90 0.90" })
hl.window_rule({
	["name"] = "swappy",
	["match"] = { ["class"] = "^(swappy)$" },
	["opacity"] = "0.80 0.80",
	["float"] = true,
	["center"] = true,
})
hl.window_rule({
	["name"] = "gwenview-fullscreen",
	["match"] = { ["class"] = "^(org\\.kde\\.gwenview)$", ["modal"] = false },
	["fullscreen"] = true,
})
hl.window_rule({
	["name"] = "libreoffice-empty-workspace",
	["match"] = {
		["class"] = "^([Ll]ibreoffice(-writer|-calc|-impress|-draw|-base|-math|-startcenter)?)$",
		["modal"] = false,
	},
	["workspace"] = "empty",
})
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
hl.layer_rule({
	["name"] = "blur-overlays",
	["match"] = { ["namespace"] = "^(rofi|notifications)$" },
	["blur"] = true,
	["ignore_alpha"] = 0,
})
hl.layer_rule({ ["name"] = "blur-session-menu", ["match"] = { ["namespace"] = "^(hypr-shell-session)$" }, ["blur"] = true })
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
