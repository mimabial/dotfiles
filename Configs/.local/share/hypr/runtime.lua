local M = {}
local SKIPPED_LAYER_NOTICE_MS = 10000

local function nested(path, value)
    local root = {}
    local cursor = root
    local parts = {}
    for part in path:gmatch("[^.]+") do
        parts[#parts + 1] = part
    end
    for index = 1, #parts - 1 do
        cursor[parts[index]] = {}
        cursor = cursor[parts[index]]
    end
    cursor[parts[#parts]] = value
    return root
end

function M.config_if_supported(path, value)
    local _, err = hl.get_config(path)
    if err == nil then
        hl.config(nested(path, value))
    end
end

function M.load(path, optional)
    local file, missing = io.open(path)
    if not file then
        if optional then
            return nil
        end
        error(missing)
    end
    local source = file:read("a")
    file:close()
    local function run()
        local chunk, syntax_error = load(source, "@" .. path)
        if not chunk then
            error(syntax_error, 0)
        end
        chunk()
    end
    if not optional then
        run()
        return true
    end
    local loaded, err = pcall(run)
    if not loaded then
        hl.notification.create({text = err, timeout = SKIPPED_LAYER_NOTICE_MS})
    end
    return loaded or nil
end

return M
