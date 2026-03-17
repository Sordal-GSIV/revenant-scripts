--- Room ownership tracking.
--- Pure Lua module for claiming rooms and checking occupancy.

local M = {}
local claimed_room = nil

--- Claim a room by ID (defaults to current room).
function M.claim_room(id)
    claimed_room = id or GameState.room_id
end

--- Return the claimed room ID, or nil.
function M.claimed_room_id()
    return claimed_room
end

--- True if current room is the claimed room.
function M.mine()
    return GameState.room_id == claimed_room
end

--- Return PCs in the room who are not in group and not self.
function M.others()
    local pcs = GameObj.pcs()
    local group = {}
    for _, name in ipairs(Group.members()) do
        group[name] = true
    end
    group[GameState.name] = true

    local result = {}
    for _, pc in ipairs(pcs) do
        if not group[pc.name] then
            result[#result + 1] = pc
        end
    end
    return result
end

--- Clear the claimed room.
function M.clear()
    claimed_room = nil
end

--- Respond with formatted claim status.
function M.info()
    if not claimed_room then
        respond("Claim: no room claimed")
        return
    end
    local status = M.mine() and "you are here" or "you are elsewhere"
    respond("Claim: room " .. tostring(claimed_room) .. " (" .. status .. ")")
    local others = M.others()
    if #others > 0 then
        local names = {}
        for _, pc in ipairs(others) do
            names[#names + 1] = pc.name
        end
        respond("  Others present: " .. table.concat(names, ", "))
    end
end

return M
