-- osacombat/health.lua — Health monitoring, healing, status effects, anti-poaching, looting
-- Ported from osacombat.lic (OSA — GemStone IV automated combat).
-- Handles: death checks, status effects, injuries, poison, disease, overexertion,
--          unstunning PCs, environmental hazards ("bad stuff"), group tracking,
--          anti-poach detection, dead NPC identification, and looting.

local M = {}

---------------------------------------------------------------------------
-- Module state
---------------------------------------------------------------------------
local everyone_in_group = {}
local everyone_hidden   = {}
local poaching          = false
local list_of_bad_things  = {}  -- hostile environmental objects (id → true)
local list_of_good_things = {}  -- friendly environmental objects (id → true)

---------------------------------------------------------------------------
-- Body part keys for wound/scar checks
---------------------------------------------------------------------------
local BODY_PARTS = {
    "head", "neck", "chest", "abdomen", "back",
    "leftArm", "rightArm", "leftHand", "rightHand",
    "leftLeg", "rightLeg", "leftFoot", "rightFoot",
    "leftEye", "rightEye", "nsys",
}

---------------------------------------------------------------------------
-- Civilian / limb nouns excluded from dead NPC checks
---------------------------------------------------------------------------
local CIVILIAN_NOUNS = {
    "child", "traveller", "scribe", "merchant", "pilgrim", "refugee",
    "beggar", "peasant", "citizen", "townsman", "townswoman", "villager",
    "farmer", "fisherman", "hunter", "miner", "sailor", "soldier",
    "guard", "sentry", "watchman", "clerk", "shopkeeper", "innkeeper",
    "bartender", "barmaid", "servant", "slave", "prisoner", "noble",
    "lady", "lord", "knight", "squire", "page", "herald", "monk",
    "priest", "priestess", "acolyte", "cleric",
}

local LIMB_NOUNS = {
    "arm", "appendage", "claw", "tentacle", "leg", "limb",
    "hand", "finger", "tail", "wing", "pincer", "mandible",
}

local function set_from_list(t)
    local s = {}
    for _, v in ipairs(t) do s[v] = true end
    return s
end

local CIVILIAN_SET = set_from_list(CIVILIAN_NOUNS)
local LIMB_SET     = set_from_list(LIMB_NOUNS)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function has_living_npcs()
    local npcs = GameObj.npcs()
    for _, npc in ipairs(npcs) do
        local status = (npc.status or ""):lower()
        if not status:find("dead") and not status:find("gone") then
            return true
        end
    end
    return false
end

local function stand_check()
    if not dead() and not standing() then
        fput("stand")
        waitrt()
    end
end

local function safe_room(cfg)
    local room = cfg.safe_room or ""
    if room == "" then room = "town" end
    return room
end

---------------------------------------------------------------------------
-- 1. M.check_dead()
---------------------------------------------------------------------------
function M.check_dead()
    if dead() then
        respond("*** OSACombat: You have died! Script exiting. ***")
        -- Original also sent LNet message and cast Spell[9823] — skipped (no LNet in Revenant)
        error("OSACombat: character is dead — aborting")
    end
end

---------------------------------------------------------------------------
-- 2. M.check_status(cfg)
---------------------------------------------------------------------------
function M.check_status(cfg)
    local status_flag  = false
    local need_dispel  = false

    -- Check debuffs that set status_flag
    local status_debuffs = {
        "Stunned", "Calmed", "Frenzied", "Cursed",
        "Webbed", "Bound", "Interference", "Moonbeam", "Stone Fist",
    }
    for _, debuff in ipairs(status_debuffs) do
        if Effects.Debuffs.active(debuff) then
            status_flag = true
            break
        end
    end

    -- Also check function-based status
    if stunned() or webbed() or bound() then
        status_flag = true
    end

    -- Check debuffs that need dispel
    if Effects.Debuffs.active("Earthen Fury") or Effects.Debuffs.active("Condemn") then
        need_dispel = true
    end

    -- Symbol of Transcendence emergency
    if cfg.get_bool("symbol_of_transcendance") then
        local rt = tonumber(GameState.roundtime or 0) or 0
        if rt > 6 and (not standing() or stunned() or webbed()) and has_living_npcs() then
            if Spell[9812].known and Spell[9812]:affordable() then
                Spell[9812]:cast()
                waitrt()
                waitcastrt()
            end
        end
    end

    -- DI Armor emergency
    if cfg.get_bool("di_armor") then
        local rt = tonumber(GameState.roundtime or 0) or 0
        local bad_state = not standing() or stunned() or webbed() or bound()
        if rt > 6 and bad_state and has_living_npcs() then
            fput("incarn armor")
            waitrt()
        end
    end

    -- If status flag set, try Beseech (1635) to clear effects
    if status_flag then
        if Spell[1635].known and Spell[1635]:affordable() then
            waitrt()
            waitcastrt()
            Spell[1635]:cast()
            waitrt()
            waitcastrt()
            pause(0.3)
            -- Recursive re-check
            M.check_status(cfg)
            return
        end
    end

    -- If need dispel, try 119 (Dispel Invisibility) or 417 (Elemental Dispel) on self
    if need_dispel then
        local charname = GameState.name or ""
        if Spell[119].known and Spell[119]:affordable() then
            waitrt()
            waitcastrt()
            fput("incant 119 channel " .. charname)
            waitrt()
            waitcastrt()
            pause(0.3)
            M.check_status(cfg)
            return
        elseif Spell[417].known and Spell[417]:affordable() then
            waitrt()
            waitcastrt()
            fput("incant 417 channel " .. charname)
            waitrt()
            waitcastrt()
            pause(0.3)
            M.check_status(cfg)
            return
        end
    end

    stand_check()
