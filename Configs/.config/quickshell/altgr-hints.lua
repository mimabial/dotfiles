return function(codes, owner, caps_lock)
    local previous = rawget(_G, "__altgr_hints")
    if previous then previous.subscription:remove() end
    local held = {}
    for _, code in pairs(codes) do held[code] = hl.is_key_down(code) end
    local last_level
    local function publish()
        local shift = held[codes.leftShift] or held[codes.rightShift]
        local level = held[codes.altgr] and (1 + (shift and 1 or 0) + (caps_lock and 2 or 0)) or 0
        if level == last_level then return end
        last_level = level
        hl.dispatch(hl.dsp.event("altgr-hints>>" .. level))
    end
    local subscription = hl.on("input.keyboard.key", function(code, _, state)
        if held[code] == nil or state == 2 then return end
        local pressed = state == 1
        if code == codes.caps and pressed and not held[code] then caps_lock = not caps_lock end
        held[code] = pressed
        publish()
    end)
    _G.__altgr_hints = {subscription = subscription, owner = owner}
    publish()
end
