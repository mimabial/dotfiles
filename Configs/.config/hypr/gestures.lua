local workspace_axis = require("vars").get("WORKSPACE_SWIPE_AXIS", "horizontal")
local expose_namespace = "expose-window-overview"
local expose_layers = #hl.get_layers({namespace = expose_namespace})
local workspace_swipe_enabled

local function set_workspace_swipe(action)
    hl.gesture({fingers = 3, direction = workspace_axis, action = action})
end

local function sync_workspace_swipe()
    local enabled = expose_layers == 0
    if enabled == workspace_swipe_enabled then return end
    if workspace_swipe_enabled ~= nil then set_workspace_swipe("unset") end
    workspace_swipe_enabled = enabled
    set_workspace_swipe(enabled and "workspace" or function() end)
end

local function count_expose_layers_and_sync_swipe(step)
    return function(layer)
        if layer.namespace ~= expose_namespace then return end
        expose_layers = math.max(0, expose_layers + step)
        sync_workspace_swipe()
    end
end

hl.on("layer.opened", count_expose_layers_and_sync_swipe(1))
hl.on("layer.closed", count_expose_layers_and_sync_swipe(-1))
sync_workspace_swipe()
if workspace_axis == "vertical" then
    hl.gesture({fingers = 3, direction = "horizontal", action = "scroll_move"})
else
    hl.gesture({fingers = 3, direction = "up", action = function() hl.dispatch(hl.dsp.event("expose.window-overview:toggle")) end})
end
hl.gesture({fingers = 4, direction = "pinch", action = "fullscreen"})
