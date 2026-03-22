--- Bigshot State — predicates and target selection
-- All decision logic from bigshot.lic v5.12.1:
--   should_rest, ready_to_hunt, ready_to_rest, should_flee,
--   valid_target, find_target, sort_npcs, priority_target,
--   boon creature handling, wound/dread/oom checks, room claim, etc.

local M = {}

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

-- Regex for 709 detached limb nouns (untargetable)
local LIMB_NOUNS = {
    arm = true, arms = true,
    appendage = true, appendages = true,
    claw = true, claws = true,
    limb = true, limbs = true,
    pincer = true, pincers = true,
    tentacle = true, tentacles = true,
    palpus = true, palpi = true,
}

-- Troll king parts (untargetable)
local TROLL_PARTS = {
    ["quickly growing troll king"] = true,
    ["severed troll arm"] = true,
    ["severed troll leg"] = true,
}

-- Familiar/companion type nouns that are never valid targets
-- (709 familiars, companion creatures, etc.)
local COMPANION_TYPES = { "companion", "familiar" }

-- Bandit noun regex equivalent
local BANDIT_NOUNS = {
    bandit = true, brigand = true, robber = true, thug = true,
    thief = true, rogue = true, outlaw = true, mugger = true,
    marauder = true, highwayman = true,
}

-- Boon ability reverse lookup: adjective (lowercased) -> ability name
-- Built from the Ruby initialize_boon_data, ability -> [adjectives], reversed.
local BOON_ADJECTIVE_MAP = {
    -- From user spec (high-level named abilities like "Ancient Fury")
    ancient       = "Ancient Fury",
    armored       = "Armored",
    big           = "Oversized",
    blighted      = "Blighted",
    cloaked       = "Cloaked",
    colossal      = "Oversized",
    craven        = "Craven",
    cunning       = "Cunning",
    cursed        = "Cursed",
    elusive       = "Elusive",
    emboldened    = "Emboldened",
    enormous      = "Oversized",
    ferocious     = "Ferocious",
    frenzied      = "Frenzied",
    frigid        = "Frigid",
    giant         = "Oversized",
    grim          = "Grim",
    grizzled      = "Grizzled",
    huge          = "Oversized",
    hulking       = "Oversized",
    incandescent  = "Incandescent",
    large         = "Oversized",
    legendary     = "Legendary",
    luminous      = "Luminous",
    mammoth       = "Oversized",
    massive       = "Oversized",
    mighty        = "Mighty",
    monstrous     = "Oversized",
    noxious       = "Noxious",
    otherworldly  = "Otherworldly",
    pestilent     = "Pestilent",
    rabid         = "Rabid",
    raging        = "Raging",
    ravenous      = "Ravenous",
    spectral      = "Spectral",
    titanic       = "Oversized",
    towering      = "Oversized",
    tremendous    = "Oversized",
    venomous      = "Venomous",
}

-- Extended boon adjective map from the Ruby boon_type hash
-- (adjective -> internal ability key used for assess matching)
local BOON_ASSESS_MAP = {
    flickering    = "blink",
    wavering      = "blink",
    shielded      = "bolt_shield",
    robust        = "boosted_hp",
    stalwart      = "boosted_hp",
    luminous      = "boosted_mana",
    lustrous      = "boosted_mana",
    sinuous       = "boosted_defense",
    flexile       = "boosted_defense",
    combative     = "boosted_offense",
    belligerent   = "boosted_offense",
    glorious      = "cheat_death",
    illustrious   = "cheat_death",
    blurry        = "confuse",
    shifting      = "confuse",
    apt           = "counter_attack",
    ready         = "counter_attack",
    resolute      = "crit_death_immune",
    unflinching   = "crit_death_immune",
    stout         = "crit_padding",
    hardy         = "crit_padding",
    shimmering    = "crit_weighting",
    gleaming      = "crit_weighting",
    flinty        = "damage_padding",
    tough         = "damage_padding",
    barbed        = "dmg_weighting",
    spiny         = "dmg_weighting",
    pestilent     = "diseased",
    afflicted     = "diseased",
    diseased      = "diseased",
    dazzling      = "dispelling",
    flashy        = "dispelling",
    glittering    = "elem_flares",
    sparkling     = "elemental_negation",
    shining       = "elemental_negation",
    glowing       = "extra_elem",
    radiant       = "extra_spirit",
    twinkling     = "extra_other",
    ethereal      = "ethereal",
    wispy         = "ethereal",
    ghostly       = "ethereal",
    raging        = "frenzy",
    frenzied      = "frenzy",
    adroit        = "jack",
    deft          = "jack",
    ["rune-covered"] = "magic_resistance",
    tattooed      = "magic_resistance",
    canny         = "mind_blast",
    keen          = "mind_blast",
    dreary        = "parting_shot",
    drab          = "parting_shot",
    indistinct    = "physical_negation",
    nebulous      = "physical_negation",
    ["sickly green"] = "poisonous",
    oozing        = "poisonous",
    slimy         = "regen",
    muculent      = "regen",
    tenebrous     = "soul",
    shadowy       = "soul",
    steadfast     = "stun_immune",
    unyielding    = "stun_immune",
    ghastly       = "terrifying",
    grotesque     = "terrifying",
    spindly       = "weaken",
    lanky         = "weaken",
}

-- Merge BOON_ADJECTIVE_MAP into BOON_ASSESS_MAP so both are available
-- The BOON_ADJECTIVE_MAP values (named abilities) take priority for display
-- but BOON_ASSESS_MAP is the canonical assess lookup
for adj, ability in pairs(BOON_ADJECTIVE_MAP) do
    if not BOON_ASSESS_MAP[adj] then
        BOON_ASSESS_MAP[adj] = ability
    end
