local vars = require("vars")
local M = {}
local moved = {}

local function active()
    local workflow, layout = vars.get("WORKFLOW"), vars.get("WORKFLOW_LAYOUT_OVERRIDE", "")
    return workflow == "floating" or workflow == "windows" and layout == "floating"
end

local function eligible(window)
    return window.workspace and window.workspace.id > 0 and not window.pinned and not window.hidden
        and window.fullscreen == 0
end

local function usable_area(monitor)
    local gaps, border = hl.get_config("general.gaps_out"), hl.get_config("general.border_size")
    local width, height = monitor.size.width / monitor.scale, monitor.size.height / monitor.scale
    if monitor.transform % 2 == 1 then width, height = height, width end
    local left = monitor.reserved.left + gaps.left + border
    local top = monitor.reserved.top + gaps.top + border
    return {
        x = math.ceil(monitor.position.x + left), y = math.ceil(monitor.position.y + top),
        width = math.floor(width - left - monitor.reserved.right - gaps.right - border),
        height = math.floor(height - top - monitor.reserved.bottom - gaps.bottom - border),
    }
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

local function float_tiled_windows()
    if not active() then return end
    for _, window in ipairs(hl.get_windows({mapped = true})) do
        if eligible(window) and not window.floating then
            local area = usable_area(window.workspace.monitor)
            hl.dispatch(hl.dsp.window.float({window = "address:" .. window.address, action = "on"}))
            local width, height = math.min(area.width, window.size.x), math.min(area.height, window.size.y)
            local x = math.max(area.x, math.min(window.at.x, area.x + area.width - width))
            local y = math.max(area.y, math.min(window.at.y, area.y + area.height - height))
            place(window, x, y, width, height)
        end
    end
end

function M.restore(previous, floating_workflow)
    for _, window in ipairs(hl.get_windows({mapped = true})) do
        if eligible(window) then
            local saved = previous[window.address]
            if saved and saved.floating then
                place(window, saved.x, saved.y, saved.width, saved.height)
            elseif window.floating and not floating_workflow then
                hl.dispatch(hl.dsp.window.float({window = "address:" .. window.address, action = "off"}))
            end
        end
    end
    return "ok"
end

function M.setup()
    hl.on("window.open_early", function(window)
        if active() and eligible(window) then hl.dispatch(hl.dsp.window.float({window = "address:" .. window.address, action = "on"})) end
    end)
    for _, event in ipairs({"window.open", "window.fullscreen", "config.reloaded"}) do
        hl.on(event, float_tiled_windows)
    end
    hl.on("window.move_to_workspace", function(window) moved[window.address] = true end)
    hl.on("window.update_rules", function(window)
        if not moved[window.address] then return end
        moved[window.address] = nil
        float_tiled_windows()
    end)
    hl.on("window.close", function(window) moved[window.address] = nil end)
end

return M
