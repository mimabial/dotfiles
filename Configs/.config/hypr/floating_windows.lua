local M = {}

local function eligible(window)
    return window.workspace and window.workspace.id > 0 and not window.pinned and not window.hidden
        and window.fullscreen == 0
end

local function place(window, x, y, width, height)
    local selector = "address:" .. window.address
    width, height = math.max(1, math.floor(width)), math.max(1, math.floor(height))
    x, y = math.floor(x), math.floor(y)
    if not window.floating then hl.dispatch(hl.dsp.window.float({window = selector, action = "on"})) end
    local grow_x, grow_y = width - window.size.x, height - window.size.y
    if grow_x ~= 0 or grow_y ~= 0 then
        local centred_x, centred_y = x + math.ceil(grow_x / 2), y + math.ceil(grow_y / 2)
        hl.dispatch(hl.dsp.window.move({window = selector, x = centred_x, y = centred_y, relative = false}))
        hl.dispatch(hl.dsp.window.resize({window = selector, x = width, y = height, relative = false}))
    end
    if window.at.x ~= x or window.at.y ~= y then
        hl.dispatch(hl.dsp.window.move({window = selector, x = x, y = y, relative = false}))
    end
end

function M.snap(address, placement)
    local window = hl.get_window("address:" .. address)
    if not window then return end
    local selector = "address:" .. address
    if placement == "maximize" then
        hl.dispatch(hl.dsp.window.fullscreen({window = selector, mode = "maximized", action = "set"}))
        return
    end
    if window.fullscreen ~= 0 then
        local mode = window.fullscreen == 1 and "maximized" or "fullscreen"
        hl.dispatch(hl.dsp.window.fullscreen({window = selector, mode = mode, action = "unset"}))
    end
    if placement == "tile" then
        hl.dispatch(hl.dsp.window.float({window = selector, action = "unset"}))
        return
    end
    local monitor = window.monitor
    local width, height = monitor.width / monitor.scale, monitor.height / monitor.scale
    if monitor.transform % 2 == 1 then width, height = height, width end
    local reserved, outer = monitor.reserved, hl.get_config("general.gaps_out")
    local inner, border = hl.get_config("general.gaps_in"), hl.get_config("general.border_size")
    local x = monitor.x + reserved.left + outer.left + border
    local y = monitor.y + reserved.top + outer.top + border
    width = width - reserved.left - reserved.right - outer.left - outer.right - 2 * border
    height = height - reserved.top - reserved.bottom - outer.top - outer.bottom - 2 * border
    if placement == "center" then
        local centered_width, centered_height = math.min(window.size.x, width), math.min(window.size.y, height)
        place(window, x + (width - centered_width) / 2, y + (height - centered_height) / 2, centered_width, centered_height)
        return
    end
    local columns = (placement == "top" or placement == "bottom") and 1 or 2
    local rows = (placement == "left" or placement == "right") and 1 or 2
    local cell_width = (width - (columns - 1) * (inner.left + inner.right + 2 * border)) / columns
    local cell_height = (height - (rows - 1) * (inner.top + inner.bottom + 2 * border)) / rows
    if placement:find("right", 1, true) then x = x + width - cell_width end
    if placement:find("bottom", 1, true) then y = y + height - cell_height end
    place(window, x, y, cell_width, cell_height)
end

function M.restore(previous)
    for _, window in ipairs(hl.get_windows({mapped = true})) do
        if eligible(window) then
            local saved = previous[window.address]
            if saved and saved.floating then
                place(window, saved.x, saved.y, saved.width, saved.height)
            elseif window.floating then
                hl.dispatch(hl.dsp.window.float({window = "address:" .. window.address, action = "off"}))
            end
        end
    end
    return "ok"
end

return M
