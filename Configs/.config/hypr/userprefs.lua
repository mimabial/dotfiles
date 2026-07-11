hl.on("hyprland.start", function()
    hl.exec_cmd(os.getenv("HOME") .. "/.local/lib/hypr/media/fftab-bridge/ensure.sh")
end)

hl.config({
    input = {
        kb_layout = "us,fr",
        kb_variant = ",",
        kb_options = "grp:alt_shift_toggle",
        resolve_binds_by_sym = true,
        touchpad = {natural_scroll = false},
    },
    misc = {
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },
})
