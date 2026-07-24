local M = {
    overlay = {width = "25%", height = "25%", basis = "monitor"},
    compact = {width = "50%", height = "70%", basis = "usable"},
    standard = {width = "70%", height = "80%", basis = "usable"},
    large = {width = "80%", height = "90%", basis = "usable"},
}

function M.rule_size(name)
    local profile = assert(M[name], "unknown window profile: " .. tostring(name))
    assert(profile.basis == "monitor", "window rules only support monitor-based profiles")
    return profile.width .. " " .. profile.height
end

return M
