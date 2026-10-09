local workspace_axis = require("vars").get("WORKSPACE_SWIPE_AXIS", "horizontal")

hl.gesture({fingers = 3, direction = workspace_axis, action = "workspace"})
if workspace_axis == "vertical" then
    hl.gesture({fingers = 3, direction = "horizontal", action = "scroll_move"})
else
    hl.gesture({fingers = 3, direction = "up", action = function() hl.dispatch(hl.dsp.event("expose.window-overview:toggle")) end})
end
hl.gesture({fingers = 4, direction = "pinch", action = "fullscreen"})
