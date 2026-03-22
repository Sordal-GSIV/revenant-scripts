-- tpick/lockpicks.lua — Lockpick management: tier hierarchy, selection, scanning, appraisal, repair
-- Ported from tpick.lic lines 1492-1611, 1795-1811, 2252-2362, 4039-4095, 4607-4745, 5312-5344, 5367-5406, 5859-5869

local M = {}
local data = require("tpick/data")
local util = require("tpick/util")

-- Precision text → tier name mapping for LMAS APPRAISE results.
-- Some tiers require both precision AND strength to disambiguate (Veniom/Invar, Alum/Golvern).
-- Order matches original tpick.lic lines 1500-1543.
local PRECISION_TO_TIER = {
    ["detrimental"]         = "Detrimental",
    ["ineffectual"]         = "Ineffectual",
    ["very inaccurate"]     = "Copper",
    ["inaccurate"]          = "Steel",
    ["somewhat inaccurate"] = "Gold",
    ["inefficient"]         = "Silver",
    ["unreliable"]          = "Mithril",
    ["below average"]       = "Ora",
    ["average"]             = "Glaes",
    ["above average"]       = "Laje",
    -- Vultite is missing from the original appraise chain (lines 1500-1543)
    -- The original Ruby skips directly from "above average" (Laje) to "somewhat accurate" (Mein)
    ["somewhat accurate"]   = "Mein",
    ["favorable"]           = "Rolaren",
    ["advantageous"]        = "Rolaren",
    ["accurate"]            = "Accurate",
    -- "highly accurate" → Veniom or Invar (requires strength check)
    -- "excellent"        → Alum or Golvern (requires strength check)
    ["incredible"]          = "Kelyn",
    ["unsurpassed"]         = "Vaalin",
}

-- Strength-dependent precision tiers (need both precision + strength to determine tier)
local PRECISION_STRENGTH_TIERS = {
    ["highly accurate"] = {
        { strength = "incredibly strong",     tier = "Invar"  },
        { strength = nil,                     tier = "Veniom" },  -- default/fallback
    },
    ["excellent"] = {
        { strength = "astonishingly strong",  tier = "Golvern" },
        { strength = nil,                     tier = "Alum"    },  -- default/fallback
    },
}

-- Build a reverse lookup: tier_name → index in LOCKPICK_NAMES (1-based)
local TIER_INDEX = {}
for i, name in ipairs(data.LOCKPICK_NAMES) do
    TIER_INDEX[name] = i
end

---------------------------------------------------------------------------
-- M.init(settings) — Parse lockpick settings into name/ID lookup tables.
-- Port of lines 1795-1811 + 5270 (ID population).
--
-- @param settings  Table with load_data (settings hash) populated.
-- @return settings_pick_names  tier_name → {name1, name2, ...}
-- @return all_pick_ids         tier_name → {id1, id2, ...}
-- @return all_repair_names     repair_name → {name1, name2, ...}
-- @return all_repair_ids       repair_name → {id1, id2, ...}
---------------------------------------------------------------------------
function M.init(settings)
    local load_data = settings.load_data
    local settings_pick_names = {}
    local all_pick_ids = {}
    local all_repair_names = {}
    local all_repair_ids = {}

    -- Parse comma-separated pick names from settings for each of 20 tiers
    for _, name in ipairs(data.LOCKPICK_NAMES) do
        all_pick_ids[name] = {}
        settings_pick_names[name] = {}
        local raw = load_data[name] or ""
        for part in raw:gmatch("[^,]+") do
            local trimmed = part:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(settings_pick_names[name], trimmed)
            end
        end
    end

    -- Parse comma-separated repair names from settings for each of 16 repair tiers
    for _, name in ipairs(data.REPAIR_NAMES) do
        all_repair_ids[name] = {}
        all_repair_names[name] = {}
        local raw = load_data[name] or ""
        for part in raw:gmatch("[^,]+") do
            local trimmed = part:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(all_repair_names[name], trimmed)
            end
        end
    end

    -- Populate pick IDs by matching inventory item names against settings names
    -- Port of line 5270: container.contents.each { |i| all_pick_ids.each { ... push if match } }
    M.populate_pick_ids(settings_pick_names, all_pick_ids, all_repair_names, all_repair_ids, settings)

    return settings_pick_names, all_pick_ids, all_repair_names, all_repair_ids
end

