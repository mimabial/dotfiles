local vars = require("vars")

vars.set("WORKFLOW_ICON", "󰖯")
vars.set("WORKFLOW_DESCRIPTION", "Movable, resizable windows with the current bar")
vars.set("WORKFLOW_QUICKSHELL_LAYOUT", "top bottom winbar macos gnome")

require("floating_windows").setup()
