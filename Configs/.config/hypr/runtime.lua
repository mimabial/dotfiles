local M = {}

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

function M.config(path, value)
    local _, err = hl.get_config(path)
    if err == nil then
        hl.config(nested(path, value))
    end
end

function M.load(path, optional)
    local chunk, err = loadfile(path)
    if not chunk then
        if optional then
            return nil
        end
        error(err)
    end
    return chunk()
end

return M
