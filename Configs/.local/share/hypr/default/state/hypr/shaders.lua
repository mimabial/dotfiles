-- Generated native Hyprland Lua. Do not edit manually.
local runtime = require("runtime")
local vars = require("vars")

vars.set("SCREEN_SHADER", "neutral")
vars.set("SCREEN_SHADER_PATH", vars.get("XDG_DATA_HOME") .. "/hypr/shaders/neutral.frag")
local compiled_path = vars.get("XDG_CACHE_HOME") .. "/hypr/shaders/compiled.cache.glsl"
vars.set("SCREEN_SHADER_COMPILED", compiled_path)
runtime.config("decoration.screen_shader", compiled_path)
