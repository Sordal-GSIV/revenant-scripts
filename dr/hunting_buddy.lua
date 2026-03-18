--- @revenant-script
--- name: hunting_buddy
--- version: 1.0
--- author: elanthia-online
--- game: dr
--- description: Manage hunting sessions with zone navigation, duration/skill-cap tracking, and combat-trainer integration.
--- tags: hunting, combat, training, zones
--- Converted from hunting-buddy.lic
---
--- Usage:
---   ;hunting_buddy
---
--- Requires: common, common-arcana, common-travel, drinfomon, events, spellmonitor, equipmanager
--- Reads hunting_info from YAML settings.

local DRC = require("lib/dr/common")
local DRCA = require("lib/dr/common_arcana")
local DRCT = require("lib/dr/common_travel")
local DRSkill = require("lib/dr/skills")

local settings = get_settings()
local data = get_data("hunting")
local escort_zones = data.escort_zones or {}
local hunting_zones = data.hunting_zones or {}
local stopped_for_bleeding = false
local hunt_exit = nil

--- Check if all stop_on skills have reached their xp cap (>=32)
local function all_skills_at_cap(stop_on_skills)
    if not stop_on_skills then return false end
    for _, skill in ipairs(stop_on_skills) do
        if DRSkill.getxp(skill) < 32 then
            return false
        end
    end
    return true
end

--- Navigate to a hunting zone. Returns true on success.
local function find_hunting_room(zone_name)
    UserVars.friends = settings.hunting_buddies or {}
    local rooms = hunting_zones[zone_name]
    if rooms then
        hunt_exit = nil
        find_empty_room(rooms, settings.safe_room, function()
            -- Check for friends in room
            local pcs = DRRoom.pcs or {}
            local friends = UserVars.friends

            -- If a friend is visible, stay
            for _, pc in ipairs(pcs) do
                for _, friend in ipairs(friends) do
                    if pc == friend then return true end
                end
            end

            -- If other PCs present (not friends), leave
            if #pcs > 0 then return false end

            -- No PCs visible
            local npcs = DRRoom.npcs or {}
            if #npcs == 0 then return true end

            -- NPCs present, no people - check for hidden players
            for _, friend in ipairs(friends) do
                Flags.add("room-check-" .. friend, friend)
            end
            Flags.add("room-check", "says, ", "say, ", "You hear")
            fput("say Anyone here?")

            local search_result = DRC.bput("search", {
                "You don't find anything of interest here",
                "vague silhouette",
                "attempting to remain hidden",
                "see signs that",
            })

            if search_result ~= "You don't find anything of interest here" then
                pause(1)
                waitrt()
                for _, friend in ipairs(friends) do
                    if Flags["room-check-" .. friend] then
                        return true
                    end
                end
                return false
            end

            -- Wait up to 10 seconds for friend response
            for _ = 1, 20 do
                pause(0.5)
                for _, friend in ipairs(friends) do
                    if Flags["room-check-" .. friend] then
                        return true
                    end
                end
                if Flags["room-check"] then return false end
                -- Check for non-friend PCs
                local current_pcs = DRRoom.pcs or {}
                for _, pc in ipairs(current_pcs) do
                    local is_friend = false
                    for _, friend in ipairs(friends) do
                        if pc == friend then is_friend = true; break end
                    end
                    if not is_friend then return false end
                end
            end
            return true
        end)
    else
        local escort_info = escort_zones[zone_name]
        if not escort_info then
            echo("FAILED TO FIND HUNTING ZONE " .. zone_name .. " IN BASE.YAML")
            return false
        end
        DRCT.walk_to(escort_info["base"])
        wait_for_script_to_complete("bescort", {escort_info["area"], escort_info["enter"]})
        hunt_exit = {escort_info["area"], "exit"}
    end
    return true
end

--- Run a single hunting session with combat-trainer
local function hunt(args, duration, stop_on_skills)
    verify_script("combat-trainer")
    start_script("combat-trainer", args)
    pause(1)
    -- Wait for combat-trainer to start
    local wait_count = 0
    while not Script.running("combat-trainer") and wait_count < 30 do
        pause(1)
        wait_count = wait_count + 1
    end

    local counter = 0
    while true do
        -- Check bleeding
        if settings.stop_hunting_if_bleeding and bleeding() then
            echo("***STATUS*** stopping due to bleeding")
            stopped_for_bleeding = true
            break
        end

        -- Check skill caps
        if all_skills_at_cap(stop_on_skills) then
            echo("***STATUS*** stopping due to skills")
            break
        end

        -- Check duration
        if duration and (counter / 60) >= duration then
            echo("***STATUS*** stopping due to time")
            break
        end

        -- Status report every 60 seconds
        if (counter % 60) == 0 then
            if duration then
                local remaining = duration - math.floor(counter / 60)
                if stop_on_skills then
                    local waiting = {}
                    for _, skill in ipairs(stop_on_skills) do
                        if DRSkill.getxp(skill) < 32 then
                            table.insert(waiting, skill)
                        end
                    end
                    echo("***STATUS*** " .. remaining .. " minutes of hunting remaining or waiting on " .. table.concat(waiting, ", "))
                else
                    echo("***STATUS*** " .. remaining .. " minutes of hunting remaining")
                end
            else
                local elapsed = math.floor(counter / 60)
                local waiting = {}
                if stop_on_skills then
                    for _, skill in ipairs(stop_on_skills) do
                        if DRSkill.getxp(skill) < 32 then
                            table.insert(waiting, skill)
                        end
                    end
                end
                echo("***STATUS*** " .. elapsed .. " minutes of hunting, still waiting on " .. table.concat(waiting, ", "))
            end
        end

        counter = counter + 1
        pause(1)
    end

    -- Stop combat-trainer
    stop_script("combat-trainer")
    -- Wait for it to fully stop
    wait_count = 0
    while Script.running("combat-trainer") and wait_count < 30 do
        pause(1)
        wait_count = wait_count + 1
    end
    DRC.retreat()
end

-- Cleanup on exit
before_dying(function()
    if Script.running("combat-trainer") then
        stop_script("combat-trainer")
    end
end)

-- Main logic
local hunting_info = settings.hunting_info or {}
for _, info in ipairs(hunting_info) do
    if stopped_for_bleeding then
        DRC.retreat()
        if Script.running("tendme") then
            stop_script("tendme")
        end
        break
    end

    local args = info["args"] or info.args or {}
    local duration = info["duration"] or info.duration
    local stop_on_skills = info["stop_on"] or info.stop_on
    local zone = info["zone"] or info.zone

    -- Skip if all skills capped
    if not all_skills_at_cap(stop_on_skills) then
        -- Navigate to zone
        if find_hunting_room(zone) then
            -- Handle nested args (multiple hunt phases)
            if type(args[1]) == "table" then
                for idx, arg in ipairs(args) do
                    local dur = type(duration) == "table" and duration[idx] or duration
                    local skills_check = type(stop_on_skills) == "table" and type(stop_on_skills[1]) == "table" and stop_on_skills[idx] or stop_on_skills
                    hunt(arg, dur, skills_check)
                end
            else
                hunt(args, duration, stop_on_skills)
            end

            -- Exit escort zone if needed
            if hunt_exit then
                wait_for_script_to_complete("bescort", hunt_exit)
            end
        end
    end
end

-- Return to safe room
DRCT.walk_to(settings.safe_room)
EquipmentManager.wear_equipment_set("standard")
