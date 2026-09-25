local runtime = require("runtime")
local vars = require("vars")

vars.set("WORKFLOW_ICON", "󰐨")
vars.set("WORKFLOW_DESCRIPTION", "Keep awake with notifications and night light disabled")

runtime.config("decoration.shadow.enabled", 0)
runtime.config("decoration.blur.enabled", 0)
runtime.config("animations.enabled", 0)
hl.window_rule({
	name = "workflow-presentation-opaque",
	match = { class = "(.*)" },
	opacity = "1 override 1 override 1 override",
	opaque = true,
})
