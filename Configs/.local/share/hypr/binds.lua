local actions = {}
_G.HYPR_BIND_ACTIONS = actions

local stale_hint_cache = require("vars").get("XDG_RUNTIME_DIR") .. "/hypr/keybinds_hint.rofi"
os.remove(stale_hint_cache)

local function chord(modifiers, key)
    local parts = {}
    for item in tostring(modifiers or ""):gsub("%+", " "):gmatch("%S+") do
        parts[#parts + 1] = item
    end
    parts[#parts + 1] = key
    return table.concat(parts, " + ")
end

local function bind(modifiers, key, description, dispatcher, options)
    options = options or {}
    options.description = description
    actions[description] = dispatcher
    hl.bind(chord(modifiers, key), dispatcher, options)
end

local function exec(modifiers, key, description, command, options)
    bind(modifiers, key, description, hl.dsp.exec_cmd(command), options)
end

return {actions = actions, chord = chord, bind = bind, exec = exec}