end

---------------------------------------------------------------------------
-- 3. M.check_for_injuries(cfg)
---------------------------------------------------------------------------
function M.check_for_injuries(cfg)
    -- Activate blood wellspring gemstone if enabled
    if cfg.get_bool("gemstone_blood_wellspring") then
        local health_threshold = cfg.get_num("activate_blood_wellspring_health_if")
        if percenthealth() < health_threshold then
            if not Effects.Buffs.active("Blood Wellspring") then
                fput("activate blood wellspring")
                pause(0.5)
            end
        end
    end

    -- Symbol of Restore emergency heal
    if cfg.get_bool("symbol_of_restore") and percenthealth() < cfg.get_num("percent_health") then
        while percenthealth() < 90 do
            fput("sym rest")
            pause(1)
            if percenthealth() >= 90 then break end
        end
    end

    -- Check all body parts for wounds exceeding threshold
    local wound_level = cfg.get_num("wound_level")
    local wounded = false
    for _, part in ipairs(BODY_PARTS) do
        local w = Wounds[part] or 0
        local s = Scars[part] or 0
        if w > wound_level or s > wound_level then
            wounded = true
            break
        end
    end

    if not wounded then return end

    -- Medical officer is self — run ecure
    local charname = GameState.name or ""
    local medical_officer = cfg.medical_officer or ""
    if medical_officer == charname or medical_officer == "" then
        if not running("ecure") then
            Script.run("ecure")
        end
        wait_while(function() return running("ecure") end)
    else
        -- Not self-healer — navigate to safe room for eherbs healing
        respond("OSACombat: Wounded — heading to safe room for healing.")
        local dest = safe_room(cfg)
        Map.go2(dest)
        if not running("eherbs") then
            Script.run("eherbs")
        end
        wait_while(function() return running("eherbs") end)
    end

    -- Warn if still wounded after healing
    for _, part in ipairs(BODY_PARTS) do
        local w = Wounds[part] or 0
        local s = Scars[part] or 0
        if w > wound_level or s > wound_level then
            respond("OSACombat WARNING: Still wounded after healing attempt (" .. part .. ").")
            break
        end
    end
end

---------------------------------------------------------------------------
-- 4. M.check_for_poison(cfg)
---------------------------------------------------------------------------
function M.check_for_poison(cfg)
    -- Check for Wall of Thorns Poison debuffs or poisoned() state
    local is_poisoned = poisoned()
    if not is_poisoned then
        for i = 1, 5 do
            if Effects.Debuffs.active("Wall of Thorns Poison " .. tostring(i)) then
                is_poisoned = true
                break
            end
        end
    end

    if not is_poisoned then return end

    -- Try Spell 114 (Cure Poison / Purify Air)
    if Spell[114].known and Spell[114]:affordable() then
        waitrt()
        waitcastrt()
        Spell[114]:cast()
        waitrt()
        waitcastrt()
        return
    end

    -- Navigate to healer / safe room and wait
    respond("OSACombat: Poisoned — heading to safe room for healing.")
    local dest = safe_room(cfg)
    Map.go2(dest)
    wait_until(function() return not poisoned() end)
end