end

-- Expose for external use
M.BOON_ABILITIES = BOON_ADJECTIVE_MAP
M.BOON_ASSESS_MAP = BOON_ASSESS_MAP

-------------------------------------------------------------------------------
-- Internal helpers
-------------------------------------------------------------------------------

--- Check if a string matches any entry in a list (case-insensitive plain match)
local function list_contains_ci(list, str)
    if not list or not str then return false end
    local s = str:lower()
    for _, entry in ipairs(list) do
        if s:find(entry:lower(), 1, true) then return true end
    end
    return false
end

--- Check if a string exactly matches any entry in a list (case-insensitive)
local function list_exact_ci(list, str)
    if not list or not str then return false end
    local s = str:lower()
    for _, entry in ipairs(list) do
        if s == entry:lower() then return true end
    end
    return false
end

--- Check if npc.noun matches a limb noun (709 arms etc.)
local function is_limb_noun(noun)
    if not noun then return false end
    return LIMB_NOUNS[noun:lower()] == true
end

--- Check if npc is a companion/familiar type (not aggressive)
local function is_companion_type(npc)
    if not npc or not npc.type then return false end
    local t = npc.type:lower()
    -- Companions and familiars are not valid unless they are aggressive NPCs
    if t:find("aggressive npc", 1, true) then return false end
    for _, ctype in ipairs(COMPANION_TYPES) do
        if t:find(ctype, 1, true) then return true end
    end
    return false
end

--- Check if npc is an animated creature (but not "animated slush")
local function is_animated_untargetable(npc)
    if not npc or not npc.name then return false end
    local name = npc.name:lower()
    return name:find("animated", 1, true) ~= nil and name:find("animated slush", 1, true) == nil
end

--- Check if npc is in troll parts list
local function is_troll_part(npc)
    if not npc or not npc.name then return false end
    return TROLL_PARTS[npc.name:lower()] == true
end

--- Check if NPC is an escort type
local function is_escort(npc)
    if not npc or not npc.type then return false end
    return npc.type:lower():find("escort", 1, true) ~= nil
end

--- Check if NPC is a boon creature
local function is_boon(npc)
    if not npc or not npc.type then return false end
    return npc.type:lower():find("boon", 1, true) ~= nil
end

--- Check if a bandit noun
local function is_bandit_noun(noun)
    if not noun then return false end
    return BANDIT_NOUNS[noun:lower()] == true
end

--- Get NPC status as dead/gone check
local function is_dead_or_gone(npc)
    if not npc then return true end
    if not npc.status then return false end
    local s = npc.status:lower()
    return s:find("dead", 1, true) ~= nil or s:find("gone", 1, true) ~= nil
end

--- Check if targets map is effectively empty (nil, empty table, or all-blank keys)
local function targets_empty(targets)
    if not targets then return true end
    if type(targets) ~= "table" then return true end
    local count = 0
    for k, _ in pairs(targets) do
        if k and k ~= "" then count = count + 1 end
    end
    return count == 0
end

--- Safe pattern match for creature name against a target key
--- Uses Lua find with plain=true for safety, case-insensitive
--- The Ruby code uses regex anchored: /^key$/i matching against name or noun
local function creature_matches_key(npc, key)
    if not npc or not key or key == "" then return false end
    local k = key:lower()
    local name = (npc.name or ""):lower()
    local noun = (npc.noun or ""):lower()
    -- Exact match (Ruby uses /^key$/i)
    return name == k or noun == k
end

-------------------------------------------------------------------------------
-- Boon Creature System
-------------------------------------------------------------------------------

