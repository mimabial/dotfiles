hl.workspace_rule({ workspace = "n[s:macspace_]", layout = "dwindle", gaps_in = 0, gaps_out = 0, no_border = true })

hl.on("window.close", function(window)
    local workspace = window and window.workspace
    if not workspace or not workspace.name:match("^macspace_") then return end
    local survivor, count = nil, 0
    for _, candidate in ipairs(hl.get_windows({ workspace = workspace, mapped = true })) do
        if candidate.address ~= window.address then
            survivor, count = candidate, count + 1
        end
    end
    if count == 1 then
        hl.dispatch(hl.dsp.window.fullscreen({ window = survivor, mode = "fullscreen", action = "set" }))
    end
end)
