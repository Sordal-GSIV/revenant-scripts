--- Combat event parser.
--- Extracts attack, damage, status, and UCS events from game text lines.

local defs = require("lib/gs/combat/defs")
local M = {}

--- Extract creature target from bold-wrapped link in a line.
--- Returns { id = "123", noun = "troll", name = "a large troll" } or nil.
---@param line string
---@return table|nil
function M.extract_target(line)
    -- Must be bold-wrapped (NPCs are bold, objects are not)
    if not string.find(line, "pushBold", 1, true) then return nil end
    local caps = defs.TARGET_LINK:captures(line)
    if caps then
        return { id = caps[1], noun = caps[2], name = caps[3] }
    end
    return nil
end

--- Parse attack from line.
--- Returns { name = "attack", target = target_table } or nil.
---@param line string
---@return table|nil
function M.parse_attack(line)
    for _, atk in ipairs(defs.ATTACKS) do
        for _, pat in ipairs(atk.patterns) do
            if pat:test(line) then
                local target = M.extract_target(line)
                return { name = atk.name, target = target }
            end
        end
    end
    return nil
end

--- Parse damage from line.
--- Returns integer damage amount or nil.
---@param line string
---@return number|nil
function M.parse_damage(line)
    for _, pat in ipairs(defs.DAMAGE_PATTERNS) do
        local caps = pat:captures(line)
        if caps and caps[1] then
            return tonumber(caps[1])
        end
    end
    return nil
end

--- Parse status effect from line.
--- Returns { status = "stunned", action = "add"|"remove", target = "creature name" } or nil.
---@param line string
---@return table|nil
function M.parse_status(line)
    for _, sdef in ipairs(defs.STATUS_ADD) do
        for _, pat in ipairs(sdef.patterns) do
            local caps = pat:captures(line)
            if caps then
                return { status = sdef.name, action = "add", target = caps[1] }
            end
        end
    end
    for _, sdef in ipairs(defs.STATUS_REMOVE) do
        for _, pat in ipairs(sdef.patterns) do
            local caps = pat:captures(line)
            if caps then
                return { status = sdef.name, action = "remove", target = caps[1] }
            end
        end
    end
    return nil
end

--- Parse UCS event from line.
--- Returns { type = "position"|"tierup"|"smite_on"|"smite_off", value = ..., target_id = ... } or nil.
---@param line string
---@return table|nil
function M.parse_ucs(line)
    local caps = defs.UCS_POSITION:captures(line)
    if caps then
        -- Extract target ID from the link in the same line
        local target = M.extract_target(line)
        return { type = "position", value = caps[1], target_id = target and target.id }
    end
    caps = defs.UCS_TIERUP:captures(line)
    if caps then
        return { type = "tierup", value = caps[1] }
    end
    if defs.UCS_SMITE_ON:test(line) then
        local target = M.extract_target(line)
        return { type = "smite_on", target_id = target and target.id }
    end
    if defs.UCS_SMITE_OFF:test(line) then
        local target = M.extract_target(line)
        return { type = "smite_off", target_id = target and target.id }
    end
    return nil
end

return M