---------------------------------------------------------------------------
-- M.populate_pick_ids — Scan a lockpick container's contents and map items to tier IDs.
-- Port of line 5270 (contents iteration + ID push).
--
-- @param settings_pick_names  tier_name → {name1, name2, ...}
-- @param all_pick_ids         tier_name → {id1, id2, ...} (mutated)
-- @param all_repair_names     repair_name → {name1, name2, ...}
-- @param all_repair_ids       repair_name → {id1, id2, ...} (mutated)
-- @param settings             Table with load_data containing "Lockpick Container" name.
---------------------------------------------------------------------------
function M.populate_pick_ids(settings_pick_names, all_pick_ids, all_repair_names, all_repair_ids, settings)
    local load_data = settings.load_data
    local container_name = load_data["Lockpick Container"] or ""
    if container_name == "" then return end

    -- Find the lockpick container in inventory
    local container = nil
    local inv = GameObj.inv()
    if inv then
        for _, item in ipairs(inv) do
            if item.name == container_name then
                container = item
                break
            end
        end
    end

    if not container then
        echo("Could not find lockpick container: " .. container_name)
        return
    end

    -- Look in the container to populate contents
    fput("look in #" .. container.id)
    pause(0.5)

    -- Scan contents and match against configured pick names
    local contents = container.contents
    if contents then
        for _, item in ipairs(contents) do
            for tier_name, names in pairs(settings_pick_names) do
                for _, pick_name in ipairs(names) do
                    if item.name == pick_name then
                        table.insert(all_pick_ids[tier_name], item.id)
                    end
                end
            end
            for repair_name, names in pairs(all_repair_names) do
                for _, rname in ipairs(names) do
                    if item.name == rname then
                        table.insert(all_repair_ids[repair_name], item.id)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- M.next_pick(vars, settings, all_pick_ids, settings_pick_names) — Advance to next
-- higher lockpick tier.
-- Port of lines 2252-2353. Table-driven instead of 20-level if/elsif chain.
--
-- @param vars               Mutable picking state table.
-- @param settings           Settings table with load_data.
-- @param all_pick_ids       tier_name → {id1, id2, ...}
-- @param settings_pick_names  tier_name → {name1, name2, ...}
---------------------------------------------------------------------------
function M.next_pick(vars, settings, all_pick_ids, settings_pick_names)
    local load_data = settings.load_data

    vars["Before Needed Pick"] = vars["Needed Pick"]
    vars["Before Pick"] = vars["Recommended Pick"]

    local current_tier = vars["Recommended Pick"]
    local current_idx = TIER_INDEX[current_tier]

    if current_tier == "Vaalin" and vars["Roll Amount"] ~= 100 then
        -- Stay on Vaalin, flag 403 needed
        if not (load_data["403"] or ""):lower():find("never") then
            vars["403 Needed"] = "yes"
        end
        vars["Needed Pick"] = load_data["Vaalin"]
        vars["Needed Pick ID"] = all_pick_ids["Vaalin"] and all_pick_ids["Vaalin"][1]
        vars["Recommended Pick"] = "Vaalin"
    elseif current_tier == "Vaalin" and vars["Roll Amount"] == 100 then
        -- Exhausted all tiers with max roll — go to wedge
        vars["Needed Pick"] = "wedge"
    elseif current_idx then
        -- Advance to next tier
        local next_idx = current_idx + 1
        if next_idx > #data.LOCKPICK_NAMES then
            next_idx = #data.LOCKPICK_NAMES  -- cap at Vaalin
        end
        local next_tier = data.LOCKPICK_NAMES[next_idx]
        vars["Needed Pick"] = load_data[next_tier]
        vars["Needed Pick ID"] = all_pick_ids[next_tier] and all_pick_ids[next_tier][1]
        vars["Recommended Pick"] = next_tier
    else
        -- Unknown tier; try Vaalin as fallback
        vars["Needed Pick"] = load_data["Vaalin"]
        vars["Needed Pick ID"] = all_pick_ids["Vaalin"] and all_pick_ids["Vaalin"][1]
        vars["Recommended Pick"] = "Vaalin"
    end

    -- Validate vaalin picks exist
    M.no_vaalin_picks(vars, settings, all_pick_ids)

    -- Handle nil pick ID (broken or missing picks at this tier)
    if vars["Needed Pick ID"] == nil and vars["Needed Pick"] ~= "wedge" then
        if vars["Recommended Pick"] == "Vaalin" then
            util.tpick_silent(true,
                "ALL OF YOUR VAALIN LOCKPICKS ARE BROKEN. YOU REALLY SHOULD HAVE AT LEAST 1 WORKING VAALIN LOCKPICK WHEN RUNNING THIS SCRIPT.",
                settings)
            -- Fatal: cannot continue without vaalin
            error("tpick: No working Vaalin lockpicks")
        else
            util.tpick_silent(true,
                "All of your " .. vars["Recommended Pick"] .. " lockpicks seem to be broken or you don't have any lockpicks of that type, trying a higher tier lockpick.",
                settings)
            -- Recurse to next tier
            M.next_pick(vars, settings, all_pick_ids, settings_pick_names)
        end
    elseif vars["Before Needed Pick"] == vars["Needed Pick"] and vars["Recommended Pick"] ~= "Vaalin" then
        -- Same pick as before and not Vaalin — skip to next
        M.next_pick(vars, settings, all_pick_ids, settings_pick_names)
    else
        -- Got a valid new pick — execute the swap
        M.nextpick2(vars, settings, all_pick_ids)
    end
