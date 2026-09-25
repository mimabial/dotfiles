-- Reads a chunk of Hyprland Lua config by running it against recording stubs
-- and reporting what it set. Lua reading Lua, so there is no second grammar to
-- keep in sync with Hyprland's, and a hand-edit that breaks the syntax gets a
-- real error instead of being silently misread.
--
--   lua looknfeel-read.lua <path>       run a file
--   lua looknfeel-read.lua -e <source>  run a string
--
-- Output is one tab-separated record per line:
--
--   k  <key:path>  <type>  <value>                     a config setting
--   v  <name>  <type>  <value>                         a theme variable
--   a  <leaf>  <enabled>  <speed>  <bezier>  <style>   an animation leaf
--
-- Nothing is applied: every stub only records. Exits non-zero with the Lua
-- error on stderr if the chunk does not load or run.

local output_records = {}

local function sanitize_field(value)
    return (tostring(value):gsub("\t", " "):gsub("\n", " "))
end

local function emit_record(...)
    local fields = {}
    for index, value in ipairs({ ... }) do fields[index] = sanitize_field(value) end
    output_records[#output_records + 1] = table.concat(fields, "\t")
end

local function emit_config_entries(config, prefix)
    for key, value in pairs(config) do
        local path = prefix == "" and tostring(key) or (prefix .. ":" .. tostring(key))
        if type(value) == "table" then
            emit_config_entries(value, path)
        else
            emit_record("k", path, type(value), value)
        end
    end
end

local function noop() end

hl = {
    config = function(config) emit_config_entries(config, "") end,
    animation = function(animation)
        emit_record("a", animation.leaf or "", animation.enabled ~= false, animation.speed or "",
            animation.bezier or "", animation.style or "")
    end,
    curve = noop,
    window_rule = noop,
    layer_rule = noop,
    bind = noop,
    unbind = noop,
    monitor = noop,
    on = noop,
    env = noop,
    get_config = function() return nil, nil end,
}

local run_file

-- Config files here are not free-standing: they require("runtime") and
-- require("vars"). Shimming require is cheaper and safer than pointing LUA_PATH
-- at the real modules, and following runtime.load is what lets a read of
-- animations.lua reach the preset it chains to.
local stubs = {
    runtime = {
        config = function(path, value)
            emit_record("k", (tostring(path):gsub("%.", ":")), type(value), value)
        end,
        load = function(path) run_file(path, true) end,
    },
    vars = {
        set = function(name, value)
            emit_record("v", name, type(value), value)
        end,
        get = function(_, fallback) return fallback or "" end,
    },
}

local real_require = require
require = function(name)
    return stubs[name] or real_require(name)
end

local function run_chunk(source, name)
    local chunk, load_error = load(source, name, "t")
    if not chunk then
        io.stderr:write(tostring(load_error))
        os.exit(1)
    end
    local ok, execution_error = pcall(chunk)
    if not ok then
        io.stderr:write(tostring(execution_error))
        os.exit(1)
    end
end

run_file = function(path, optional)
    local file = io.open(path, "r")
    if not file then
        if optional then return end
        io.stderr:write("cannot open " .. tostring(path))
        os.exit(1)
    end
    local source = file:read("a")
    file:close()
    run_chunk(source, path)
end

if arg[1] == "-e" then
    run_chunk(arg[2] or "", "looknfeel-block")
else
    run_file(arg[1], false)
end

print(table.concat(output_records, "\n"))
