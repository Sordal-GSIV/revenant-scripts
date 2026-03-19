--- Combat event processor.
--- State machine that processes chunks of game text into creature state updates.

local parser = require("lib/gs/combat/parser")
local creature_instance = require("lib/gs/combat/creature_instance")
local M = {}

-- Body part mapping from critranks location strings
local LOCATION_MAP = {
    leftarm = "leftArm", larm = "leftArm",
    rightarm = "rightArm", rarm = "rightArm",
    leftleg = "leftLeg", lleg = "leftLeg",
    rightleg = "rightLeg", rleg = "rightLeg",
    lefthand = "leftHand", lhand = "leftHand",
    righthand = "rightHand", rhand = "rightHand",
    leftfoot = "leftFoot", lfoot = "leftFoot",
    rightfoot = "rightFoot", rfoot = "rightFoot",
    lefteye = "leftEye", leye = "leftEye",
    righteye = "rightEye", reye = "rightEye",
    head = "head", neck = "neck", chest = "chest",
    abdomen = "abdomen", abs = "abdomen",
    back = "back", nerves = "nsys",
}

--- Map a critranks location string to a BODY_PARTS key.
---@param location string|nil
---@return string|nil
function M.map_location(location)
    if not location then return nil end
    return LOCATION_MAP[location:lower()] or location
end

--- Process a chunk of game text lines (main entry point called by the tracker).
---@param lines string[]
function M.process(lines)
    local events = M.parse_events(lines)
    for _, event in ipairs(events) do
        M.persist_event(event)
    end
end

--- State machine parser — extract combat events from a sequence of lines.
---@param lines string[]
---@return table[] array of event tables
function M.parse_events(lines)
    local events = {}
    local state = "seeking_attack"
    local current_event = nil
    local current_target = nil

    for _, line in ipairs(lines) do
        -- Global: always check for status effects
        local status = parser.parse_status(line)
        if status then
            -- Find target for this status event
            if status.target then
                -- Try to find a creature with this name
                local all = creature_instance.all()
                for _, c in ipairs(all) do
                    if c.name and string.find(c.name, status.target, 1, true) then
                        if status.action == "add" then
                            creature_instance.add_status(c.id, status.status)
                        else
                            creature_instance.remove_status(c.id, status.status)
                        end
                        break
                    end
                end
            elseif current_target then
                -- Apply to current target
                if status.action == "add" then
                    creature_instance.add_status(current_target.id, status.status)
                else
                    creature_instance.remove_status(current_target.id, status.status)
                end
            end
        end

        -- Global: check for UCS events
        local ucs = parser.parse_ucs(line)
        if ucs then
            local target_id = ucs.target_id or (current_target and current_target.id)
            if target_id then
                if ucs.type == "position" then
                    creature_instance.set_ucs_position(target_id, ucs.value)
                elseif ucs.type == "tierup" then
                    creature_instance.set_ucs_tierup(target_id, ucs.value)
                elseif ucs.type == "smite_on" then
                    creature_instance.smite(target_id)
                elseif ucs.type == "smite_off" then
                    -- just clear it (smote TTL handles expiry)
                end
            end
        end

        -- Extract target from this line
        local line_target = parser.extract_target(line)
        if line_target and line_target.id then
            -- Register creature if new
            creature_instance.register(line_target.id, line_target.name, line_target.noun)

            -- Check for target switch
            if current_target and current_target.id ~= line_target.id then
                -- Save current event
                if current_event and current_target.id and
                   (#current_event.damages > 0 or #current_event.statuses > 0) then
                    events[#events + 1] = current_event
                end
                current_event = nil
            end
            current_target = line_target
        end

        if state == "seeking_attack" then
            local attack = parser.parse_attack(line)
            if attack then
                -- Save previous event
                if current_event and current_event.target and current_event.target.id and
                   (#current_event.damages > 0 or #current_event.statuses > 0) then
                    events[#events + 1] = current_event
                end
                current_event = {
                    name = attack.name,
                    target = attack.target or current_target,
                    damages = {},
                    statuses = {},
                }
                state = "seeking_damage"
            end

        elseif state == "seeking_damage" then
            -- Check for damage
            local damage = parser.parse_damage(line)
            if damage then
                if current_event then
                    current_event.damages[#current_event.damages + 1] = damage
                end
            end

            -- Check for new attack (reset state)
            local attack = parser.parse_attack(line)
            if attack then
                -- Save current event
                if current_event and current_event.target and current_event.target.id and
                   (#current_event.damages > 0 or #current_event.statuses > 0) then
                    events[#events + 1] = current_event
                end
                current_event = {
                    name = attack.name,
                    target = attack.target or current_target,
                    damages = {},
                    statuses = {},
                }
            end
        end
    end

    -- Save final event
    if current_event and current_event.target and current_event.target.id and
       (#current_event.damages > 0 or #current_event.statuses > 0) then
        events[#events + 1] = current_event
    end

    return events
end

--- Apply a parsed event to creature instances.
---@param event table { name, target, damages, statuses }
function M.persist_event(event)
    if not event.target or not event.target.id then return end
    local id = event.target.id

    -- Ensure creature is registered
    creature_instance.register(id, event.target.name, event.target.noun)

    -- Apply damages
    for _, dmg in ipairs(event.damages) do
        creature_instance.add_damage(id, dmg)
    end

    -- Apply statuses
    for _, status_name in ipairs(event.statuses) do
        creature_instance.add_status(id, status_name)
    end
end

return M