end

---------------------------------------------------------------------------
-- M.no_vaalin_picks(vars, settings, all_pick_ids) — Validate that at least
-- one vaalin lockpick ID exists. Exit with error if not.
-- Port of lines 2355-2362.
--
-- @param vars          Picking state table.
-- @param settings      Settings table with load_data.
-- @param all_pick_ids  tier_name → {id1, id2, ...}
---------------------------------------------------------------------------
function M.no_vaalin_picks(vars, settings, all_pick_ids)
    local load_data = settings.load_data
    local pop_boxes = vars["Pop Boxes"]
    local pick_enruned = load_data["Pick Enruned"] == "Yes"

    -- Only check when not in pop-only mode, or when pop mode with Pick Enruned
    if (not pop_boxes) or (pop_boxes and pick_enruned) then
        local vaalin_ids = all_pick_ids["Vaalin"] or {}
        if (#vaalin_ids == 0 or vaalin_ids[1] == nil) and vars["Picking Mode"] then
            vars["Error Message"] = "I could not find any of your Vaalin Lockpicks. "
                .. "You need at least 1 Vaalin Lockpick (any lockpick you enter into the 'Vaalin Lockpick' setting) "
                .. "for this script to run correctly.\n\n"
                .. "Check ;tpick setup to be sure 'Vaalin Lockpick' and 'Lockpick Container' are filled out correctly "
                .. "and be sure you have your Vaalin Lockpick in your Lockpick container.\n\n"
                .. "It is also possible that all of your Vaalin lockpicks are broken, "
                .. "you should repair or replace them in that case."
            error("tpick: No Vaalin lockpicks found")
        end
    end
end

---------------------------------------------------------------------------
-- M.lock_pick_information(vars, settings, all_pick_ids) — Given a recommended
-- pick tier name, populate vars with pick name, ID, and modifier.
-- Port of lines 4607-4690. Table-driven using LOCKPICK_NAMES and PICK_MODIFIERS.
--
-- @param vars          Picking state table (mutated).
-- @param settings      Settings table with load_data.
-- @param all_pick_ids  tier_name → {id1, id2, ...}
---------------------------------------------------------------------------
function M.lock_pick_information(vars, settings, all_pick_ids)
    local load_data = settings.load_data
    local tier = vars["Recommended Pick"]
    local idx = TIER_INDEX[tier]

    if idx then
        vars["Needed Pick"] = load_data[tier]
        vars["Needed Pick ID"] = all_pick_ids[tier] and all_pick_ids[tier][1]
        vars["Recommended Pick Modifier"] = data.PICK_MODIFIERS[idx]

        -- Extra validation when reaching Vaalin tier
        if tier == "Vaalin" then
            M.no_vaalin_picks(vars, settings, all_pick_ids)
        end
    end
end

---------------------------------------------------------------------------
-- M.nextpick2(vars, settings, all_pick_ids) — Execute the actual pick swap:
-- stow current pick, get the new recommended pick.
-- Port of lines 4692-4743.
--
-- @param vars          Picking state table.
-- @param settings      Settings table with load_data.
-- @param all_pick_ids  tier_name → {id1, id2, ...}
---------------------------------------------------------------------------
function M.nextpick2(vars, settings, all_pick_ids)
    local load_data = settings.load_data

    if vars["Needed Pick"] == "wedge" then
        -- Wedge logic: handle plinites, scale traps, or normal wedge/407
        if vars["Open Plinites"] or (vars["Current Box"] and vars["Current Box"].name and string.find(vars["Current Box"].name, "plinite")) then
            if vars["Picking Mode"] == "worker" then
                util.tpick_silent(true,
                    "Can't extract this plinite based on my calculations. If you think this is in error increase the Vaalin Lock Roll setting in the setup menu.",
                    settings)
                vars["Give Up On Box"] = true
            else
                util.tpick_silent(true,
                    "Can't extract this plinite, OPENing it instead. If you think this is in error increase the Vaalin Lock Roll setting in the setup menu.",
                    settings)
                waitrt()
                fput("open #" .. vars["Current Box"].id)
            end
        elseif vars["Scale Trap Found"] then
            util.tpick_silent(true, "Can't pick this box and it has a scales trap.", settings)
            if vars["Picking Mode"] == "solo" then
                util.where_to_stow_box(vars)
            elseif vars["Picking Mode"] == "other" then
                util.tpick_say("Can't Open Box", settings)
                -- open_others() called from picking module
                vars["Next Task"] = "open_others"
            elseif vars["Picking Mode"] == "ground" then
                vars["Can't Open Plated Box Count"] = (vars["Can't Open Plated Box Count"] or 0) + 1
                vars["Box Opened"] = nil
            end
        else
            if Stats.prof == "Rogue" then
                util.tpick_silent(nil, "Can't pick this lock, going to try to wedge it open.", settings)
                -- wedge_lock() called from picking module
                vars["Next Task"] = "wedge_lock"
            elseif Spell[407].known and not vars["Box Has Glyph Trap"] then
                util.tpick_silent(nil, "Can't pick this lock, going to try to pop it open.", settings)
                -- cast_407() called from picking module
                vars["Next Task"] = "cast_407"
            else
                if Spell[407].known and vars["Box Has Glyph Trap"] then
                    util.tpick_silent(true, "I can't use 407 on this box because it has a glyph trap.", settings)
                end
                util.tpick_silent(true, "Couldn't open this box.", settings)
                if vars["Picking Mode"] == "other" then
                    util.tpick_say("Can't Open Box", settings)
                    vars["Next Task"] = "open_others"
                elseif vars["Picking Mode"] == "ground" then
                    vars["Box Opened"] = nil
                elseif vars["Picking Mode"] == "solo" then
                    util.where_to_stow_box(vars)
                    util.tpick_put_stuff_away(vars, settings)
                    pause(0.1)
                end
            end
        end
    elseif vars["Before Needed Pick"] == load_data["Vaalin"] then
        util.tpick_silent(nil, "Trying to pick with Vaalin lockpick again.", settings)
        -- pick_2() called from picking module
        vars["Next Task"] = "pick_2"
    else
        util.tpick_silent(nil,
            "Couldn't pick lock with " .. (vars["Before Pick"] or "unknown") .. " pick, trying " .. (vars["Recommended Pick"] or "unknown") .. " pick.",
            settings)
        -- pick_2() called from picking module
        vars["Next Task"] = "pick_2"
    end
end

---------------------------------------------------------------------------
-- M.calculate_needed_lockpick(vars, settings, all_pick_ids) — Given a lock
-- difficulty number, calculate which lockpick tier is appropriate.
-- Port of lines 5367-5406.
--
-- @param vars          Picking state table (mutated with Recommended Pick, etc.)
-- @param settings      Settings table with load_data.
-- @param all_pick_ids  tier_name → {id1, id2, ...}
---------------------------------------------------------------------------
function M.calculate_needed_lockpick(vars, settings, all_pick_ids)
    local load_data = settings.load_data
    local number = 0
    local pick_skill = vars["Pick Skill"] or 0
    local pick_lore = vars["Pick Lore"] or 0
    local lock_difficulty = vars["Lock Difficulty"] or 0
    local lock_roll = tonumber(load_data["Lock Roll"]) or 0

    vars["Total Pick Skill"] = pick_skill + pick_lore

    -- Check if even Vaalin (2.50 modifier) is insufficient
    if (vars["Total Pick Skill"]) * 2.50 - lock_difficulty + lock_roll < 100
        or vars["Can't Determine Plinite Difficulty"] then
        -- Need Vaalin with spells
        vars["Needed Pick"] = load_data["Vaalin"]
        vars["Needed Pick ID"] = all_pick_ids["Vaalin"] and all_pick_ids["Vaalin"][1]
        M.no_vaalin_picks(vars, settings, all_pick_ids)

        if not (load_data["403"] or ""):lower():find("never") then
            vars["403 Needed"] = "yes"
        end
        if not (load_data["404"] or ""):lower():find("never") then
            vars["Need 404"] = "yes"
        end
        if not (load_data["403"] or ""):lower():find("never") then
            vars["Need 403"] = true
        end
        number = 19  -- Vaalin index (0-based in original, but we'll clamp later)
    else
        -- Walk up the modifier tiers until skill*modifier - difficulty + roll >= 100
        for i, modifier in ipairs(data.PICK_MODIFIERS) do
            vars["Total Pick Skill"] = pick_skill * modifier
            if vars["Total Pick Skill"] - lock_difficulty + lock_roll < 100 then
                number = number + 1
                -- If we've reached tier 19+ (Kelyn/Vaalin), flag 403 needed
                if number > 18 and not (load_data["403"] or ""):lower():find("never") then
                    vars["Need 403"] = true
                end
            else
                break
            end
            -- Check if 403 should be used based on difficulty threshold
            if vars["Use 403 For Lock Difficulty"] and lock_difficulty > vars["Use 403 For Lock Difficulty"] then
                vars["Need 403"] = true
            end
        end

        -- If 403 is needed, recalculate with pick_skill + pick_lore
        if vars["Need 403"] then
            number = 0
            if not (load_data["403"] or ""):lower():find("never") then
                vars["403 Needed"] = "yes"
            end
            if not (load_data["404"] or ""):lower():find("never") then
                vars["Need 404"] = "yes"
            end
            for _, modifier in ipairs(data.PICK_MODIFIERS) do
                vars["Total Pick Skill"] = (pick_skill + pick_lore) * modifier
                if vars["Total Pick Skill"] - lock_difficulty + lock_roll < 100 then
                    number = number + 1
                else
                    break
                end
            end
        end
    end

    -- Clamp to valid range (0-based index in original, our LOCKPICK_NAMES is 1-based)
    -- number is 0-based tier count: 0 = Detrimental, 19 = Vaalin
    number = math.min(number, 19)
    -- Convert to 1-based index
    vars["Recommended Pick"] = data.LOCKPICK_NAMES[number + 1]

    M.lock_pick_information(vars, settings, all_pick_ids)
end

---------------------------------------------------------------------------
-- M.appraise_lockpick(name, settings) — Use LMAS APPRAISE on a lockpick to
-- determine its material quality tier.
-- Port of lines 1492-1553.
--
-- @param name      Short name of the lockpick item.
-- @param settings  Settings table with load_data (mutated to append pick name to tier).
-- @return tier_name  The material tier, or nil if unrecognized / not a lockpick.
---------------------------------------------------------------------------
function M.appraise_lockpick(name, settings)
    local load_data = settings.load_data
    local lockpick_found = false
    local tier = nil

    -- The lockpick should already be in hand; appraise whatever is in the right hand
    local rh = GameObj.right_hand()
    local rh_name = rh and rh.name or "lockpick"

    local result = dothistimeout(
        "lmas appraise my " .. rh_name,
        4,
        "level of precision|That's not a lockpick|Please rephrase"
    )

    if result and string.find(result, "level of precision") then
        -- Parse: "It seems to have a(n) <precision> level of precision and is/has <strength>."
        local precision = string.match(result, "have an? (.-) level of precision")
        local strength = string.match(result, "and is (.-)%.") or
                         string.match(result, "and has (.-)%.")

        if precision then
            local p_lower = precision:lower()

            -- Check simple precision-only tiers first
            tier = PRECISION_TO_TIER[p_lower]

            -- Check strength-dependent tiers
            if not tier and PRECISION_STRENGTH_TIERS[p_lower] then
                local entries = PRECISION_STRENGTH_TIERS[p_lower]
                local fallback_tier = nil
                for _, entry in ipairs(entries) do
                    if entry.strength == nil then
                        fallback_tier = entry.tier
                    elseif strength and strength:lower():find(entry.strength, 1, true) then
                        tier = entry.tier
                        break
                    end
                end
                if not tier then
                    tier = fallback_tier
                end
            end

            if tier then
                lockpick_found = true
                -- Append name to the tier's setting (comma-separated)
                local current = load_data[tier] or ""
                if current ~= "" then
                    load_data[tier] = current .. "," .. name
                else
                    load_data[tier] = name
                end
            else
                echo("I don't recognize the precision level of " .. name
                    .. ". Please send the LMAS APPRAISE information of this lockpick to Dreaven.")
            end
        end
    end
    -- result was nil or "not a lockpick" — skip

    -- Put the lockpick back in the container
    local container_id = settings.lockpick_container_id
    if container_id then
        while GameObj.right_hand() and GameObj.right_hand().name ~= "Empty" do
            waitrt()
            fput("put my " .. (GameObj.right_hand().name or "lockpick") .. " in #" .. container_id)
            pause(0.3)
        end
    end

    return tier, lockpick_found
end

---------------------------------------------------------------------------
-- M.scan_lockpicks(settings, all_pick_ids) — Scan all lockpicks in the lockpick
-- container, appraise each, and auto-assign to the correct tier setting.
-- Port of lines 1555-1609.
--
-- @param settings      Settings table with load_data.
-- @param all_pick_ids  tier_name → {id1, id2, ...} (reset and repopulated).
---------------------------------------------------------------------------
function M.scan_lockpicks(settings, all_pick_ids)
    local load_data = settings.load_data

    -- Clear all existing tier assignments
    for _, name in ipairs(data.LOCKPICK_NAMES) do
        load_data[name] = ""
    end

    waitrt()
    -- Stow anything in hands
    local rh = GameObj.right_hand()
    if rh and rh.name ~= "Empty" then
        fput("stow right")
    end
    local lh = GameObj.left_hand()
    if lh and lh.name ~= "Empty" then
        fput("stow left")
    end

    local lockpick_found = false
    local container_name = load_data["Lockpick Container"] or ""

    -- Find lockpick container in inventory
    local container = nil
    local inv = GameObj.inv()
    if inv then
        for _, item in ipairs(inv) do
            if item.name == container_name then
                container = item
                break
            end
        end
    end

    if not container then
        util.tpick_message(
            ";tpick: Could not find " .. container_name
            .. ", which you have listed as your 'Lockpick Container.'")
        return
    end

    -- Store container ID for appraise_lockpick to put picks back
    settings.lockpick_container_id = container.id

    -- Look in the container to populate its contents
    fput("look in #" .. container.id)
    pause(0.5)

    local contents = container.contents
    if contents then
        for _, item in ipairs(contents) do
            -- Get each item into hand
            while not GameObj.right_hand() or GameObj.right_hand().name == "Empty" do
                waitrt()
                fput("get #" .. item.id)
                pause(0.3)
            end
            local _, found = M.appraise_lockpick(item.name, settings)
            if found then
                lockpick_found = true
            end
        end
    end

    -- If no picks found via contents iteration, try parsing the container display
    -- (handles vambraces and containers that expose items differently)
    if not lockpick_found then
        local look_cmd
        if container_name:lower():find("vambrace") then
            look_cmd = "look in #" .. container.id
        else
            look_cmd = "look on #" .. container.id
        end

        local result = dothistimeout(look_cmd, 4, "you see|There is nothing on|There is nothing in")
        if result and string.find(result, "you see") then
            -- Parse XML-style exist= items from the look output
            for item_id, item_name in result:gmatch('exist="(%d+)" noun="[^"]*">([^<]+)</a>') do
                if item_id ~= container.id then
                    -- Get the item
                    while not GameObj.right_hand() or GameObj.right_hand().name == "Empty" do
                        waitrt()
                        fput("get #" .. item_id)
                        pause(0.3)
                    end
                    local _, found = M.appraise_lockpick(item_name, settings)
                    if found then
                        lockpick_found = true
                    end
                end
            end
        end
    end

    -- Remove trailing commas from each tier's pick list
    for _, name in ipairs(data.LOCKPICK_NAMES) do
        local val = load_data[name] or ""
        -- Remove leading/trailing commas
        val = val:gsub("^,", ""):gsub(",$", "")
        load_data[name] = val
    end

    echo("Finished scanning your lockpicks.")
end

---------------------------------------------------------------------------
-- M.find_gnomish_lockpick(vars, settings) — Find and use a lockpick from a
-- gnomish bracer (special equipment). Spins until the needed pick appears.
-- Port of lines 4039-4070.
--
-- @param vars      Picking state table.
-- @param settings  Settings table.
-- @return true if pick found, nil otherwise.
---------------------------------------------------------------------------
function M.find_gnomish_lockpick(vars, settings)
    local bracer_name = vars["Gnomish Bracers"]
    if not bracer_name then return nil end

    local found_pick = nil
    local spin_number = 0
    local needed_pick = vars["Needed Pick"] or ""

    -- First try: TURN
    waitrt()
    fput("turn my " .. bracer_name)
    while true do
        local line = get()
        if line and string.find(line, "^You spin your") then
            if string.find(line, needed_pick, 1, true) then
                found_pick = true
            end
            break
        end
    end

    -- If not found, keep spinning (up to 20 times)
    if not found_pick then
        while true do
            spin_number = spin_number + 1
            waitrt()
            fput("spin my " .. bracer_name)
            while true do
                local line = get()
                if line and string.find(line, "^You spin your") then
                    if string.find(line, needed_pick, 1, true) then
                        found_pick = true
                    end
                    break
                end
            end
            if found_pick or spin_number > 20 then
                break
            end
        end
    end

    if spin_number > 20 then
        util.tpick_silent(true,
            "Couldn't find the lockpick needed to pick this lock in your " .. bracer_name .. ".",
            settings)
        -- Escalate to next pick tier
        vars["Next Task"] = "next_pick"
        return nil
    else
        -- Pick found — proceed to pick_3
        vars["Next Task"] = "pick_3"
        return true
    end
end

---------------------------------------------------------------------------
-- M.get_pick_tier_from_precision(precision, strength) — Determine lockpick
-- tier from LMAS APPRAISE precision and strength text.
-- Utility used by appraise_lockpick.
--
-- @param precision  Precision text from appraise result (e.g. "detrimental").
-- @param strength   Strength text from appraise result (e.g. "incredibly strong").
-- @return tier_name  The material tier name, or nil if unrecognized.
---------------------------------------------------------------------------
function M.get_pick_tier_from_precision(precision, strength)
    if not precision then return nil end
    local p_lower = precision:lower()

    -- Simple precision-only lookup
    local tier = PRECISION_TO_TIER[p_lower]
    if tier then return tier end

    -- Strength-dependent lookup
    local entries = PRECISION_STRENGTH_TIERS[p_lower]
    if entries then
        local fallback = nil
        for _, entry in ipairs(entries) do
            if entry.strength == nil then
                fallback = entry.tier
            elseif strength and strength:lower():find(entry.strength, 1, true) then
                return entry.tier
            end
        end
        return fallback
    end

    return nil
end

---------------------------------------------------------------------------
-- M.get_wire_order_numbers(settings) — Read the rogue guild toolbench sign
-- to learn wire order numbers and costs for each material.
-- Port of tpick.lic lines 4072-4093.
--
-- @param settings  Table with settings (used for navigation context).
-- @return repair_info  Table: material_name → { order_number, order_cost }
---------------------------------------------------------------------------
function M.get_wire_order_numbers(settings)
    -- Navigate out if inside a room with an 'out' exit
    if checkpaths and checkpaths("out") then
        fput("go out")
    end

    -- Navigate to rogue guild workshop / toolbench area
    local target = Room.current and Room.current.find_nearest_by_tag
        and Room.current.find_nearest_by_tag("rogue guild workshop")
    if not target then
        target = Room.current and Room.current.find_nearest_by_tag
            and Room.current.find_nearest_by_tag("rogue guild toolbenchs")
    end
    if target then
        Script.run("go2", { tostring(target) })
        wait_while(function() return running("go2") end)
    end

    fput("go toolbench")
    fput("read sign")

    local repair_info = {}
    while true do
        local line = get()
        if not line then break end
        -- Match: "1.) a thin copper wire     50"
        local order_num, material_name, order_cost = line:match("(%d+)%.%)%s+a thin (%a+) wire%s+(%d+)")
        if order_num and material_name and order_cost then
            repair_info[material_name] = {
                order_number = order_num,
                order_cost   = order_cost,
            }
        elseif line:find("a thin bar of vaalin") then
            break
        end
    end

    -- Move out of the toolbench room
    if checkpaths and checkpaths("out") then
        fput("go out")
    end

    return repair_info
end

---------------------------------------------------------------------------
-- M.repair(pick_id, material, vars, settings) — Repair a single broken
-- lockpick using LMAS REPAIR at the rogue guild toolbench.
-- Port of tpick.lic lines 5312-5344 (tpick_repair_lockpicks).
--
-- @param pick_id   Game object ID of the lockpick to check/repair.
-- @param material  Material name (e.g. "copper", "steel").
-- @param vars      Runtime state table.
-- @param settings  Settings table.
-- @return "repaired", "not_broken", "unrepairable", or nil on error.
---------------------------------------------------------------------------
function M.repair(pick_id, material, vars, settings)
    -- Check if the pick is actually broken
    local result = dothistimeout(
        "look #" .. pick_id, 1,
        { "The.*appears to be broken%.",
          "You see nothing unusual%.",
          "I could not find what you were referring to%.",
          "appears to be somewhat damaged" })

    if not result then
        return nil
    end

    -- Not broken or not found — skip
    if result:find("You see nothing unusual")
        or result:find("I could not find what you were referring to")
        or result:find("appears to be somewhat damaged") then
        return "not_broken"
    end

    -- It's broken — need to repair
    if not result:find("appears to be broken") then
        return nil
    end

    -- Ensure we have wire order info
    if not vars["Repair Info"] then
        vars["Repair Info"] = M.get_wire_order_numbers(settings)
    end

    local wire_info = vars["Repair Info"][material]
    if not wire_info then
        util.tpick_silent(true, "No wire order info found for material: " .. material, settings)
        return nil
    end

    -- Get the broken lockpick
    fput("get #" .. pick_id)

    -- Navigate out if in a sub-room
    if checkpaths and checkpaths("out") then
        fput("go out")
    end

    -- Go to bank, withdraw funds for the wire
    Script.run("go2", { "bank", "--disable-confirm" })
    wait_while(function() return running("go2") end)
    fput("depo all")
    fput("withdraw " .. wire_info.order_cost .. " silvers")

    -- Navigate to rogue guild workshop
    local target = Room.current and Room.current.find_nearest_by_tag
        and Room.current.find_nearest_by_tag("rogue guild workshop")
    if not target then
        target = Room.current and Room.current.find_nearest_by_tag
            and Room.current.find_nearest_by_tag("rogue guild toolbenchs")
    end
    if target then
        Script.run("go2", { tostring(target) })
        wait_while(function() return running("go2") end)
    end

    -- Enter toolbench and buy wire
    fput("go toolbench")
    waitrt()
    fput("order " .. wire_info.order_number)
    fput("buy")
    waitrt()

    -- Attempt the repair
    local repair_result = dothistimeout(
        "lmas repair #" .. pick_id, 2,
        { "cooling rapidly to form a tight bond",
          "but the broken tip refuses to work free" })

    if repair_result and repair_result:find("cooling rapidly to form a tight bond") then
        waitrt()
        -- Stow repaired pick back into lockpick container
        if vars["Lockpick Container"] then
            fput("put #" .. pick_id .. " in #" .. vars["Lockpick Container"].id)
        else
            fput("stow #" .. pick_id)
        end
        return "repaired"
    elseif repair_result and repair_result:find("but the broken tip refuses to work free") then
        util.tpick_silent(true, "This lockpick cannot be repaired.", settings)
        return "unrepairable"
    else
        util.tpick_silent(true, "Didn't recognize any game lines during repair.", settings)
        return nil
    end
end

---------------------------------------------------------------------------
-- M.repair_lockpicks_start(vars, settings) — Repair all broken lockpicks
-- in the broken lockpick container.
-- Port of tpick.lic lines 5859-5869 (repair_lockpicks_start).
--
-- @param vars      Runtime state table (contains all_pick_ids, all_repair_ids, etc.).
-- @param settings  Settings table.
---------------------------------------------------------------------------
function M.repair_lockpicks_start(vars, settings)
    if Stats.prof ~= "Rogue" then
        util.tpick_silent(true, "Only rogues can repair lockpicks.", settings)
        return
    end

    -- Stow anything in hands first
    util.tpick_put_stuff_away(vars, settings)

    local all_pick_ids = vars["All Pick IDs"] or {}
    local all_repair_ids = vars["All Repair IDs"] or {}
    local all_repair_names = vars["All Repair Names"] or {}
    local settings_pick_names = vars["Settings Pick Names"] or {}

    -- Populate repair IDs from broken lockpick container contents
    if vars["Broken Lockpick Container"] and vars["Broken Lockpick Container"].contents then
        for _, item in ipairs(vars["Broken Lockpick Container"].contents) do
            -- Match against pick names
            for name, names_list in pairs(settings_pick_names) do
                for _, pname in ipairs(names_list) do
                    if item.name == pname then
                        table.insert(all_pick_ids[name] or {}, item.id)
                        break
                    end
                end
            end
            -- Match against repair names
            for name, names_list in pairs(all_repair_names) do
                for _, rname in ipairs(names_list) do
                    if item.name == rname then
                        if not all_repair_ids[name] then
                            all_repair_ids[name] = {}
                        end
                        table.insert(all_repair_ids[name], item.id)
                        break
                    end
                end
            end
        end
    end

    -- Iterate over each repair material tier and repair broken picks
    for _, name in ipairs(data.REPAIR_NAMES) do
        local ids = all_repair_ids[name]
        if ids then
            -- Extract material from "Repair Copper" → "copper"
            local material = name:match("^Repair%s+(.+)$")
            if material then
                material = material:lower()
                for _, pick_id in ipairs(ids) do
                    M.repair(pick_id, material, vars, settings)
                end
            end
        end
    end

    -- Move out of the toolbench if still inside
    if checkroom and checkroom():lower():find("workbench") then
        fput("go out")
    end
end

return M
