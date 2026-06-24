-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("ANIMATION", "optimized")
local animation_path = vars.get("XDG_DATA_HOME") .. "/hypr/animations/optimized.lua"
vars.set("ANIMATION_PATH", animation_path)
runtime.load(animation_path)