--- Assess a creature for boon abilities, cache results.
--- Sends "assess #id" command, parses response for ability adjectives.
--- Returns table of ability names, or nil.
function M.check_boons(creature, bstate)
    if not creature then return nil end
    if not is_boon(creature) then return nil end

    -- Initialize cache
    if not bstate._boon_cache then bstate._boon_cache = {} end

    -- Return cached result
    if bstate._boon_cache[creature.id] ~= nil then
        local cached = bstate._boon_cache[creature.id]
        if cached == false then return nil end -- cached negative
        return cached
    end

    -- Send assess command and collect response
    local lines = quiet_command("assess #" .. creature.id,
        "appears to be",
        "You do not currently have a target")

    if not lines then
        bstate._boon_cache[creature.id] = false
        return nil
    end

    -- Find the line with "appears to be"
    local text = nil
    if type(lines) == "table" then
        for _, line in ipairs(lines) do
            if line:find("appears to be", 1, true) then
                text = line
                break
            end
        end
    elseif type(lines) == "string" then
        if lines:find("appears to be", 1, true) then
            text = lines
        end
    end

    if not text then
        bstate._boon_cache[creature.id] = false
        return nil
    end

    -- Strip XML tags
    local cleaned = text:gsub("<[^>]+>", "")

    -- Capture descriptors after "appears to be"
    local phrase = cleaned:match("[Aa]ppears to be (.+)")
    if not phrase then
        bstate._boon_cache[creature.id] = false
        return nil
    end

    -- Clean up trailing period and whitespace
    phrase = phrase:gsub("%.$", ""):lower()

    -- Split by commas or "and"
    local parts = {}
    for part in phrase:gmatch("[^,]+") do
        -- Further split on " and "
        for subpart in part:gmatch("[^a]+") do
            -- This naive split won't work; use gsub approach
        end
        parts[#parts + 1] = part
    end

    -- Better split: split on comma first, then on " and "
    parts = {}
    for segment in phrase:gmatch("[^,]+") do
        segment = segment:match("^%s*(.-)%s*$") -- trim
        -- Split on " and "
        local subs = {}
        local remaining = segment
        while true do
            local before, after = remaining:match("^(.-)%s+and%s+(.+)$")
            if before then
                subs[#subs + 1] = before:match("^%s*(.-)%s*$")
                remaining = after
            else
                subs[#subs + 1] = remaining:match("^%s*(.-)%s*$")
                break
            end
        end
        for _, s in ipairs(subs) do
            if s ~= "" then
                parts[#parts + 1] = s
            end
        end
    end

    -- Map adjectives to ability names
    local abilities = {}
    local seen = {}
    for _, adj in ipairs(parts) do
        local ability = BOON_ADJECTIVE_MAP[adj] or BOON_ASSESS_MAP[adj]
        if ability and not seen[ability] then
            abilities[#abilities + 1] = ability
            seen[ability] = true
        end
    end

    if #abilities == 0 then
        bstate._boon_cache[creature.id] = false
        return nil
    end

    bstate._boon_cache[creature.id] = abilities
    return abilities
end

--- Check if a boon creature has abilities in the ignore list.
--- Returns true if the creature should be skipped as a target.
function M.invalid_target_with_boons(creature, bstate)
    local ignore_list = bstate.boons_ignore
    if not ignore_list or #ignore_list == 0 then return false end
    if not is_boon(creature) then return false end

    local abilities = M.check_boons(creature, bstate)
    if not abilities then return false end

    -- Check intersection of abilities and ignore list
    for _, ability in ipairs(abilities) do
        for _, ignored in ipairs(ignore_list) do
            if ability:lower() == ignored:lower() then
                return true
            end
        end
    end

    return false
end

--- Check if any NPC in room has boon abilities in the flee list.
--- Returns true if we should flee.
function M.should_flee_from_boons(bstate)
    local flee_list = bstate.boons_flee
    if not flee_list or #flee_list == 0 then return false end

    local npcs = GameObj.npcs()
    if not npcs then return false end

    for _, creature in ipairs(npcs) do
        if is_boon(creature) then
            local abilities = M.check_boons(creature, bstate)
            if abilities then
                for _, ability in ipairs(abilities) do
                    for _, flee_name in ipairs(flee_list) do
                        if ability:lower() == flee_name:lower() then
                            return true
                        end
                    end
                end
            end
        end
    end

    return false
end

-------------------------------------------------------------------------------
-- Target Selection
-------------------------------------------------------------------------------

--- Sort NPCs by target priority.
--- If bstate.targets is a table mapping creature_name -> letter (a-j),
--- sort by letter order. Filter out dead, gone, untargetable (709 arms,
--- escorts, animated creatures). If targets list is empty/blank, target
--- everything. For quick mode, use quickhunt_targets. For bandit hunting,
--- prioritize bandit nouns. Returns sorted array of NPC objects.
function M.sort_npcs(bstate)
    local npcs = GameObj.npcs()
    if not npcs or #npcs == 0 then return {} end

    local is_quick = bstate._quick_mode or false
    local is_bandit = bstate._bandit_mode or false
    local targets = bstate.targets or {}
    local quickhunt_targets = bstate.quickhunt_targets or {}
    local untargetable = bstate._untargetable or {}

    -- Build effective targets map
    local effective_targets = {}

    if is_quick or is_bandit then
        -- Start with quickhunt_targets
        for k, v in pairs(quickhunt_targets) do
            effective_targets[k] = v
        end

        -- If quickhunt_targets is empty, auto-populate from room NPCs
        if targets_empty(quickhunt_targets) then
            for _, npc in ipairs(npcs) do
                local name = (npc.name or ""):lower()
                if not untargetable[name] then
                    if not is_bandit or is_bandit_noun(npc.noun) then
                        effective_targets[name] = "quick"
                    end
                end
            end
        end

        -- Merge with existing targets map
        for k, v in pairs(targets) do
            if not effective_targets[k] then
                effective_targets[k] = v
            end
        end
    else
        -- Normal mode: use targets map, or match everything if empty
        if targets_empty(targets) then
            -- Target everything (Ruby: @TARGETS ||= { ".+"=>"a" })
            effective_targets[".+"] = "a"
        else
            for k, v in pairs(targets) do
                effective_targets[k] = v
            end
        end
    end

    -- Build ordered result: iterate target keys, collect matching NPCs
    local result = {}
    local seen_ids = {}

    for target_key, _ in pairs(effective_targets) do
        for _, npc in ipairs(npcs) do
            if not seen_ids[npc.id] then
                -- Check if NPC matches this target key
                local matches = false
                if target_key == ".+" then
                    -- Match everything
                    matches = true
                else
                    matches = creature_matches_key(npc, target_key)
                end

                if matches then
                    seen_ids[npc.id] = true
                    result[#result + 1] = npc
                end
            end
        end
    end

    return result
end

--- Find best valid target from sorted NPCs.
--- If current_target is still valid, keeps it (unless priority says switch).
--- Returns NPC or nil.
function M.find_target(bstate, just_entered)
    just_entered = just_entered or false
    local current = bstate._current_target

    -- If current target is still valid, keep it
    if current and M.valid_target(current, bstate, just_entered) then
        return current
    end

    -- Search sorted NPCs for first valid target
    local sorted = M.sort_npcs(bstate)
    for _, npc in ipairs(sorted) do
        if M.valid_target(npc, bstate, just_entered) then
            -- Check priority if enabled
            if not bstate._bandit_mode and bstate.priority then
                if M.priority_target(npc, bstate) then
                    return npc
                end
            else
                return npc
            end
        end
    end

    return nil
end

--- Full target validation.
--- Checks all conditions that would make a target invalid.
--- Returns true if the NPC is a valid combat target.
function M.valid_target(npc, bstate, just_entered)
    just_entered = just_entered or false

    if not npc then return false end

    -- Dead or gone
    if is_dead_or_gone(npc) then return false end

    -- Check if NPC is still in GameObj.npcs collection
    local in_room = false
    local room_npcs = GameObj.npcs()
    if room_npcs then
        for _, room_npc in ipairs(room_npcs) do
            if room_npc.id == npc.id then
                in_room = true
                break
            end
        end
    end
    if not in_room then return false end

    -- Animated creatures (not animated slush)
    if is_animated_untargetable(npc) then
        -- Add to untargetable cache
        if not bstate._untargetable then bstate._untargetable = {} end
        if npc.name then
            bstate._untargetable[npc.name:lower()] = true
        end
        return false
    end

    -- 709 limb nouns
    if is_limb_noun(npc.noun) then return false end

    -- Troll parts
    if is_troll_part(npc) then return false end

    -- Companion/familiar (not aggressive)
    if is_companion_type(npc) then return false end

    -- Escort type
    if is_escort(npc) then return false end

    -- Check untargetable cache
    if not bstate._untargetable then bstate._untargetable = {} end
    if npc.name and bstate._untargetable[npc.name:lower()] then
        return false
    end

    -- Invalid targets list (user-configured exclusions)
    local invalid_targets = bstate.invalid_targets or {}
    if list_exact_ci(invalid_targets, npc.name) then return false end
    if list_exact_ci(invalid_targets, npc.noun) then return false end

    -- Boon creature with ignored abilities
    if is_boon(npc) and M.invalid_target_with_boons(npc, bstate) then
        return false
    end

    -- Should flee check (includes boon flee, flee count, etc.)
    if M.should_flee(bstate, just_entered) then return false end

    -- Lone targets only: skip if room has > 1 valid target when just entering
    if just_entered and bstate.lone_targets_only then
        local valid_count = 0
        local all_npcs = GameObj.npcs()
        if all_npcs then
            for _, other in ipairs(all_npcs) do
                if not is_dead_or_gone(other)
                    and not is_limb_noun(other.noun)
                    and not is_troll_part(other)
                    and not is_companion_type(other)
                    and not is_escort(other)
                    and not is_animated_untargetable(other) then
                    valid_count = valid_count + 1
                end
            end
        end
        if valid_count > 1 then return false end
    end

    -- If targets map is non-empty, check that this NPC is in it
    local targets = bstate.targets or {}
    if not targets_empty(targets) then
        local found = false
        for target_key, _ in pairs(targets) do
            if creature_matches_key(npc, target_key) then
                found = true
                break
            end
        end
        -- In quick mode or bandit mode, also check quickhunt_targets
        if not found and (bstate._quick_mode or bstate._bandit_mode) then
            local qt = bstate.quickhunt_targets or {}
            for target_key, _ in pairs(qt) do
                if creature_matches_key(npc, target_key) then
                    found = true
                    break
                end
            end
            -- In bandit mode, bandit nouns are always valid
            if not found and bstate._bandit_mode and is_bandit_noun(npc.noun) then
                found = true
            end
            -- In quick mode with empty quickhunt_targets, everything is valid
            if not found and bstate._quick_mode and targets_empty(qt) then
                found = true
            end
        end
        if not found then return false end
    end

    -- Targetable verification (send target command if unknown)
    if bstate._targetable == nil then bstate._targetable = {} end
    local npc_name_lower = (npc.name or ""):lower()

    if not bstate._targetable[npc_name_lower] and not bstate._untargetable[npc_name_lower] then
        -- Try to target the creature to verify it is targetable
        local result = dothistimeout("target #" .. npc.id, 3,
            "You are now targeting",
            "You can't target",
            "You discern that you are the origin",
            "You are unable to discern the origin")

        if result then
            if result:find("You are now targeting", 1, true) then
                if not is_dead_or_gone(npc) then
                    bstate._targetable[npc_name_lower] = true
                end
            elseif result:find("You can't target", 1, true)
                or result:find("You discern that you are the origin", 1, true)
                or result:find("You are unable to discern the origin", 1, true) then
                if not is_dead_or_gone(npc) then
                    bstate._untargetable[npc_name_lower] = true
                end
            end
        end
    end

    if bstate._untargetable[npc_name_lower] then
        return false
    end

    return true
end

--- Check if a higher-priority target exists than current one.
--- Returns true if current target IS the highest priority, false otherwise.
--- (Ruby: priority() returns true if target is still the priority)
function M.priority_target(current_target, bstate)
    if not current_target then return false end
    if bstate._bandit_mode then return true end
    if not bstate.priority then return true end

    -- Check if room NPCs have changed
    local room_npcs = GameObj.npcs() or {}
    local last_check = bstate._room_npcs_last_check or {}

    -- Compare current NPCs to last check
    local changed = false
    if #room_npcs ~= #last_check then
        changed = true
    else
        for i, npc in ipairs(room_npcs) do
            if not last_check[i] or npc.id ~= last_check[i].id then
                changed = true
                break
            end
        end
    end

    if not changed then return true end

    -- Room changed, re-evaluate priority
    bstate._room_npcs_last_check = room_npcs

    -- Filter out untargetable
    local valid_npcs = {}
    for _, npc in ipairs(room_npcs) do
        if not bstate._untargetable or not bstate._untargetable[(npc.name or ""):lower()] then
            valid_npcs[#valid_npcs + 1] = npc
        end
    end

    -- Walk target keys in order; first match wins
    local targets = bstate.targets or {}
    for target_key, _ in pairs(targets) do
        for _, npc in ipairs(valid_npcs) do
            if creature_matches_key(npc, target_key) then
                -- This is the highest-priority NPC
                return (npc.name or ""):lower() == (current_target.name or ""):lower()
            end
        end
    end

    return true
end

--- Count of valid living NPCs in room (excluding invalid/dead/gone/untargetable).
function M.gameobj_npc_check(bstate)
    local npcs = GameObj.npcs()
    if not npcs then return 0 end

    local untargetable = bstate._untargetable or {}
    local count = 0

    for _, npc in ipairs(npcs) do
        if not is_dead_or_gone(npc)
            and not is_animated_untargetable(npc)
            and not is_limb_noun(npc.noun)
            and not is_troll_part(npc)
            and not is_companion_type(npc)
            and not is_escort(npc)
            and not untargetable[(npc.name or ""):lower()] then
            count = count + 1
        end
    end

    return count
end

-------------------------------------------------------------------------------
-- Status Checks
-------------------------------------------------------------------------------

--- Check if character has wounds.
--- If wounded_eval is configured, evaluates it. Otherwise checks all body
--- parts for severity > 0. Returns false in quick mode.
function M.is_wounded(bstate)
    if bstate._quick_mode then return false end

    -- If a custom wounded_eval function is set, use it
    if bstate.wounded_eval and type(bstate.wounded_eval) == "function" then
        return bstate.wounded_eval()
    end

    -- If wounded_eval is a string expression, evaluate it
    if bstate.wounded_eval and type(bstate.wounded_eval) == "string" and bstate.wounded_eval ~= "" then
        local fn, err = load("return " .. bstate.wounded_eval)
        if fn then
            local ok, result = pcall(fn)
            if ok then return result end
        end
        return false
    end

    -- Default: check all wound/scar body parts
    if not Wounds and not Scars then return false end
    local parts = {
        "head", "neck", "torso", "rightArm", "leftArm",
        "rightHand", "leftHand", "rightLeg", "leftLeg", "nsys",
        "rightEye", "leftEye"
    }
    for _, part in ipairs(parts) do
        if Wounds and Wounds[part] and Wounds[part] > 0 then return true end
        if Scars and Scars[part] and Scars[part] > 0 then return true end
    end

    return false
end

--- Returns true if mind_value >= fried threshold (unless fried > 100 or quick mode).
function M.fried(bstate)
    if bstate._quick_mode then return false end

    local fried_threshold = bstate.fried or 100
    if fried_threshold > 100 then return false end

    local mind = bstate._correct_percent_mind or GameState.mind_value or 0
    return mind >= fried_threshold
end

--- Returns true if percent_mana < oom threshold.
function M.oom(bstate)
    local oom_threshold = bstate.oom or 0
    if oom_threshold < 0 then return false end
    if oom_threshold == 0 then return false end

    return (Char.percent_mana or 100) < oom_threshold
end

--- Returns true if overkill counter >= overkill limit AND lte_boost done.
function M.overkill(bstate)
    local overkill_limit = bstate.overkill or 0
    local counter = bstate._overkill_counter or 0
    return counter >= overkill_limit and M.lte_boost(bstate)
end

--- Returns true if lte_boost counter >= lte_boost limit.
function M.lte_boost(bstate)
    local lte_limit = bstate.lte_boost or 0
    local counter = bstate._lte_boost_counter or 0
    return counter >= lte_limit
end

--- Check Effects.Debuffs for "Creeping Dread" level.
--- Returns true if dread level >= configured threshold.
function M.creeping_dread(bstate)
    local threshold = bstate.creeping_dread or 0
    if threshold <= 0 then return false end

    if not Effects or not Effects.Debuffs then return false end

    -- Look for "Creeping Dread" in debuffs (may have level in parens)
    local debuffs = Effects.Debuffs.to_h and Effects.Debuffs.to_h() or {}
    for key, _ in pairs(debuffs) do
        local k = tostring(key)
        if k:find("Creeping Dread", 1, true) then
            -- Extract level from "(N)" if present
            local level = tonumber(k:match("%((%d+)%)"))
            if level and level >= threshold then
                return true
            end
            -- If no level number, just the presence means level 1
            if not level and threshold <= 1 then
                return true
            end
        end
    end

    return false
end

--- Check Effects.Debuffs for "Crushing Dread" level.
--- Returns true if dread level >= configured threshold.
function M.crushing_dread(bstate)
    local threshold = bstate.crushing_dread or 0
    if threshold <= 0 then return false end

    if not Effects or not Effects.Debuffs then return false end

    local debuffs = Effects.Debuffs.to_h and Effects.Debuffs.to_h() or {}
    for key, _ in pairs(debuffs) do
        local k = tostring(key)
        if k:find("Crushing Dread", 1, true) then
            local level = tonumber(k:match("%((%d+)%)"))
            if level and level >= threshold then
                return true
            end
            if not level and threshold <= 1 then
                return true
            end
        end
    end

    return false
end

--- Check for Wall of Thorns Poison debuff.
--- Returns true if wot_poison setting is enabled and debuff is active.
function M.wot_poison(bstate)
    if not bstate.wot_poison then return false end

    if not Effects or not Effects.Debuffs then return false end

    -- Check debuffs hash for Wall of Thorns Poison
    local debuffs = Effects.Debuffs.to_h and Effects.Debuffs.to_h() or {}
    for key, _ in pairs(debuffs) do
        if tostring(key):find("Wall of Thorns Poison", 1, true) then
            return true
        end
    end

    -- Also check via active() if available
    if Effects.Debuffs.active then
        return Effects.Debuffs.active("Wall of Thorns Poison") or false
    end

    return false
end

--- Mind is fully saturated.
function M.saturated(bstate)
    -- Check if GameState has a mind text or similar
    local mind = GameState.mind_value or 0
    -- Saturated is typically mind_value at maximum (100+)
    -- In Ruby: checkmind =~ /saturated/
    -- We approximate: saturated means mind is at or beyond 100%
    return mind >= 100
end

--- Update correct_percent_mind.
--- Uses "experience" command if near fried threshold for accurate reading.
function M.check_mind(bstate)
    local base_mind = GameState.mind_value or 0
    bstate._correct_percent_mind = base_mind

    local fried_threshold = bstate.fried or 100

    -- If we're near the fried threshold, get an accurate reading
    if base_mind >= fried_threshold then
        -- Send experience command for precise FXP reading
        local lines = quiet_command("experience", "Experience")
        if lines then
            -- Try to parse percent_fxp from the response
            -- The engine should update GameState.mind_value after this
            bstate._correct_percent_mind = GameState.mind_value or base_mind
        end
    end

    return bstate._correct_percent_mind
end

-------------------------------------------------------------------------------
-- Should Rest
-------------------------------------------------------------------------------

--- Returns true + reason if character should stop hunting.
--- Checks all rest conditions from bigshot v5.12.1.
function M.should_rest(bstate)
    if bstate._quick_mode then return false, nil end

    -- Bounty complete (bounty_eval)
    if bstate.bounty_mode and bstate._bigshot_should_rest then
        return true, "bounty complete"
    end

    -- External $bigshot_should_rest flag
    if bstate._bigshot_should_rest then
        return true, bstate._rest_reason or "$bigshot_should_rest set"
    end

    -- Wounded
    if M.is_wounded(bstate) then
        return true, "wounded"
    end

    -- Fried + overkill + lte_boost all met
    if M.fried(bstate) and M.overkill(bstate) and M.lte_boost(bstate) then
        return true, "fried"
    end

    -- Encumbered
    local encumbered_threshold = bstate.encumbered or 101
    if (Char.percent_encumbrance or 0) >= encumbered_threshold then
        return true, "encumbered"
    end

    -- Crushing dread level exceeded
    if M.crushing_dread(bstate) then
        return true, "crushing dread limit"
    end

    -- Creeping dread level exceeded
    if M.creeping_dread(bstate) then
        return true, "creeping dread limit"
    end

    -- Wall of Thorns poison
    if M.wot_poison(bstate) then
        return true, "wall of thorns poison"
    end

    -- Confusion debuff
    if bstate.confusion and Effects and Effects.Debuffs and Effects.Debuffs.active then
        if Effects.Debuffs.active("Confused") then
            return true, "confusion debuff"
        end
    end

    -- OOM (with optional wracking attempt first)
    if M.oom(bstate) then
        -- Note: wracking is attempted in ready_to_rest flow, not here
        return true, "out of mana"
    end

    -- Box in hand after looting
    if bstate.box_in_hand and bstate._box_in_hand then
        return true, "box in hand"
    end

    return false, nil
end

--- Returns reason string if should rest, nil if should keep hunting.
--- This is ready_to_rest? from Ruby — used for the leader's own check
--- in the rest decision flow. Similar to should_rest but used differently.
function M.ready_to_rest(bstate)
    if bstate._quick_mode then return nil end

    -- Bounty mode + should_rest flag
    if bstate.bounty_mode and bstate._bigshot_should_rest then
        return "bounty complete"
    end

    -- External flag
    if bstate._bigshot_should_rest then
        return bstate._rest_reason or "$bigshot_should_rest set"
    end

    -- Wounded
    if M.is_wounded(bstate) then
        return "wounded"
    end

    -- Fried + overkill + lte_boost
    if M.fried(bstate) and M.overkill(bstate) and M.lte_boost(bstate) then
        return "fried"
    end

    -- Encumbered
    local encumbered_threshold = bstate.encumbered or 101
    if (Char.percent_encumbrance or 0) >= encumbered_threshold then
        return "encumbered"
    end

    -- Crushing dread
    if M.crushing_dread(bstate) then
        return "crushing dread limit"
    end

    -- Creeping dread
    if M.creeping_dread(bstate) then
        return "creeping dread limit"
    end

    -- Wall of Thorns poison
    if M.wot_poison(bstate) then
        return "wall of thorns poison"
    end

    -- Confusion
    if bstate.confusion and Effects and Effects.Debuffs and Effects.Debuffs.active then
        if Effects.Debuffs.active("Confused") then
            return "confusion debuff"
        end
    end

    -- OOM (with wracking attempt)
    if M.oom(bstate) then
        -- Attempt wracking if enabled (caller should handle wrack before this)
        return "out of mana"
    end

    return nil
end

--- Returns true if ready to hunt again.
--- All recovery thresholds must be met.
function M.ready_to_hunt(bstate)
    -- Wounded
    if M.is_wounded(bstate) then return false, "wounded" end

    -- Encumbered
    local encumbered_threshold = bstate.encumbered or 101
    if (Char.percent_encumbrance or 0) >= encumbered_threshold then
        return false, "encumbered"
    end

    -- Creeping dread still active
    if M.creeping_dread(bstate) then return false, "creeping dread active" end

    -- Crushing dread still active
    if M.crushing_dread(bstate) then return false, "crushing dread active" end

    -- Confusion
    if bstate.confusion and Effects and Effects.Debuffs and Effects.Debuffs.active then
        if Effects.Debuffs.active("Confused") then
            return false, "confusion debuff active"
        end
    end

    -- Wall of Thorns poison
    if M.wot_poison(bstate) then return false, "wall of thorns poison active" end

    -- Mind still above rest_till_exp threshold
    local rest_till_exp = bstate.rest_till_exp or 0
    if rest_till_exp > 0 then
        local mind = bstate._correct_percent_mind or GameState.mind_value or 0
        if mind > rest_till_exp then
            return false, "mind still above threshold"
        end
    end

    -- Mana below rest_till_mana threshold
    local rest_till_mana = bstate.rest_till_mana or 0
    if rest_till_mana > 0 then
        if (Char.percent_mana or 0) < rest_till_mana then
            return false, "mana still below threshold"
        end
    end

    -- Spirit below rest_till_spirit threshold
    local rest_till_spirit = bstate.rest_till_spirit or 0
    if rest_till_spirit > 0 then
        if (Char.spirit or 0) < rest_till_spirit then
            return false, "spirit still below threshold"
        end
    end

    -- Stamina below rest_till_percentstamina threshold
    local rest_till_stamina = bstate.rest_till_percentstamina or 0
    if rest_till_stamina > 0 then
        if (Char.percent_stamina or 0) < rest_till_stamina then
            return false, "stamina still below threshold"
        end
    end

    -- Check resting scripts still running
    local resting_scripts = bstate.resting_scripts or {}
    for _, script_entry in ipairs(resting_scripts) do
        local name = script_entry:match("^(%S+)")
        if name and Script and Script.running and Script.running(name) then
            return false, "resting scripts still running"
        end
    end

    return true, "ready"
end

-------------------------------------------------------------------------------
-- Should Flee
-------------------------------------------------------------------------------

--- Returns true + reason if should leave room.
--- Checks flee count, always_flee_from, clouds/vines/webs/voids,
--- boon flee, external flee flags, ambusher presence.
function M.should_flee(bstate, just_entered)
    just_entered = just_entered or false

    -- Quick mode never flees
    if bstate._quick_mode then return false, nil end

    -- External flee flag (from flee_message monitor)
    if bstate._bigshot_flee then
        return true, "flee message triggered"
    end

    -- Ambusher present
    if bstate._ambusher_here then
        return true, "ambusher present"
    end

    -- Check loot objects for clouds/vines/webs/voids
    local loot = GameObj.loot and GameObj.loot() or {}
    for _, item in ipairs(loot) do
        local noun = (item.noun or ""):lower()
        local name = (item.name or ""):lower()

        if bstate.flee_clouds then
            if noun:find("cloud", 1, true) or noun:find("breath", 1, true)
                or name == "intense shimmering circle" then
                return true, "flee from cloud"
            end
        end

        if bstate.flee_vines then
            if noun:find("vine", 1, true) then
                return true, "flee from vines"
            end
        end

        if bstate.flee_webs then
            if noun:find("web", 1, true) then
                return true, "flee from webs"
            end
        end

        if bstate.flee_voids then
            if name:find("black void", 1, true) then
                return true, "flee from void"
            end
        end
    end

    -- Always flee from specific creatures (by noun or name)
    local always_flee = bstate.always_flee_from or {}
    if #always_flee > 0 then
        local npcs = GameObj.npcs() or {}
        for _, npc in ipairs(npcs) do
            if list_exact_ci(always_flee, npc.noun) or list_exact_ci(always_flee, npc.name) then
                return true, "flee from " .. (npc.name or npc.noun or "creature")
            end
        end

        -- Also check PCs in always_flee_from list
        local pcs = GameObj.pcs and GameObj.pcs() or {}
        for _, pc in ipairs(pcs) do
            local pc_name = pc.name or pc.noun or ""
            if list_exact_ci(always_flee, pc_name) then
                return true, "flee from player " .. pc_name
            end
        end
    end

    -- Skip flee count check in bandit mode
    if bstate._bandit_mode then return false, nil end

    -- Boon creature flee list
    local boons_flee = bstate.boons_flee or {}
    if #boons_flee > 0 then
        local npcs = GameObj.npcs() or {}
        local has_boons = false
        for _, npc in ipairs(npcs) do
            if is_boon(npc) then
                has_boons = true
                break
            end
        end
        if has_boons and M.should_flee_from_boons(bstate) then
            return true, "flee from boon creature"
        end
    end

    -- Flee count: too many valid enemies
    local flee_count = bstate.flee_count or 100

    -- If just entered and lone_targets_only, effective flee count is 1
    if just_entered and bstate.lone_targets_only then
        flee_count = 1
    end

    if flee_count > 0 then
        -- Count valid NPCs (same filter as Ruby should_flee)
        local npcs = GameObj.npcs() or {}
        local valid = {}
        local untargetable = bstate._untargetable or {}
        local inv_targets = bstate.invalid_targets or {}

        for _, npc in ipairs(npcs) do
            local dominated = false

            -- Filter same as Ruby
            if is_dead_or_gone(npc) then dominated = true end
            if not dominated and list_exact_ci(inv_targets, npc.name) then dominated = true end
            if not dominated and list_exact_ci(inv_targets, npc.noun) then dominated = true end
            if not dominated and untargetable[(npc.name or ""):lower()] then dominated = true end
            if not dominated and is_limb_noun(npc.noun) then dominated = true end
            if not dominated and is_troll_part(npc) then dominated = true end
            if not dominated and is_companion_type(npc) then dominated = true end

            if not dominated then
                valid[#valid + 1] = npc
            end
        end

        if #valid > flee_count then
            return true, "too many enemies (" .. #valid .. " > " .. flee_count .. ")"
        end
    end

    return false, nil
end

-------------------------------------------------------------------------------
-- Room Claim
-------------------------------------------------------------------------------

--- Check if room is claimed by another player/group.
--- Returns true if room is ours (safe to loot/act).
--- check_disks: whether to verify no foreign disks are present.
function M.bigclaim(bstate, check_disks)
    if check_disks == nil then check_disks = true end

    -- Only leader checks claim
    local leader = bstate._leader or GameState.name
    if GameState.name ~= leader then return true end

    -- Quick mode: always claimed
    if bstate._quick_mode then return true end

    -- Use Claim module if available
    if Claim and Claim.mine then
        if not Claim.mine() then return false end
    end

    -- Disk check: make sure no foreign disks
    if not bstate.ignore_disks and check_disks then
        if Disk and Disk.all and Group and Group.disks then
            local all_disks = Disk.all() or {}
            local group_disks = Group.disks() or {}

            -- Build set of group disk IDs
            local group_disk_ids = {}
            for _, d in ipairs(group_disks) do
                group_disk_ids[d.id or d] = true
            end

            -- Check for foreign disks
            for _, d in ipairs(all_disks) do
                local did = d.id or d
                if not group_disk_ids[did] then
                    return false
                end
            end
        end
    end

    return true
end

--- Determines if looting is needed.
--- Checks dead NPCs, claim status, delay_loot timer.
function M.need_to_loot(bstate, check_delayed)
    check_delayed = check_delayed or false

    -- Must have claim
    if not M.bigclaim(bstate, false) then return false end

    -- Should not be fleeing
    if M.should_flee(bstate) then return false end

    -- Ambusher check
    if bstate._ambusher_here then return false end

    -- Count dead NPCs (excluding escorts)
    local npcs = GameObj.npcs() or {}
    local dead_npcs = {}
    for _, npc in ipairs(npcs) do
        if npc.status and npc.status:lower():find("dead", 1, true)
            and not is_escort(npc) then
            dead_npcs[#dead_npcs + 1] = npc
        end
    end

    -- Check if there are valid living targets
    local has_valid = false
    local sorted = M.sort_npcs(bstate)
    for _, npc in ipairs(sorted) do
        if M.valid_target(npc, bstate) then
            has_valid = true
            break
        end
    end

    -- If no dead NPCs and there are valid targets, no need to loot
    if #dead_npcs == 0 and has_valid then return false end

    -- Delay loot check: if delayed looting is enabled and there are valid targets
    if bstate.delay_loot and has_valid and not check_delayed then
        -- Check if enough time has passed (15 second timer)
        local now = os.time()
        local last_loot_check = bstate._last_loot_check_time or 0
        if (now - last_loot_check) < 15 then
            return false
        end
        bstate._last_loot_check_time = now
    end

    -- Also check for loot on the ground
    local ground_loot = GameObj.loot and GameObj.loot() or {}
    if #dead_npcs == 0 and #ground_loot == 0 then return false end

    return true
end

-------------------------------------------------------------------------------
-- Utility
-------------------------------------------------------------------------------

--- Reset combat tracking variables on room change.
--- Clears aim counters, smite list, 703 list, 1614 list, archery tracking,
--- UAC tier, flee flags, reaction, etc.
function M.reset_variables(bstate, moved)
    if moved == nil then moved = true end

    if moved then
        bstate._ambusher_here = false
        bstate._smite_list = {}
        bstate._703_list = {}
        bstate._1614_list = {}
    end

    bstate._aim = 0
    bstate._ambush_count = 0
    bstate._archery_aim = 0
    bstate._archery_stuck_location = {}
    bstate._dislodge_location = {}
    bstate._unarmed_tier = 1
    bstate._unarmed_followup = false
    bstate._unarmed_followup_attack = ""
    bstate._reaction = nil

    -- Clear boon cache on room change
    if moved then
        bstate._boon_cache = {}
    end
end

--- Map target name to command routine letter (A-J), return the appropriate
--- command list. If group is not solo and fried, use disable_commands.
--- Quick mode uses quick_commands if available.
function M.find_routine(target, bstate)
    -- DISABLE override: if not solo, fried, and disable_commands configured
    local disable_cmds = bstate.disable_commands or {}
    if not bstate._solo_mode and M.fried(bstate) and #disable_cmds > 0 then
        return disable_cmds
    end

    if not target then return bstate.hunting_commands or {} end

    local targets = bstate.targets or {}

    -- Find matching key in targets map
    local routine_letter = "a"
    local found_key = false

    for target_key, letter in pairs(targets) do
        if creature_matches_key(target, target_key) then
            routine_letter = (letter or "a"):lower()
            found_key = true
            break
        end
    end

    -- Quick mode: use quick_commands if target mapped to 'quick' or no explicit mapping
    if routine_letter == "quick" or (bstate._quick_mode and not found_key) then
        local quick_cmds = bstate.quick_commands or {}
        if #quick_cmds > 0 then
            return quick_cmds
        end
    end

    -- Lookup table for letters b-j
    if routine_letter ~= "a" then
        local key = "hunting_commands_" .. routine_letter
        local cmds = bstate[key]
        if cmds and type(cmds) == "table" and #cmds > 0 then
            return cmds
        end
    end

    -- Fallback to default hunting commands
    return bstate.hunting_commands or {}
end

return M
