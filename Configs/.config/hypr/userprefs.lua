hl.env("HYPR_PROFILE_WORKFLOW_LOCK", "1")

hl.config({
    input = {
        kb_layout = "us,fr",
        kb_variant = ",",
        kb_options = "",
        resolve_binds_by_sym = true,
        touchpad = {natural_scroll = false},
    },
    misc = {
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },
    decoration = {
        blur = {popups = true},
    },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("hyprshell gaming/gamemode-hook reconcile")
    hl.exec_cmd("hyprshell system/start-if-vpn.sh --timeout 90 --workspace 10 -- qbittorrent")
end)
