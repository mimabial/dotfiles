local PARK_SLOTS_EVENT = "dock-slots>>"
local ROOT_TURNS = { "togglesplit", "swapsplit", "togglesplit" }

local function tiled_slots(workspace)
	local slots = {}
	for _, window in ipairs(workspace:get_windows()) do
		if not window.floating then
			slots[window.address] = string.format("%.0f,%.0f,%.0f,%.0f", window.at.x, window.at.y, window.size.x, window.size.y)
		end
	end
	return slots
end

local function slot_bounds(slot)
	local x, y, width, height = slot:match("^(-?%d+),(-?%d+),(%d+),(%d+)$")
	return tonumber(x), tonumber(y), tonumber(width), tonumber(height)
end

local function spans_group(slots, address)
	local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
	for _, slot in pairs(slots) do
		local x, y, width, height = slot_bounds(slot)
		left, top = math.min(left, x), math.min(top, y)
		right, bottom = math.max(right, x + width), math.max(bottom, y + height)
	end
	local _, _, width, height = slot_bounds(slots[address])
	return width == right - left or height == bottom - top
end

local function sibling_split_child(workspace, address)
	local siblings, count = tiled_slots(workspace), 0
	siblings[address] = nil
	for _ in pairs(siblings) do
		count = count + 1
	end
	if count < 2 then
		return nil
	end
	for sibling in pairs(siblings) do
		if spans_group(siblings, sibling) then
			return sibling
		end
	end
	return nil
end

local function slot_swaps(record, workspace)
	local owner_of, occupant, slot_of = {}, {}, {}
	for owner, slot in pairs(record) do
		if owner_of[slot] then
			return nil
		end
		owner_of[slot] = owner
	end
	for current, slot in pairs(tiled_slots(workspace)) do
		if occupant[slot] or not owner_of[slot] or not record[current] then
			return nil
		end
		occupant[slot], slot_of[current] = current, slot
	end
	for owner in pairs(record) do
		if not slot_of[owner] then
			return nil
		end
	end
	local swaps = {}
	for slot, owner in pairs(owner_of) do
		local current = occupant[slot]
		if current ~= owner then
			local vacated = slot_of[owner]
			swaps[#swaps + 1] = { current, owner }
			occupant[slot], occupant[vacated] = owner, current
			slot_of[owner], slot_of[current] = slot, vacated
		end
	end
	return swaps
end

local function focus(address)
	hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
end

local function without_warps(action)
	local warps = hl.get_config("cursor.no_warps")
	hl.config({ cursor = { no_warps = true } })
	action()
	hl.config({ cursor = { no_warps = warps } })
end

local function focus_in_place(address)
	without_warps(function()
		focus(address)
	end)
end

local function regrow_dwindle_root(address, record, workspace)
	local swaps
	without_warps(function()
		focus(address)
		hl.dispatch(hl.dsp.layout("movetoroot"))
		local sibling = sibling_split_child(workspace, address)
		for _, flip_sibling in ipairs(sibling and { false, true } or { false }) do
			if flip_sibling then
				focus(sibling)
				hl.dispatch(hl.dsp.layout("togglesplit"))
				focus(address)
			end
			swaps = slot_swaps(record, workspace)
			for _, turn in ipairs(ROOT_TURNS) do
				if swaps then
					break
				end
				hl.dispatch(hl.dsp.layout(turn))
				swaps = slot_swaps(record, workspace)
			end
			if swaps then
				break
			end
		end
	end)
	return swaps
end

local function move(address, workspace)
	hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, workspace = workspace, follow = false }))
end

local function park(address, parking)
	local window = hl.get_window("address:" .. address)
	if window and window.workspace and window.workspace.visible and not window.floating then
		local fields = { address }
		for owner, slot in pairs(tiled_slots(window.workspace)) do
			fields[#fields + 1] = owner .. "=" .. slot
		end
		hl.dispatch(hl.dsp.event(PARK_SLOTS_EVENT .. table.concat(fields, " ")))
	end
	move(address, parking)
end

local function restore(address, workspace, record)
	move(address, workspace)
	local window = hl.get_window("address:" .. address)
	if not (record and record[address] and window and window.workspace and window.workspace.visible) then
		return
	end
	local swaps = slot_swaps(record, window.workspace)
	if not swaps and window.workspace.tiled_layout == "dwindle" and spans_group(record, address) then
		swaps = regrow_dwindle_root(address, record, window.workspace)
	end
	for _, swap in ipairs(swaps or {}) do
		hl.dispatch(hl.dsp.window.swap({ window = "address:" .. swap[1], target = "address:" .. swap[2] }))
	end
end

return { park = park, restore = restore, focus_in_place = focus_in_place }