---------------------------------------------------------------------------
-- 5. M.check_for_disease(cfg)
---------------------------------------------------------------------------
function M.check_for_disease(cfg)
    if not diseased() then return end

    -- Try Spell 113 (Remove Disease / Unpresence)
    if Spell[113].known and Spell[113]:affordable() then
        waitrt()
        waitcastrt()
        Spell[113]:cast()
        waitrt()
        waitcastrt()
        return
    end

    -- Navigate to healer
    respond("OSACombat: Diseased — heading to safe room for healing.")
    local dest = safe_room(cfg)
    Map.go2(dest)
    wait_until(function() return not diseased() end)
end

---------------------------------------------------------------------------
-- 6. M.check_for_popped(cfg)
---------------------------------------------------------------------------
function M.check_for_popped(cfg)
    if not Effects.Debuffs.active("Overexerted") then return end

    -- Try Spell 1107 (Kai's Strike / muscle repair)
    if Spell[1107].known and Spell[1107]:affordable() then
        waitrt()
        waitcastrt()
        Spell[1107]:cast()
        waitrt()
        waitcastrt()
        return
    end

    -- Navigate to healer
    respond("OSACombat: Overexerted — heading to safe room for healing.")
    local dest = safe_room(cfg)
    Map.go2(dest)
    wait_until(function() return not Effects.Debuffs.active("Overexerted") end)
end

---------------------------------------------------------------------------
-- 7. M.check_for_stunned(cfg)
---------------------------------------------------------------------------
function M.check_for_stunned(cfg)
    if not cfg.use_unstun then return end
    if stunned() or dead() then return end
    if not Spell[108].known then return end

    local pcs = GameObj.pcs()
    for _, pc in ipairs(pcs) do
        local status = (pc.status or ""):lower()
        if status:find("stunned") then
            -- Wait until we have enough mana
            wait_until(function() return checkmana() >= 8 end)
            waitrt()
            waitcastrt()
            if Spell[108]:affordable() then
                Spell[108]:cast(pc.noun or pc.name)
                waitrt()
                waitcastrt()
            end
        end
    end
end

---------------------------------------------------------------------------
-- 8. M.check_for_badstuff(cfg)
---------------------------------------------------------------------------

-- Nouns considered hostile environmental hazards
local BAD_THING_NOUNS = {
    "globe", "rift", "cyclone", "vine", "web", "cloud",
    "whirlwind", "sandstorm", "vortex", "swarm", "tempest",
    "void", "anomaly",
}
local BAD_THING_SET = set_from_list(BAD_THING_NOUNS)

function M.check_for_badstuff(cfg)
    local loot = GameObj.loot()
    for _, obj in ipairs(loot) do
        local noun = (obj.noun or ""):lower()
        local id   = obj.id

        -- Skip already-tracked objects
        if list_of_good_things[id] or list_of_bad_things[id] then
            -- already known, skip
        elseif BAD_THING_SET[noun] then
            list_of_bad_things[id] = true
            M.cast_at_bad_thing(cfg, obj)
        end
    end

    -- Clean up tracked objects no longer in the room
    local current_ids = {}
    for _, obj in ipairs(loot) do
        current_ids[obj.id] = true
    end
    for id, _ in pairs(list_of_bad_things) do
        if not current_ids[id] then list_of_bad_things[id] = nil end
    end
    for id, _ in pairs(list_of_good_things) do
        if not current_ids[id] then list_of_good_things[id] = nil end
    end
end

---------------------------------------------------------------------------
-- 9. M.cast_at_bad_thing(cfg, bad_thing)
---------------------------------------------------------------------------

-- Nouns that respond to 612/505/1218 (weather-type hazards)
local WEATHER_NOUNS = set_from_list({
    "cloud", "cyclone", "whirlwind", "sandstorm", "vortex",
})

-- Nouns that respond to 417/119 (magical construct hazards)
local CONSTRUCT_NOUNS = set_from_list({
    "vine", "web", "swarm", "tempest", "void", "globe", "rift", "anomaly",
})

function M.cast_at_bad_thing(cfg, bad_thing)
    local noun = (bad_thing.noun or ""):lower()
    local id   = bad_thing.id
    local target = "#" .. tostring(id)

    waitrt()
    waitcastrt()

    if WEATHER_NOUNS[noun] then
        -- Try 612 (Breeze), then 505 (Hand of Tonis), then 1218 (Weapon Fire)
        if Spell[612].known and Spell[612]:affordable() then
            fput("incant 612 " .. target)
        elseif Spell[505].known and Spell[505]:affordable() then
            fput("incant 505 " .. target)
        elseif Spell[1218].known and Spell[1218]:affordable() then
            fput("incant 1218 " .. target)
        end
    elseif CONSTRUCT_NOUNS[noun] then
        -- Try 417 (Elemental Dispel) or 119 (Dispel Invisibility)
        if Spell[417].known and Spell[417]:affordable() then
            fput("incant 417 " .. target)
        elseif Spell[119].known and Spell[119]:affordable() then
            fput("incant 119 " .. target)
        end
    end

    waitrt()
    waitcastrt()
end

---------------------------------------------------------------------------
-- 10. M.health_monitor(cfg, cc)
---------------------------------------------------------------------------
function M.health_monitor(cfg, cc)
    M.check_dead()
    M.check_status(cfg)
    M.check_for_injuries(cfg)
    M.check_for_poison(cfg)
    M.check_for_disease(cfg)
    M.check_for_popped(cfg)
    M.check_for_stunned(cfg)
    M.check_for_badstuff(cfg)
end

---------------------------------------------------------------------------
-- 11. M.determine_group_members()
---------------------------------------------------------------------------
function M.determine_group_members()
    everyone_in_group = {}
    everyone_hidden   = {}

    local result = dothistimeout("group", 5,
        "Your group|You are not currently in a group|you are not in a group")

    if not result then return everyone_in_group end

    -- Parse each line of group output for member names
    -- Typical format:  " Playername is also a member of your group."
    --                  " Playername is the leader of your group."
    --                  " Playername (hidden) is also a member of your group."
    local lines = result
    if type(lines) == "string" then
        -- Include self
        local charname = GameState.name or ""
        if charname ~= "" then
            table.insert(everyone_in_group, charname)
        end

        for line in lines:gmatch("[^\r\n]+") do
            -- Match member names — captures the name before " is "
            local name = line:match("^%s*(%u%a+)%s+is%s+")
            if name then
                table.insert(everyone_in_group, name)
                -- Check for hidden indicator
                if line:find("%(hidden%)") then
                    table.insert(everyone_hidden, name)
                end
            end
        end
    end

    return everyone_in_group
end

---------------------------------------------------------------------------
-- 12. M.check_for_poaching(cfg)
---------------------------------------------------------------------------
function M.check_for_poaching(cfg)
    if cfg.state then
        cfg.state.poaching = false
    end
    poaching = false

    local pcs = checkpcs() or {}
    if #pcs == 0 then return false end

    -- Build set of known group members
    local group_set = {}
    for _, name in ipairs(everyone_in_group) do
        group_set[name] = true
    end

    -- Any PC not in our group is a potential poacher
    for _, pc_name in ipairs(pcs) do
        if not group_set[pc_name] then
            poaching = true
            if cfg.state then
                cfg.state.poaching = true
            end
            return true
        end
    end

    return false
end

---------------------------------------------------------------------------
-- 13. M.checkfordead()
---------------------------------------------------------------------------

-- Animated creature nouns that should NOT be excluded
local ANIMATED_EXCEPTION = set_from_list({ "slush" })

function M.checkfordead()
    local dead_npcs = {}
    local npcs = GameObj.npcs()

    for _, npc in ipairs(npcs) do
        local status = (npc.status or ""):lower()
        local noun   = (npc.noun or ""):lower()
        local name   = (npc.name or ""):lower()

        -- Must be dead or gone
        if status:find("dead") or status:find("gone") then
            -- Exclude animated creatures (except animated slush)
            local is_animated = name:find("animated") and not ANIMATED_EXCEPTION[noun]
            if not is_animated then
                -- Exclude civilians and limb nouns
                if not CIVILIAN_SET[noun] and not LIMB_SET[noun] then
                    table.insert(dead_npcs, npc)
                end
            end
        end
    end

    return dead_npcs
end

---------------------------------------------------------------------------
-- 14. M.looter(cfg)
---------------------------------------------------------------------------
function M.looter(cfg)
    local dead_npcs = M.checkfordead()
    if #dead_npcs == 0 then return end

    -- Must not be stunned/dead/etc.
    if dead() or stunned() then return end

    -- Anti-poaching check
    if cfg.get_bool("check_for_group") then
        M.check_for_poaching(cfg)
        if poaching then
            respond("OSACombat: Non-group PCs present — skipping loot.")
            return
        end
    end

    -- Run eloot if looting is enabled
    if cfg.get_bool("osalooter") then
        waitrt()
        waitcastrt()

        local args = nil
        if cfg.get_bool("skin_only") then
            args = "skin"
        end

        if not running("eloot") then
            if args then
                Script.run("eloot", args)
            else
                Script.run("eloot")
            end
        end
        wait_while(function() return running("eloot") end)

        -- Return to defensive stance
        local def_stance = cfg.defending_stance or "Defensive"
        fput("stance " .. def_stance:lower())
    end
end

return M
