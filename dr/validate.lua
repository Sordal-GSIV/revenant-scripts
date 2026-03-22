--- @revenant-script
--- name: validate
--- version: 1.0.0
--- author: rpherbig
--- original-authors: rpherbig, Etreu, Sheltim, many contributors (dr-scripts community)
--- game: dr
--- description: Validate character JSON settings files for correctness and common mistakes
--- tags: settings, validation, json, yaml
--- @lic-certified: complete 2026-03-19
---
--- Full port of validate.lic (Lich5) to Revenant Lua.
---
--- In Revenant, character settings are stored as JSON in profiles/:
---   profiles/{CharName}-setup.json
---   profiles/{CharName}-{file}.json  (for hunting_file_list entries)
---
--- Usage:
---   ;validate         - Run all validation checks
---   ;validate verbose - Show each check name as it runs

-------------------------------------------------------------------------------
-- Arg parsing
-------------------------------------------------------------------------------

local verbose = false
if Script.vars[1] and Script.vars[1]:lower():find("verbose") then
    verbose = true
end

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local warning_count = 0
local error_count = 0
local current_check = nil   -- shown in verbose mode when check produces a hit

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

--- Check if a value is nil or empty (nil, "", empty table).
local function is_empty(v)
    if v == nil then return true end
    if type(v) == "string" then return v == "" end
    if type(v) == "table" then return next(v) == nil end
    return false
end

--- Check if an array-like table contains a value.
local function contains(arr, val)
    if type(arr) ~= "table" then return false end
    for _, v in ipairs(arr) do
        if v == val then return true end
    end
    return false
end

--- Check if a hash table has the given key (non-nil value).
local function has_key(t, key)
    if type(t) ~= "table" then return false end
    return t[key] ~= nil
end

--- Return the keys of a table as an array.
local function keys(t)
    if type(t) ~= "table" then return {} end
    local r = {}
    for k in pairs(t) do table.insert(r, k) end
    return r
end

--- Array set-difference: elements in a not in b.
local function set_diff(a, b)
    if type(a) ~= "table" then return {} end
    if type(b) ~= "table" then return a end
    local bset = {}
    for _, v in ipairs(b) do bset[v] = true end
    local r = {}
    for _, v in ipairs(a) do
        if not bset[v] then table.insert(r, v) end
    end
    return r
end

--- Array intersection: elements in both a and b.
local function set_intersect(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return {} end
    local bset = {}
    for _, v in ipairs(b) do bset[v] = true end
    local r = {}
    for _, v in ipairs(a) do
        if bset[v] then table.insert(r, v) end
    end
    return r
end

--- Unique values in an array.
local function uniq(arr)
    if type(arr) ~= "table" then return {} end
    local seen = {}
    local r = {}
    for _, v in ipairs(arr) do
        if not seen[v] then seen[v] = true; table.insert(r, v) end
    end
    return r
end

--- Flatten one level of an array of arrays.
local function flatten(arr)
    if type(arr) ~= "table" then return {} end
    local r = {}
    for _, v in ipairs(arr) do
        if type(v) == "table" then
            for _, vv in ipairs(v) do table.insert(r, vv) end
        else
            table.insert(r, v)
        end
    end
    return r
end

--- Collect all values from a hash table into an array (shallow).
local function values(t)
    if type(t) ~= "table" then return {} end
    local r = {}
    for _, v in pairs(t) do table.insert(r, v) end
    return r
end

--- Check if value is an integer (number with no fractional part).
local function is_integer(v)
    return type(v) == "number" and math.floor(v) == v
end

--- Check if value is a hash/object (non-array table).
local function is_hash(v)
    if type(v) ~= "table" then return false end
    local count = 0
    for _ in pairs(v) do count = count + 1 end
    if count == 0 then return true end -- empty table treated as hash
    return v[1] == nil  -- no integer key 1 → not an array
end

--- Match a skill name against a valid skill pattern (case-insensitive full match).
--- Some valid skill patterns use regex features (alternation, wildcards).
local function matches_skill_pattern(skill, pattern)
    local ok, re = pcall(Regex.new, "(?i)^" .. pattern .. "$")
    if ok and re then
        return re:test(skill)
    end
    -- fallback: case-insensitive plain match
    return skill:lower() == pattern:lower()
end

--- Find a gear entry matching an item description string.
--- item_desc matches /#{adjective}\s*#{name}/i against gear entries.
local function gear_matches_item(gear_arr, item_desc)
    if type(gear_arr) ~= "table" or type(item_desc) ~= "string" then return false end
    for _, data in ipairs(gear_arr) do
        if type(data) == "table" then
            local adj = tostring(data.adjective or data["adjective"] or "")
            local nm  = tostring(data.name or data["name"] or "")
            if adj ~= "" and nm ~= "" then
                local ok, re = pcall(Regex.new, "(?i)" .. adj .. "\\s*" .. nm)
                if ok and re and re:test(item_desc) then return true end
            elseif nm ~= "" then
                local ok, re = pcall(Regex.new, "(?i)\\b" .. nm .. "\\b")
                if ok and re and re:test(item_desc) then return true end
            end
        end
    end
    return false
end

-------------------------------------------------------------------------------
-- Reporting
-------------------------------------------------------------------------------

local function warn(message)
    if verbose and current_check then
        echo("  " .. current_check)
        current_check = nil
    end
    echo("WARNING:< " .. message .. "  >")
    warning_count = warning_count + 1
end

local function report_error(message)   -- 'error' is a Lua builtin
    if verbose and current_check then
        echo("  " .. current_check)
        current_check = nil
    end
    echo("ERROR:< " .. message .. "  >")
    error_count = error_count + 1
end

-------------------------------------------------------------------------------
-- Valid-data tables (mirrors DRYamlValidator#setup_data)
-------------------------------------------------------------------------------

local valid_astrology_keys    = {"ways", "observe", "rtr", "weather", "events", "attunement"}
local valid_thrown_skills     = {"Heavy Thrown", "Light Thrown"}
local valid_aimed_skills      = {"Bow", "Slings", "Crossbow"}
local valid_ranged_skills     = {}
for _, s in ipairs(valid_thrown_skills) do table.insert(valid_ranged_skills, s) end
for _, s in ipairs(valid_aimed_skills)  do table.insert(valid_ranged_skills, s) end

local valid_melee_skills = {
    "Offhand Weapon", "Brawling", "Polearms", "Large Blunt", "Twohanded Blunt",
    "Staves", "Small Blunt", "Small Edged", "Large Edged", "Twohanded Edged",
}
local valid_weapon_skills = {}
for _, s in ipairs(valid_ranged_skills) do table.insert(valid_weapon_skills, s) end
for _, s in ipairs(valid_melee_skills)  do table.insert(valid_weapon_skills, s) end
table.insert(valid_weapon_skills, "Targeted Magic")

-- summoned weapons: ranged + melee minus Offhand Weapon and Brawling
local valid_summon_skills = {}
for _, s in ipairs(valid_thrown_skills) do table.insert(valid_summon_skills, s) end
for _, s in ipairs(valid_melee_skills) do
    if s ~= "Offhand Weapon" and s ~= "Brawling" then
        table.insert(valid_summon_skills, s)
    end
end

local valid_research_skills = {
    "Arcana", "Life Magic", "Holy Magic", "Lunar Magic", "Elemental Magic",
    "Arcane Magic", "Attunement", "Warding", "Augmentation", "Utility",
}
local valid_defensive_skills = {"Shield Usage", "Parry Ability", "Evasion"}
local valid_caravan_skills = {
    "Attunement", "Warding", "Augmentation", "Utility", "Scholarship", "Appraisal",
    "Perception", "Locksmithing", "First Aid", "Outfitting", "Engineering",
    "Performance", "Outdoorsmanship", "Athletics", "Forging",
}

local all_skills = {
    "Instinct", "Evasion", "Athletics", "Stealth", "Perception", "Locksmithing",
    "First Aid", "Skinning", "Outdoorsmanship", "Thievery", "Backstab", "Thanatology",
    "Forging", "Outfitting", "Engineering", "Alchemy", "Scholarship", "Appraisal",
    "Tactics", "Performance", "Empathy", "Trading", "Attunement", "Arcana",
    "Targeted Magic", "Debilitation", "Warding", "Augmentation", "Utility", "Sorcery",
    "Summoning", "Astrology", "Theurgy", "Inner Magic", "Inner Fire", "Melee Mastery",
    "Missile Mastery", "Parry Ability", "Small Edged", "Large Edged", "Twohanded Edged",
    "Twohanded Blunt", "Small Blunt", "Large Blunt", "Bow", "Slings", "Crossbow",
    "Polearms", "Heavy Thrown", "Offhand Weapon", "Brawling", "Light Thrown", "Staves",
    "Expertise", "Defending", "Shield Usage", "Light Armor", "Chain Armor", "Brigandine",
    "Plate Armor", "Conviction", "Life Magic", "Holy Magic", "Lunar Magic",
    "Elemental Magic", "Arcane Magic", "Enchanting",
}

local neutral_aspects = {
    "Everild", "Kertigen", "Damaris", "Tamsine", "Meraud", "Truffenyi",
    "Glythtide", "Chadatru", "Faenella", "Hodierna", "Eluned", "Hav'roth", "Urrem'tier",
}

local training_ability_patterns = {
    "Almanac", "Ambush Choke", "Ambush Stun", "Analyze", "App Bundle",
    "App Careful", "App Pouch", "App Quick", "App", "Astro",
    "Barb Research Augmentation", "Barb Research Utility", "Barb Research Warding",
    "Charged Maneuver", "Collect", "Favor Orb", "Flee", "Herbs", "Hunt",
    "Khri Prowess", "Locks", "Meraud", "Perc Health", "Perc", "PercMana",
    "Pray", "PrayerMat", "Recall", "(Ret|Retreat) Stealth", "Scream",
    "Smite", "Stealth", "Summon .* Domain", "Tactics", "Teach", "Tessera",
}

-------------------------------------------------------------------------------
-- Custom scripts check (mirrors DRYamlValidator#warn_custom_scripts)
-------------------------------------------------------------------------------

local function warn_custom_scripts()
    -- In Revenant, check for a dr/custom/ override directory.
    -- If it exists, warn about any scripts that shadow curated dr/ scripts.
    local custom_dir = "dr/custom"
    if not File.is_dir(custom_dir) then return end

    local custom_files = File.list(custom_dir) or {}
    local curated_files = File.list("dr") or {}

    local curated_set = {}
    for _, f in ipairs(curated_files) do
        if not File.is_dir("dr/" .. f) and not f:find("^%.") then
            curated_set[f] = true
        end
    end

    local include_list = {}
    for _, f in ipairs(custom_files) do
        if not File.is_dir(custom_dir .. "/" .. f) and not f:find("^%.") then
            if curated_set[f] then
                table.insert(include_list, f)
            end
        end
    end

    if #include_list > 0 then
        respond("")
        respond("  NOTE: The following curated scripts are in your custom folder and will not receive updates.")
        respond("  " .. table.concat(include_list, ", "))
    end
end

-------------------------------------------------------------------------------
-- Helper: load settings for a specific file suffix (e.g. "hunt")
-------------------------------------------------------------------------------

local function load_settings_for_file(charname, suffix)
    -- Delegate to global get_settings with an additional suffix.
    -- get_settings() from dependency merges base + character files.
    local ok, settings = pcall(get_settings, {suffix})
    if ok and type(settings) == "table" then return settings end
    return nil
end

-------------------------------------------------------------------------------
-- Assertions (mirrors DRYamlValidator instance methods)
-------------------------------------------------------------------------------

local assertions = {}

assertions[#assertions+1] = {
    name = "assert_that_root_keys_exist",
    fn = function(settings)
        for _, key in ipairs({"weapon_training", "crossing_training", "hunting_info", "gear", "gear_sets"}) do
            if settings[key] == nil then
                warn("You are missing a setting that is probably needed: " .. key)
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_weapon_training_has_skills",
    fn = function(settings)
        if settings.weapon_training and is_empty(settings.weapon_training) then
            warn("You have no weapons configured in weapon_training: this will likely cause problems.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_dual_load_and_charged_maneuvers_bows_do_not_coexist",
    fn = function(settings)
        if settings.dual_load and type(settings.charged_maneuvers) == "table"
           and has_key(settings.charged_maneuvers, "Bow") then
            report_error("dual_load: true is not compatible with using charged_maneuvers with Bows! Set dual_load to false or configure charged_maneuvers without Bows")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_cyclic_no_release_spell_is_invalid_unless_listed_in_base_spells",
    fn = function(settings)
        if not settings.cyclic_no_release then return end
        local spell_data = get_data("spells")
        local sd = (type(spell_data) == "table" and spell_data.spell_data) or {}
        for _, spell_name in ipairs(settings.cyclic_no_release) do
            if not has_key(sd, spell_name) then
                report_error(tostring(spell_name) .. " in cyclic_no_release is not a valid spell name.")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_holy_weapon_charging_has_valid_hometown_unless_using_icon",
    fn = function(settings)
        if not DRStats.paladin() then return end
        local hw = settings.holy_weapon
        if type(hw) ~= "table" or not hw.weapon_name then return end
        local ht = tostring(settings.hometown or "")
        if ht:find("Crossing") or ht:find("Shard") then return end
        if type(hw.icon_name) == "string" and hw.icon_name ~= "" then return end
        report_error("Only Crossing and Shard Chadatru altars are valid for charging a holy weapon without an icon.")
    end
}

assertions[#assertions+1] = {
    name = "assert_that_appraisal_training_settings_are_valid",
    fn = function(settings)
        if is_empty(settings.appraisal_training) then return end
        local valid = {"pouches", "zills", "art", "gear", "bundle"}
        local bad = set_diff(settings.appraisal_training, valid)
        if not is_empty(bad) then
            warn("You have the following invalid appraisal_training settings: " ..
                 table.concat(bad, ", ") .. "\nValid appraisal_training settings are: " ..
                 table.concat(valid, ", "))
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_low_value_gem_pouch_settings_are_valid",
    fn = function(settings)
        if not settings.gem_pouch_low_value then return end
        if is_empty(settings.low_value_gem_pouch_container) then
            report_error("gem_pouch_low_value defined, but no low_value_gem_pouch_container for low value pouches to go into")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_gear_has_deprecated_is_leather_entry",
    fn = function(settings)
        if type(settings.gear) ~= "table" then return end
        for _, item in ipairs(settings.gear) do
            if type(item) == "table" and (item.is_leather or item["is_leather"]) then
                warn("Gear entry " .. tostring(item.name or item["name"] or "(unknown)") ..
                     " has deprecated is_leather setting.")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_gear_has_incorrect_worn_entry",
    fn = function(settings)
        if type(settings.gear) ~= "table" then return end
        for _, item in ipairs(settings.gear) do
            if type(item) == "table" and (item.worn or item["worn"]) then
                report_error("Gear entry " .. tostring(item.name or item["name"] or "(unknown)") ..
                             " has incorrect worn setting. The correct setting name is is_worn.")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_sorcery_is_dangerous",
    fn = function(settings)
        if not settings.crafting_training_spells_enable_sorcery then return end
        if settings.crafting_training_spells_enable_sorcery_squelch_warning then return end
        warn("You have Sorcery casting whilst crafting, check JUSTICE in your crafting room")
        warn("Set crafting_training_spells_enable_sorcery_squelch_warning: true to make this message go away")
    end
}

assertions[#assertions+1] = {
    name = "assert_that_pouch_appraisal_has_defined_container",
    fn = function(settings)
        if type(settings.appraisal_training) ~= "table" then return end
        if not contains(settings.appraisal_training, "pouches") then return end
        if settings.full_pouch_container then return end
        warn("Must have full_pouch_container defined if training appraisal with pouches")
    end
}

assertions[#assertions+1] = {
    name = "assert_that_empty_pouch_container_is_different_than_full_pouch_container",
    fn = function(settings)
        if not settings.full_pouch_container then return end
        if settings.full_pouch_container == settings.spare_gem_pouch_container then
            warn("Full pouch container cannot be the same as the spare pouch container")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_aspects_are_neutral_if_not_using_altars",
    fn = function(settings)
        if settings.use_favor_altars then return end
        if not settings.favor_god then return end
        local god = tostring(settings.favor_god):sub(1,1):upper() ..
                    tostring(settings.favor_god):sub(2)
        if not contains(neutral_aspects, god) then
            report_error("The favor_god: " .. tostring(settings.favor_god) ..
                         " you have set requires use_favor_altars: true, only neutral aspects can use the puzzle for orbs")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_theurgy_prayer_mat_room_should_be_an_int_and_warn_about_deprecation",
    fn = function(settings)
        if not settings.theurgy_use_prayer_mat then return end
        local room = settings.theurgy_prayer_mat_room
        if is_integer(room) then return end
        if type(room) == "table" and room.id ~= nil then
            warn("theurgy_prayer_mat_room is set as a key value pair id: " .. tostring(room.id) ..
                 " this is deprecated. It should be set as a room number \"theurgy_prayer_mat_room: " ..
                 tostring(room.id) .. "\" ")
        else
            warn("theurgy_prayer_mat_room does not contain valid settings. A valid setting looks like \"theurgy_prayer_mat_room: 1900\"")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_hometown_has_altar_if_using_altars",
    fn = function(settings)
        if not settings.use_favor_altars then return end
        if (settings.favor_goal or 0) == 0 then return end
        if not settings.hometown then return end
        local theurgy_data = get_data("theurgy")
        local town_entry = type(theurgy_data) == "table" and theurgy_data[settings.hometown]
        if not (type(town_entry) == "table" and type(town_entry.favor_altars) == "table") then
            warn("Could not find theurgy data for hometown: " .. tostring(settings.hometown))
            return
        end
        if not settings.favor_god then return end
        local god = tostring(settings.favor_god):sub(1,1):upper() .. tostring(settings.favor_god):sub(2)
        if not has_key(town_entry.favor_altars, god) then
            warn("The favor_god: " .. tostring(settings.favor_god) ..
                 " you have set does not have a favor altar in your hometown: " ..
                 tostring(settings.hometown) ..
                 ".  You will not be able to get favors if you fall below your favor_goal.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_water_holder_is_set_when_using_altars",
    fn = function(settings)
        if not settings.use_favor_altars then return end
        if settings.water_holder then return end
        report_error("water_holder: must be defined in your yaml to use favor_altars. ex: water_holder: chalice")
    end
}

assertions[#assertions+1] = {
    name = "assert_that_almanac_skills_are_skills",
    fn = function(settings)
        if not settings.almanac_skills then return end
        for _, skill_name in ipairs(settings.almanac_skills) do
            if not contains(all_skills, skill_name) then
                report_error("Invalid almanac_skills: skill name '" .. tostring(skill_name) ..
                             "'. Valid skills are '" .. table.concat(all_skills, ", ") .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_weapon_training_are_skills",
    fn = function(settings)
        if not settings.weapon_training then return end
        for skill_name in pairs(settings.weapon_training) do
            if not contains(valid_weapon_skills, skill_name) then
                report_error("Invalid weapon_training: skill name '" .. tostring(skill_name) ..
                             "'. Valid skills are '" .. table.concat(valid_weapon_skills, ", ") .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_dance_skill_is_skill",
    fn = function(settings)
        if not settings.dance_skill then return end
        if not contains(valid_melee_skills, settings.dance_skill) then
            report_error("dance_skill: skill name '" .. tostring(settings.dance_skill) ..
                         "' is not valid. Valid skills are '" .. table.concat(valid_melee_skills, ", ") .. "'")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_priority_weapons_are_skills",
    fn = function(settings)
        if not settings.priority_weapons then return end
        for _, skill_name in ipairs(settings.priority_weapons) do
            if not contains(valid_weapon_skills, skill_name) then
                report_error("Invalid priority_weapons: skill name '" .. tostring(skill_name) ..
                             "'. Valid skills are '" .. table.concat(valid_weapon_skills, ", ") .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_combat_spell_training_spells_are_skills",
    fn = function(settings)
        if not settings.combat_spell_training then return end
        local valid = {"Augmentation", "Sorcery", "Utility", "Warding", "Debilitation", "Targeted Magic"}
        for skill_name in pairs(settings.combat_spell_training) do
            if not contains(valid, skill_name) then
                report_error("Invalid combat_spell_training: skill name '" .. tostring(skill_name) ..
                             "'. Valid skill names are '" .. table.concat(valid, ", ") .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crafting_training_spells_are_skills",
    fn = function(settings)
        if not settings.crafting_training_spells then return end
        local valid = {"Augmentation", "Utility", "Warding"}
        if settings.crafting_training_spells_enable_sorcery then
            table.insert(valid, "Sorcery")
        end
        for skill_name in pairs(settings.crafting_training_spells) do
            if not contains(valid, skill_name) then
                report_error("Invalid crafting_training_spells: skill name '" .. tostring(skill_name) ..
                             "'. Valid skill names are '" .. table.concat(valid, ", ") .. "'")
            end
        end
        if has_key(settings.crafting_training_spells, "Sorcery") and
           not settings.crafting_training_spells_enable_sorcery then
            warn("To remove this error, remove Sorcery from crafting_training_spells, or set crafting_training_spells_enable_sorcery: true")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crafting_training_spells_have_no_cambrinth",
    fn = function(settings)
        if not settings.crafting_training_spells then return end
        for spell_name, data in pairs(settings.crafting_training_spells) do
            if type(data) == "table" and data.cambrinth then
                warn(tostring(spell_name) .. " in crafting_training_spells uses cambrinth which increases crafting time, you may want to remove it.")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_cycle_armors_are_skills",
    fn = function(settings)
        if not settings.cycle_armors then return end
        local valid = {"Light Armor", "Chain Armor", "Brigandine", "Plate Armor"}
        for _, skill in ipairs(settings.cycle_armors) do
            if not contains(valid, skill) then
                report_error("Skill name in cycle_armors is not valid: " .. tostring(skill))
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_slivers_includes_tk_ammo",
    fn = function(settings)
        if type(settings.offensive_spells) ~= "table" then return end
        local has_slivers = false
        for _, spell_info in ipairs(settings.offensive_spells) do
            if type(spell_info) == "table" and spell_info.slivers then
                has_slivers = true; break
            end
        end
        if not has_slivers then return end
        if settings.tk_ammo then return end
        warn("You are using slivers for Telekenetic spells but have no backup tk_ammo! If there are no moons, you will not cast the spell!")
    end
}

assertions[#assertions+1] = {
    name = "assert_that_summoned_weapons_are_skills",
    fn = function(settings)
        if not settings.summoned_weapons then return end
        for _, info in ipairs(settings.summoned_weapons) do
            if type(info) == "table" and not contains(valid_summon_skills, info.name or info["name"]) then
                report_error("Invalid summoned_weapons: skill name '" .. tostring(info.name or info["name"]) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_summoned_weapons_are_in_weapon_training",
    fn = function(settings)
        if not settings.summoned_weapons then return end
        if not settings.weapon_training then return end
        for _, info in ipairs(settings.summoned_weapons) do
            if type(info) == "table" then
                local nm = info.name or info["name"]
                if not has_key(settings.weapon_training, nm) then
                    warn("A summoned_weapons: skill name '" .. tostring(nm) .. "' is not in weapon_training:")
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_stop_on_skills_are_valid",
    fn = function(settings)
        if type(settings.hunting_info) ~= "table" then return end
        for _, info in ipairs(settings.hunting_info) do
            if type(info) == "table" and type(info.stop_on) == "table" then
                local bad = set_diff(info.stop_on, all_skills)
                if not is_empty(bad) then
                    report_error("stop_on: skills not recognized as valid skills '" ..
                                 table.concat(bad, ", ") .. "'")
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_stop_on_weapon_skills_are_in_weapon_training",
    fn = function(settings)
        if type(settings.hunting_info) ~= "table" then return end
        if not settings.weapon_training then return end
        local stop_ons = {}
        for _, info in ipairs(settings.hunting_info) do
            if type(info) == "table" and type(info.stop_on) == "table" then
                for _, s in ipairs(info.stop_on) do
                    table.insert(stop_ons, s)
                end
            end
        end
        local wt_keys = keys(settings.weapon_training)
        for _, skill in ipairs(uniq(stop_ons)) do
            if contains(valid_weapon_skills, skill) and skill ~= "Targeted Magic" then
                if not contains(wt_keys, skill) then
                    report_error("stop_on: weapon skill " .. tostring(skill) .. " not in weapon_training: setting")
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_hunting_info_has_duration_or_stop_on",
    fn = function(settings)
        if type(settings.hunting_info) ~= "table" then return end
        for _, info in ipairs(settings.hunting_info) do
            if type(info) == "table" then
                if info.duration == nil and info.stop_on == nil and info.stop_on_low == nil then
                    report_error("Must have at least one of :duration or stop_on or stop_on_low for hunting_info '" ..
                                 tostring(info.zone or "(unknown zone)") .. "'")
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_priority_skills_exists_if_hunting_priority",
    fn = function(settings)
        if not settings.training_manager_hunting_priority then return end
        if is_empty(settings.training_manager_priority_skills) then
            report_error("training_manager_hunting_priority is true, but no training_manager_priority_skills were set")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_priority_skills_skills_are_valid",
    fn = function(settings)
        if type(settings.hunting_info) ~= "table" then return end
        if not settings.training_manager_priority_skills then return end
        for _, skill in ipairs(settings.training_manager_priority_skills) do
            if not contains(all_skills, skill) then
                report_error("Invalid training_manager_priority_skills: skill name '" .. tostring(skill) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_priority_defense_skill_is_valid",
    fn = function(settings)
        if not settings.priority_defense then return end
        if not contains(valid_defensive_skills, settings.priority_defense) then
            report_error("Invalid priority_defense skill: skill name '" .. tostring(settings.priority_defense) .. "'")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_hunting_info_has_zones",
    fn = function(settings)
        if type(settings.hunting_info) ~= "table" then return end
        for i, info in ipairs(settings.hunting_info) do
            if type(info) == "table" and info.zone == nil then
                report_error("Hunting info at index '" .. tostring(i) .. "' had no zone.")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_hunting_info_zones_are_in_hunting_or_escort_zones",
    fn = function(settings)
        if type(settings.hunting_info) ~= "table" then return end
        local hunting_data = get_data("hunting")
        local hunting_zones = (type(hunting_data) == "table" and hunting_data.hunting_zones) or {}
        local escort_zones  = (type(hunting_data) == "table" and hunting_data.escort_zones) or {}
        local custom_zones  = settings.custom_hunting_zones or {}

        local zone_names = {}
        for _, info in ipairs(settings.hunting_info) do
            if type(info) == "table" and info.zone ~= nil then
                if type(info.zone) == "table" then
                    for _, z in ipairs(info.zone) do table.insert(zone_names, z) end
                else
                    table.insert(zone_names, info.zone)
                end
            end
        end

        for _, name in ipairs(zone_names) do
            local ok = false
            if type(hunting_zones) == "table" then
                if has_key(hunting_zones, name) or contains(hunting_zones, name) then ok = true end
            end
            if not ok and type(escort_zones) == "table" then
                if has_key(escort_zones, name) or contains(escort_zones, name) then ok = true end
            end
            if not ok and type(custom_zones) == "table" then
                if has_key(custom_zones, name) or contains(custom_zones, name) then ok = true end
            end
            if not ok then
                report_error("Hunting zone not found in hunting_zones, escort_zones, or custom-defined zones. '" .. tostring(name) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_gear_sets_not_nil",
    fn = function(settings)
        if not settings.gear_sets then return end
        for name, items in pairs(settings.gear_sets) do
            if items == nil then
                report_error("gear_set: '" .. tostring(name) .. "' is nil, an empty gear set should be " .. tostring(name) .. ": []")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_gear_sets_has_standard",
    fn = function(settings)
        if not settings.gear_sets then return end
        if not has_key(settings.gear_sets, "standard") then
            warn("a 'standard' gear_set: entry is required for combat-trainer to function.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_gear_sets_has_stealing_if_training_thievery",
    fn = function(settings)
        if not settings.gear_sets then return end
        if not (type(settings.crossing_training) == "table" and contains(settings.crossing_training, "Thievery")) then return end
        if not has_key(settings.gear_sets, "stealing") then
            warn("a 'stealing' gear_set: entry is required when training Thievery.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crafting_magic_exist_if_crafting_and_caster",
    fn = function(settings)
        if settings.crafting_training_spells then return end
        if type(settings.crossing_training) ~= "table" then return end
        if DRStats.thief() or DRStats.barbarian() then return end
        local crafting_skills = {"Outfitting", "Forging", "Alchemy", "Engineering"}
        for _, skill in ipairs(settings.crossing_training) do
            if contains(crafting_skills, skill) then
                warn("You are a magic user and have " .. skill ..
                     " in crossing_training but do not have crafting_training_spells set up. You may want to consider adding it.")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_not_feinting_with_offhand",
    fn = function(settings)
        if settings.dance_skill ~= "Offhand Weapon" then return end
        local function has_feint(arr)
            if type(arr) ~= "table" then return false end
            for _, v in ipairs(arr) do
                if type(v) == "string" and v:lower():find("feint") then return true end
            end
            return false
        end
        if has_feint(settings.dance_actions) or has_feint(settings.dance_actions_stealth) then
            report_error("Feint in your actions list will cause an error when Offhand Weapon is your dance skill")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_no_research_only_skills_if_research_is_off",
    fn = function(settings)
        if settings.use_research then return end
        if type(settings.crossing_training) ~= "table" then return end
        local research_only = {"Life Magic", "Holy Magic", "Lunar Magic", "Elemental Magic", "Arcane Magic"}
        for _, skill in ipairs(settings.crossing_training) do
            if contains(research_only, skill) then
                report_error("You have a research only skill '" .. skill ..
                             "' listed in crossing_training but research is disabled")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_all_research_skills_are_in_crossing_training",
    fn = function(settings)
        if not settings.use_research then return end
        if type(settings.crossing_training) ~= "table" then return end
        if not settings.research_skills then return end
        for _, skill in ipairs(settings.research_skills) do
            if not contains(settings.crossing_training, skill) then
                report_error("Skill in research_skills could not be found in crossing_training. '" .. tostring(skill) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_all_research_skills_are_valid",
    fn = function(settings)
        if not settings.use_research then return end
        if type(settings.crossing_training) ~= "table" then return end
        if not settings.research_skills then return end
        for _, skill in ipairs(settings.research_skills) do
            if not contains(valid_research_skills, skill) then
                report_error("Skill in research_skills was not a valid research skill. '" .. tostring(skill) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crossing_training_skills_are_valid",
    fn = function(settings)
        if type(settings.crossing_training) ~= "table" then return end
        for _, skill in ipairs(settings.crossing_training) do
            if not contains(all_skills, skill) then
                report_error("Invalid crossing_training: skill name '" .. tostring(skill) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crossing_training_requires_movement_skills_are_valid",
    fn = function(settings)
        if type(settings.crossing_training_requires_movement) ~= "table" then return end
        for _, skill in ipairs(settings.crossing_training_requires_movement) do
            if not contains(all_skills, skill) then
                report_error("Invalid crossing_training_requires_movement: skill name '" .. tostring(skill) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_train_workorders_are_valid",
    fn = function(settings)
        if not settings.train_workorders then return end
        local valid = {"Blacksmithing", "Weaponsmithing", "Tailoring", "Carving", "Shaping", "Remedies", "Artificing"}
        for _, discipline in ipairs(settings.train_workorders) do
            if not contains(valid, discipline) then
                report_error("Invalid train_workorders: discipline name '" .. tostring(discipline) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_mines_to_mine_are_in_mining_buddy_rooms",
    fn = function(settings)
        if not settings.mines_to_mine then return end
        local mining_data = get_data("mining")
        local mining_rooms = (type(mining_data) == "table" and mining_data.mining_buddy_rooms) or {}
        for _, mine in ipairs(settings.mines_to_mine) do
            if not contains(mining_rooms, mine) and not has_key(mining_rooms, mine) then
                report_error("Mine in mines_to_mine could not be found in mining_buddy_rooms. '" .. tostring(mine) .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_gear_sets_contain_described_items",
    fn = function(settings)
        if not settings.gear_sets then return end
        if type(settings.gear) ~= "table" then return end
        local all_items = uniq(flatten(values(settings.gear_sets)))
        for _, item in ipairs(all_items) do
            if type(item) == "string" and not gear_matches_item(settings.gear, item) then
                report_error("Item in gear_set could not be found in gear listings. '" .. item .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_weapon_training_weapons_in_gear",
    fn = function(settings)
        if not settings.weapon_training then return end
        if type(settings.gear) ~= "table" then return end
        for skill, item in pairs(settings.weapon_training) do
            if type(item) == "string" and item ~= "" then
                if not gear_matches_item(settings.gear, item) then
                    -- Check if it's a summoned weapon
                    local is_summoned = false
                    if type(settings.summoned_weapons) == "table" then
                        for _, sw in ipairs(settings.summoned_weapons) do
                            if type(sw) == "table" and (sw.name or sw["name"]) == skill then
                                is_summoned = true; break
                            end
                        end
                    end
                    if not is_summoned then
                        report_error("Item in weapon_training could not be found in gear listings. '" ..
                                     tostring(skill) .. ": " .. tostring(item) .. "'")
                    end
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_barb_famine_healing_has_both_required_settings",
    fn = function(settings)
        if is_empty(settings.barb_famine_healing) then return end
        local bfh = settings.barb_famine_healing
        if type(bfh) ~= "table" then return end
        if bfh.health_threshold == nil or bfh.inner_fire_threshold == nil then
            report_error("barb_famine_healing requires a health_threshold and inner_fire_threshold. Please check the base.yaml or the lich repo settings wiki for details.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_minimum_whirlwind_trainables",
    fn = function(settings)
        if not settings.whirlwind_trainables then return end
        if type(settings.whirlwind_trainables) == "table" and #settings.whirlwind_trainables < 2 then
            report_error("Whirlwinding requires a minimum of two one-handed template weapons!")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_whirlwind_trainables_are_in_weapon_training",
    fn = function(settings)
        if not (settings.weapon_training and settings.whirlwind_trainables) then return end
        for _, desc in ipairs(settings.whirlwind_trainables) do
            local found = false
            for _, v in pairs(settings.weapon_training) do
                if v == desc then found = true; break end
            end
            if found then
                report_error("Weapon skill '" .. tostring(desc) ..
                             "' not found in weapon_training! All whirlwind_trainables need to also be listed in weapon_training.")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_whirlwind_trainables_are_not_swappables",
    fn = function(settings)
        if is_empty(settings.whirlwind_trainables) then return end
        if type(settings.weapon_training) ~= "table" then return end
        if type(settings.gear) ~= "table" then return end
        for weapon_skill, desc in pairs(settings.weapon_training) do
            if contains(settings.whirlwind_trainables, weapon_skill) or
               contains(settings.whirlwind_trainables, desc) then
                for _, gear_data in ipairs(settings.gear) do
                    if type(gear_data) == "table" and gear_matches_item({gear_data}, desc) then
                        if gear_data.swappable or gear_data["swappable"] then
                            report_error("The listed weapon, " .. tostring(desc) ..
                                         ", is a swappable! We don't support the use of swappable weapons during whirlwind training.")
                        end
                    end
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_training_abilities_are_valid",
    fn = function(settings)
        if not settings.training_abilities then return end
        for skill in pairs(settings.training_abilities) do
            local valid = false
            for _, pat in ipairs(training_ability_patterns) do
                if matches_skill_pattern(tostring(skill), pat) then
                    valid = true; break
                end
            end
            if not valid then
                report_error("Ability in training_abilities is not valid: " .. tostring(skill))
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_pet_source_is_defined_for_locks",
    fn = function(settings)
        if not settings.training_abilities then return end
        if not settings.training_abilities["Locks"] then return end
        if not settings.picking_pet_box_source then
            report_error("You must have a picking_pet_box_source: to use Locks in training_abilities")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_dance_skill_in_weapon_training",
    fn = function(settings)
        if not settings.weapon_training then return end
        if not settings.dance_skill then return end
        if settings.dynamic_dance_skill then return end
        if not has_key(settings.weapon_training, settings.dance_skill) then
            report_error("Dance skill '" .. tostring(settings.dance_skill) ..
                         "' must be in weapon_training if you're not using dynamic_dance_skill")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_necro_ritual_is_valid",
    fn = function(settings)
        if not settings.thanatology then return end
        if type(settings.thanatology) ~= "table" then return end
        if not settings.thanatology.ritual_type then return end
        local valid = {"preserve", "harvest", "fetish", "cut", "dissect", "consume", "arise", "cycle", "butcher"}
        if not contains(valid, settings.thanatology.ritual_type) then
            report_error("thanatology['ritual_type']: '" .. tostring(settings.thanatology.ritual_type) ..
                         "' is invalid, only [preserve, harvest, fetish, cut, dissect, consume, arise, and cycle] are supported at this time.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_safe_room_necro_has_valid_container",
    fn = function(settings)
        if not settings.necro_safe_room_use_material then return end
        local nh = settings.necromancer_healing
        local th = settings.thanatology
        if not (type(nh) == "table" and nh.Devour and type(th) == "table" and th.harvest_container) then
            report_error("Safe room necromancer healing requires the use of devour listed under necromancer_healing and a harvest_container listed under thanatology.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_safe_room_necro_is_storing_material",
    fn = function(settings)
        if not settings.necro_safe_room_use_material then return end
        local nh = settings.necromancer_healing
        local th = settings.thanatology
        if type(nh) == "table" and nh.Devour and type(th) == "table" and th.store == false then
            report_error("Safe room necromancer healing requires material on hand to use. You are not storing material and will eventually run out.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_cyclic_training_spells_are_defined",
    fn = function(settings)
        if not settings.cyclic_cycle_skills then return end
        local cts = settings.cyclic_training_spells or {}
        for _, skill in ipairs(settings.cyclic_cycle_skills) do
            if not has_key(cts, skill) then
                report_error("Skill in cyclic_cycle_skills does not have a cyclic_training_spell defined: " .. tostring(skill))
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crossing_training_spells_are_defined",
    fn = function(settings)
        if type(settings.crossing_training) ~= "table" then return end
        if not settings.train_with_spells then return end
        local spell_skills = {"Augmentation", "Warding", "Utility", "Debilitation"}
        local ts = settings.training_spells or {}
        for _, skill in ipairs(spell_skills) do
            if contains(settings.crossing_training, skill) and not has_key(ts, skill) then
                report_error("Magic skill in crossing_training does not have a training_spells defined: " .. skill)
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crossing_training_nonspells_are_defined",
    fn = function(settings)
        if type(settings.crossing_training) ~= "table" then return end
        if settings.train_with_spells then return end
        local spell_skills = {"Augmentation", "Warding", "Utility", "Debilitation"}
        local tns = settings.training_nonspells or {}
        for _, skill in ipairs(spell_skills) do
            if contains(settings.crossing_training, skill) and not has_key(tns, skill) then
                report_error("Magic skill in crossing_training does not have a training_nonspells defined: " .. skill)
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_pick_blind_is_deprecated",
    fn = function(settings)
        if settings.pick_blind then
            warn("The pick_blind settings is deprecated and is now always_pick_blind, please adjust your YAML, support for pick_blind will be removed in the future.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_check_discern_timer_is_deprecated",
    fn = function(settings)
        if settings.check_discern_timer then
            report_error("The check_discern_timer setting is deprecated. It is now check_discern_timer_in_hours for clarity. Please adjust accordingly.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_is_empath_is_deprecated",
    fn = function(settings)
        if settings.is_empath then
            warn("The is_empath setting is deprecated and can be removed from your YAML. We now check your guild from the info command.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_knitting_tools_doesnt_exist",
    fn = function(settings)
        if settings.knitting_tools then
            warn("knitting_tools: was deprecated, please update your yaml and use outfitting_tools: instead.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_appraise_pouches_is_deprecated",
    fn = function(settings)
        if settings.train_appraisal_with_pouches then
            warn("***YOU HAVE OUTDATED SETTINGS*** THE SETTING train_appraisal_with_pouches IS NO LONGER USED. READ MORE HERE: https://elanthipedia.play.net/Lich_script_repository#appraisal")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_mech_lore_is_deprecated",
    fn = function(settings)
        if type(settings.crossing_training) ~= "table" then return end
        if contains(settings.crossing_training, "Mechanical Lore") then
            warn("***YOU HAVE OUTDATED SETTINGS*** Mechanical Lore is no longer supported as it has been removed from the game with the release of Enchanting. Please remove from your training routine.")
            warn("Dependency has 'Engineering' to train engineering. Mechanical Lore is slow.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_appraise_gear_is_deprecated",
    fn = function(settings)
        if settings.train_appraisal_with_gear then
            warn("***YOU HAVE OUTDATED SETTINGS*** THE SETTING train_appraisal_with_gear IS NO LONGER USED. READ MORE HERE: https://elanthipedia.play.net/Lich_script_repository#appraisal")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_tailoring_belt_is_deprecated",
    fn = function(settings)
        if settings.tailoring_belt then
            warn("The tailoring_belt setting is deprecated and can be removed from your YAML. The outfitting_belt setting should be used instead.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_astrology_buffs_is_deprecated",
    fn = function(settings)
        if type(settings.astrology_buffs) == "table" and settings.astrology_buffs.spells then
            warn("*** YOU HAVE OUTDATED SETTINGS *** THE SETTING astrology_buffs[spells] IS NO LONGER USED. Astrology buffs now uses a waggle set named astrology!")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crossing_training_sorcery_as_string_is_deprecated",
    fn = function(settings)
        if settings.crossing_training_sorcery and type(settings.crossing_training_sorcery) == "string" then
            warn("The crossing_training_sorcery setting should not be a string. Instead it should be a spell definition similar to astrology_buffs, lockpick_buffs, scouting_buffs, or stealing_buffs.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_weapon_training_has_ranged_skill_when_retreat_is_enabled",
    fn = function(settings)
        if type(settings.hunting_info) ~= "table" then return end
        if not settings.weapon_training then return end
        local wt_keys = keys(settings.weapon_training)
        if not is_empty(set_intersect(valid_ranged_skills, wt_keys)) then return end
        -- Check if any hunting_info entry has a retreat threshold (arg matching /r\d+/)
        local re = Regex.new("r\\d+")
        for _, info in ipairs(settings.hunting_info) do
            if type(info) == "table" and type(info.args) == "table" then
                for _, arg in ipairs(info.args) do
                    if re:test(tostring(arg)) then
                        report_error("Hunt '" .. tostring(info.zone or "(unknown)") ..
                                     "' has a retreat threshold set, but no ranged weapon skills to train.")
                        break
                    end
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_barb_combos_is_deprecated",
    fn = function(settings)
        if settings.use_barb_combos then
            warn("use_barb_combos is deprecated, please change to use_analyze_combos for the replacement.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_barb_buffs_are_in_base_spells",
    fn = function(settings)
        if not settings.buff_nonspells then return end
        if type(settings.buff_nonspells) ~= "table" then return end
        if not settings.buff_nonspells.barb_buffs then return end
        local spell_data = get_data("spells")
        local supported = (type(spell_data) == "table" and spell_data.barb_abilities) or {}
        for _, name in ipairs(settings.buff_nonspells.barb_buffs) do
            if not contains(supported, name) then
                report_error("Barb ability '" .. tostring(name) ..
                             "' not yet supported. Please make an issue on Github for it to be added!")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_predict_event_is_deprecated",
    fn = function(settings)
        if settings.predict_event then
            warn("***YOU HAVE OUTDATED SETTINGS*** THE SETTING predict_event IS NO LONGER USED. READ MORE HERE: https://elanthipedia.play.net/Lich_script_repository#astrology")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_train_in_ap_is_deprecated",
    fn = function(settings)
        if type(settings.astral_plane_training) == "table" and settings.astral_plane_training.train_in_ap then
            warn("***YOU HAVE OUTDATED SETTINGS*** THE SETTING train_in_ap IS NO LONGER USED. READ MORE HERE: https://elanthipedia.play.net/Lich_script_repository#astrology")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_astrology_keys_are_valid",
    fn = function(settings)
        if not settings.astrology_training then return end
        for _, key in ipairs(keys(settings.astrology_training)) do
            if not contains(valid_astrology_keys, key) then
                report_error("'" .. tostring(key) ..
                             "' is not a valid setting for astrology_training! Valid settings are '" ..
                             table.concat(valid_astrology_keys, ", ") .. "'")
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_necro_train_first_aid_is_deprecated",
    fn = function(settings)
        if type(settings.thanatology) ~= "table" then return end
        if settings.thanatology.train_first_aid then
            warn("***YOU HAVE OUTDATED SETTINGS*** THE SETTING thanatology[\"train_first_aid\"] IS NO LONGER USED. To train first aid via rituals use the dissect ritual or cycle rituals.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_have_divination_bones_is_deprecated",
    fn = function(settings)
        if settings.have_divination_bones then
            warn("***YOU HAVE OUTDATED SETTINGS*** THE SETTING have_divination_bones IS NO LONGER USED. Used now with just divination_bones_storage set. Please adjust accordingly.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_hometown_is_valid",
    fn = function(settings)
        if not settings.hometown then return end
        local town_data = get_data("town")
        if type(town_data) ~= "table" then return end
        local valid_hometowns = keys(town_data)
        if not contains(valid_hometowns, settings.hometown) then
            warn("Your hometown of '" .. tostring(settings.hometown) ..
                 "' is not valid. Valid values are: " .. table.concat(valid_hometowns, ", "))
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_force_healer_town_is_valid",
    fn = function(settings)
        if not settings.force_healer_town then return end
        local town_data = get_data("town")
        if type(town_data) ~= "table" then return end
        local valid_hometowns = keys(town_data)
        if not contains(valid_hometowns, settings.force_healer_town) then
            report_error("Your force_healer_town setting of '" .. tostring(settings.force_healer_town) ..
                         "' is not valid. Valid values are: " .. table.concat(valid_hometowns, ", "))
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_hometown_has_npc_empath",
    fn = function(settings)
        local town_data = get_data("town")
        if type(town_data) ~= "table" then return end
        local hometown = settings.force_healer_town or settings.hometown
        if not hometown then return end
        local town_entry = town_data[hometown]
        if type(town_entry) == "table" and town_entry.npc_empath == nil then
            report_error("No npc empath exists in your hometown or force_healer_town so healing will not work, please pick another town.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_lockpick_buffs_are_deprecated",
    fn = function(settings)
        if not is_empty(settings.lockpick_buffs) then
            warn("***YOU HAVE OUTDATED SETTINGS*** THE SETTING lockpick_buffs IS NO LONGER USED. Please make a waggle_set called 'pick'")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_component_container_is_deprecated",
    fn = function(settings)
        if not is_empty(settings.component_container) then
            warn("component_container is deprecated, please nest the setting under pick settings. https://elanthipedia.play.net/Lich_script_repository#pick")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_sell_loot_money_on_hand_is_correct",
    fn = function(settings)
        if not settings.sell_loot_money_on_hand then return end
        local s = tostring(settings.sell_loot_money_on_hand)
        local amount, denom = s:match("^(%d+)%s+(%a+)")
        if not amount then
            report_error("sell_loot_money_on_hand is invalid. The proper format is: <amount> <denomination> e.g. 3 silv or 4 bronze")
            return
        end
        local denominations = {"copper", "bronze", "silver", "gold", "platinum"}
        local valid_denom = false
        for _, d in ipairs(denominations) do
            if d:sub(1, #denom) == denom:lower() then valid_denom = true; break end
        end
        if not valid_denom then
            report_error("sell_loot_money_on_hand is invalid. The proper format is: <amount> <denomination> e.g. 3 silv or 4 bronze")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_sell_loot_metals_and_stones_is_correct",
    fn = function(settings)
        if not settings.sell_loot_metals_and_stones then return end
        if not settings.sell_loot_metals_and_stones_container then
            report_error("You do not have a container set for selling metals and stones. Specify sell_loot_metals_and_stones_container: setting.")
        end
        local loot_additions = settings.loot_additions or {}
        if not (contains(loot_additions, "nugget") or contains(loot_additions, "bar")) then
            warn("sell_loot_metals_and_stones setting is true. You may want to add \"nugget\" and \"bar\" to your loot_additions: setting.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_pet_buffs_have_spell_requirements",
    fn = function(settings)
        if type(settings.buff_spells) ~= "table" then return end
        for name, data in pairs(settings.buff_spells) do
            if type(data) == "table" and data.pet_type then
                if not data.recast_every then
                    report_error("Pet buffs require a custom recast timer. Please include a \"recast_every:\" setting for " .. tostring(name) .. ".")
                end
                if not data.cast then
                    report_error("Pet buffs require a custom cast message. Please include a \"cast:\" setting for " .. tostring(name) .. ".")
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_restock_shop_items_recipes_are_valid",
    fn = function(settings)
        if is_empty(settings.restock_shop) then return end
        if type(settings.restock_shop) ~= "table" then return end
        if not settings.restock_shop.items then return end
        local recipes_data = get_data("recipes")
        local recipes = (type(recipes_data) == "table" and recipes_data.crafting_recipes) or {}
        for _, item in ipairs(settings.restock_shop.items) do
            if type(item) == "table" and item.recipe then
                local found = false
                for _, recipe in ipairs(recipes) do
                    if type(recipe) == "table" and type(recipe.name) == "string" and
                       recipe.name:find(tostring(item.recipe)) then
                        found = true; break
                    end
                end
                if not found then
                    report_error("The following restock shop items match no recipe data: " .. tostring(item.recipe))
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_workorder_cash_on_hand_is_correct",
    fn = function(settings)
        if not settings.workorder_cash_on_hand then return end
        if not is_integer(settings.workorder_cash_on_hand) then
            report_error("workorder_cash_on_hand is invalid. The proper format is 5000 for 5 gold for example")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_repair_withdrawal_amount_is_correct",
    fn = function(settings)
        if not settings.repair_withdrawal_amount then return end
        if not is_integer(settings.repair_withdrawal_amount) then
            report_error("repair_withdrawal_amount: is invalid. The proper format is 5000 for 5 gold for example")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_regalia_waggle_is_defined",
    fn = function(settings)
        if not settings.cycle_armors_regalia then return end
        if type(settings.waggle_sets) ~= "table" then return end
        local regalia_set = settings.waggle_sets.regalia
        if not (type(regalia_set) == "table" and regalia_set.Regalia) then
            warn("No Regalia waggle defined. Combat-trainer will use min prep unless you declare a waggle named 'regalia' with different values")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_regalia_waggle_has_abbrev",
    fn = function(settings)
        if not settings.cycle_armors_regalia then return end
        if type(settings.waggle_sets) ~= "table" then return end
        local regalia_set = settings.waggle_sets.regalia
        if not (type(regalia_set) == "table" and type(regalia_set.Regalia) == "table") then return end
        local abbrev = regalia_set.Regalia.abbrev
        if type(abbrev) ~= "string" or abbrev:upper() ~= "REGAL" then
            report_error("Regalia waggle's abbreviation differs from default. Change to abbrev: REGAL")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_regalia_gearset_is_defined",
    fn = function(settings)
        if not settings.cycle_armors_regalia then return end
        if type(settings.gear_sets) ~= "table" then return end
        local regalia_gear = settings.gear_sets.regalia
        if regalia_gear == nil or (type(regalia_gear) == "table" and #regalia_gear == 0) then
            report_error("Regalia cycling requires a gear_set named 'regalia' that is missing any armor you wish Regalia to replace.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_regalia_does_not_conflict_with_armor_swap",
    fn = function(settings)
        if settings.cycle_armors and settings.cycle_armors_regalia then
            report_error("cycle_armors and cycle_armors_regalia at the same time not currently supported! Combat-trainer will default to cycle_armors only!")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_cycle_regalia_are_skills",
    fn = function(settings)
        if not settings.cycle_armors_regalia then return end
        local valid = {"Light Armor", "Chain Armor", "Brigandine", "Plate Armor"}
        for _, skill in ipairs(settings.cycle_armors_regalia) do
            if not contains(valid, skill) then
                report_error("Skill name in cycle_armors_regalia is not valid: " .. tostring(skill))
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_spells_are_in_base_spells",
    fn = function(settings)
        local sd = get_data("spells")
        local spell_data = (type(sd) == "table" and sd.spell_data) or {}

        local function check_list(list_name, spell_names)
            if is_empty(spell_names) then return end
            local bad = {}
            for _, name in ipairs(spell_names) do
                if not has_key(spell_data, name) then table.insert(bad, name) end
            end
            if not is_empty(bad) then
                warn(list_name .. " contains the following spell names not found in data/base_spells, " ..
                     table.concat(bad, ", ") .. " Check spelling and capitalization.")
            end
        end

        -- buff_spells (hash keyed by spell name)
        if type(settings.buff_spells) == "table" then
            local names = {}
            for spell_name in pairs(settings.buff_spells) do table.insert(names, spell_name) end
            check_list("buff_spells", names)
        end

        -- offensive_spells (array of {name=...})
        if type(settings.offensive_spells) == "table" then
            local names = {}
            for _, s in ipairs(settings.offensive_spells) do
                if type(s) == "table" and s.name then table.insert(names, s.name) end
            end
            check_list("offensive_spells", names)
        end

        -- crafting_training_spells
        if type(settings.crafting_training_spells) == "table" then
            local names = {}
            for _, data in pairs(settings.crafting_training_spells) do
                if type(data) == "table" and data.name and not has_key(spell_data, data.name) then
                    table.insert(names, data.name)
                end
            end
            if not is_empty(names) then
                warn("crafting_training_spells contains the following spell names not found in data/base_spells, " ..
                     table.concat(names, ", ") .. " Check spelling and capitalization.")
            end
        end

        -- training_spells
        if type(settings.training_spells) == "table" then
            local names = {}
            for _, data in pairs(settings.training_spells) do
                if type(data) == "table" and data.name and not has_key(spell_data, data.name) then
                    table.insert(names, data.name)
                end
            end
            if not is_empty(names) then
                warn("training_spells contains the following spell names not found in data/base_spells, " ..
                     table.concat(names, ", ") .. " Check spelling and capitalization.")
            end
        end

        -- combat_spell_training
        if type(settings.combat_spell_training) == "table" then
            local names = {}
            for _, data in pairs(settings.combat_spell_training) do
                if type(data) == "table" and data.name and not has_key(spell_data, data.name) then
                    table.insert(names, data.name)
                end
            end
            if not is_empty(names) then
                warn("combat_spell_training contains the following spell names not found in data/base_spells, " ..
                     table.concat(names, ", ") .. " Check spelling and capitalization.")
            end
        end

        -- waggle_sets (hash of {spell_name -> data})
        if type(settings.waggle_sets) == "table" then
            local names = {}
            for _, spell_set in pairs(settings.waggle_sets) do
                if type(spell_set) == "table" then
                    for spell_name in pairs(spell_set) do
                        table.insert(names, spell_name)
                    end
                end
            end
            check_list("waggle_sets", uniq(names))
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_caravan_training_skills_are_valid",
    fn = function(settings)
        if is_empty(settings.caravan_training_skills) then return end
        for skill, cooldown in pairs(settings.caravan_training_skills) do
            if not is_integer(cooldown) then
                report_error("caravan_training_skills has an invalid cooldown at skill: '" .. tostring(skill) .. "'")
            end
            if not contains(valid_caravan_skills, skill) then
                report_error("caravan_training_skills: skills not recognized as valid skills '" .. tostring(skill) .. "'")
            end
            local spell_skills = {"Augmentation", "Utility", "Warding"}
            if contains(spell_skills, skill) then
                local cts = settings.crafting_training_spells or {}
                if not has_key(cts, skill) then
                    report_error("caravan_training_skills: " .. skill ..
                                 " is included, but no corresponding spell in crafting_training_spells!")
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_avtalia_array_is_valid",
    fn = function(settings)
        if is_empty(settings.avtalia_array) then return end
        local cambrinth_str = tostring(settings.cambrinth or "")
        for _, camb in ipairs(settings.avtalia_array) do
            if type(camb) == "table" and type(camb.name) == "string" then
                local parts = {}
                for w in camb.name:gmatch("%S+") do table.insert(parts, w) end
                local first = parts[1] or ""
                local last  = parts[#parts] or ""
                local pat = first == last and ("(?i)\\b" .. first) or
                                              ("(?i)" .. first .. ".*\\b" .. last)
                local ok, re = pcall(Regex.new, pat)
                if ok and re then
                    -- Check if the avtalia cambrinth conflicts with normal cambrinth
                    if re:test(cambrinth_str) then
                        report_error("avtalia_array appears to include your normal casting cambrinth. This could break it horribly.")
                    end
                    -- Check for duplicates within avtalia_array
                    local count = 0
                    for _, other in ipairs(settings.avtalia_array) do
                        if type(other) == "table" and type(other.name) == "string" and re:test(other.name) then
                            count = count + 1
                        end
                    end
                    if count > 1 then
                        report_error("avtalia_array has a duplicate entry for " .. camb.name ..
                                     ". Any cambrinth used in avtalia_array must be unique.")
                    end
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_cornmaze_containers_is_an_array",
    fn = function(settings)
        if is_empty(settings.cornmaze_containers) then return end
        if type(settings.cornmaze_containers) == "table" and settings.cornmaze_containers[1] then return end
        report_error("cornmaze_containers should be a list of containers like:\ncornmaze_containers:\n  - haversack\n  - portal\n  - hip pouch")
    end
}

assertions[#assertions+1] = {
    name = "assert_that_crossing_training_config_is_valid",
    fn = function(settings)
        if not settings.crossing_training then return end
        if type(settings.crossing_training_max_threshold) ~= "number" then
            report_error("crossing_training_max_threshold is not a numeric value. This may cause problems with the crossing-training script.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_attunement_config_is_valid",
    fn = function(settings)
        if type(settings.attunement_target_increment) ~= "number" then
            report_error("attunement_target_increment is not a numeric value. This may cause problems with the attunement script.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_faux_atmo_config_is_valid",
    fn = function(settings)
        if is_empty(settings.faux_atmo_items) then return end
        if type(settings.faux_atmo_interval) ~= "number" then
            report_error("faux_atmo_interval is not a numeric value. This may cause problems with the faux-atmo script.")
        end
        for _, item in ipairs(settings.faux_atmo_items) do
            if type(item) == "table" then
                if is_empty(item.name) then
                    report_error("Entry in faux_atmo_items list has no name property. This may cause problems with the faux-atmo script. " .. tostring(item))
                elseif is_empty(item.verbs) then
                    report_error("Entry in faux_atmo_items list has no verbs property. This may cause problems with the faux-atmo script. " .. tostring(item))
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_wand_settings_are_valid",
    fn = function(settings)
        if is_empty(settings.wands) then return end
        for wand_name, wand_settings in pairs(settings.wands) do
            if type(wand_settings) == "table" then
                if wand_settings["activation message"] == nil then
                    report_error("You do not have an activation message for " .. tostring(wand_name) ..
                                 ".  This means it will not be possible to detect when the wand was activated successfully.")
                end
                if wand_settings.container == nil then
                    report_error("You do not have a container set for " .. tostring(wand_name) ..
                                 " in wands:.  This will prevent it from working.")
                end
            end
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_backstab_is_not_an_array",
    fn = function(settings)
        if settings.backstab == nil then return end
        if type(settings.backstab) == "table" then return end  -- array is fine
        -- The assertion warns if it IS defined AND is NOT an array
        -- (In Ruby: return unless settings.backstab && !settings.backstab.is_a?(Array))
        -- So: flag if backstab is set and is not a table
        report_error("setting backstab is defined as \"" .. tostring(settings.backstab) ..
                     "\" which is not correct. A correct setting is a list of weapons to use when backstabbing, see base.yaml for an example.")
    end
}

assertions[#assertions+1] = {
    name = "assert_that_prehunt_buffs_is_deprecated",
    fn = function(settings)
        if settings.prehunt_buffs then
            warn("prehunt_buffs is deprecated, please change to prehunt_buffing_room: <num>.")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_prehunt_buffing_room_exists_without_waggle_set",
    fn = function(settings)
        if type(settings.waggle_sets) ~= "table" then return end
        if settings.waggle_sets.prehunt_buffs and settings.prehunt_buffing_room == nil then
            warn("You have a prehunt_buffs waggle set without a room defined, you will buff in place!")
        end
    end
}

assertions[#assertions+1] = {
    name = "assert_that_use_barrage_attacks_is_deprecated",
    fn = function(settings)
        if not settings.use_barrage_attacks then return end
        if not DRStats.warrior_mage() then return end
        warn("use_barrage_attacks is deprecated, please specify \"barrage: true\" in the spell configurations for the TM spells you want to use barrage attacks with.")
    end
}

-------------------------------------------------------------------------------
-- Run assertions against a settings object
-------------------------------------------------------------------------------

local function run_assertions(settings)
    for _, assertion in ipairs(assertions) do
        if verbose then
            current_check = assertion.name
        end
        local ok, err = pcall(assertion.fn, settings)
        if not ok then
            echo("  [validate] Error in " .. assertion.name .. ": " .. tostring(err))
        end
        current_check = nil
    end
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

local charname = (GameState and GameState.name) or ""

respond("")
respond("  CHECKING: That JSON profile files have the correct .json extension")
respond("  (Revenant uses JSON profiles in profiles/. YAML profiles are not valid here.)")

-- Check for stray YAML files in profiles/ directory
local profile_files = {}
if File.is_dir("profiles") then
    profile_files = File.list("profiles") or {}
end

local stray_yaml = {}
for _, f in ipairs(profile_files) do
    if f:find("%.yaml$") or f:find("%.yml$") then
        table.insert(stray_yaml, f)
    end
end

if #stray_yaml > 0 then
    echo("**WARNING**: You have YAML profile files in profiles/. Revenant requires JSON format (.json).")
    echo("Please convert the following profiles to JSON and rename to .json:")
    for _, f in ipairs(stray_yaml) do
        respond("   " .. f)
    end
    warning_count = warning_count + 1
else
    respond("   PASSED")
end

respond("")
respond("  CHECKING: That " .. charname .. "-setup.json exists in the profiles/ folder.")

local setup_file = "profiles/" .. charname .. "-setup.json"
if not File.exists(setup_file) then
    echo("**WARNING**: No " .. charname .. "-setup.json file found in profiles/.")
    echo("This file is required. Check that the file exists and is in the correct folder.")
    echo("ENDING REMAINING CHECKS DUE TO MISSING SETUP FILE")
    respond("")
    respond("  WARNINGS:" .. warning_count .. " ERRORS:" .. error_count)
    respond("  All done!")
    respond("")
    return
else
    respond("   PASSED")
end

respond("")
respond("  CHECKING: That character JSON files contain valid JSON.")

for _, f in ipairs(profile_files) do
    local lower_name = charname:lower()
    if f:lower():find("^" .. lower_name .. "%-") and f:find("%.json$") then
        local path = "profiles/" .. f
        local content = File.read(path) or ""
        local ok, _ = pcall(Json.decode, content)
        local mtime_str = tostring(File.mtime(path) or "")
        if ok then
            respond("   " .. f .. " PASSED - Modified: " .. mtime_str)
        else
            echo("   " .. f .. " FAILED - Modified: " .. mtime_str)
            error_count = error_count + 1
        end
    end
end

warn_custom_scripts()

-- Load and validate the main setup settings
respond("")
respond("  CHECKING: " .. #assertions .. " different potential errors in [" .. charname .. "-setup.json]")

local settings = get_settings()
run_assertions(settings)

-- Validate hunting_file_list entries if present
if type(settings.hunting_file_list) == "table" and not is_empty(settings.hunting_file_list) then
    respond("")
    respond("  You have specified files via json setting hunting_file_list.")
    respond("  Validating settings for " .. #settings.hunting_file_list ..
            " settings files. Note: json errors from " .. charname .. "-setup.json may be duplicated below.")
    respond("")

    for _, file in ipairs(settings.hunting_file_list) do
        if tostring(file) ~= "setup" then  -- already checked setup above
            local hunt_file = "profiles/" .. charname .. "-" .. tostring(file) .. ".json"
            if not File.exists(hunt_file) then
                respond("  NO FILE EXISTS: You've identified " .. charname .. "-" .. tostring(file) ..
                        ".json in hunting_file_list, but file does not exist.")
                respond("")
            else
                respond("  CHECKING: " .. #assertions .. " different potential errors in file [" ..
                        charname .. "-" .. tostring(file) .. ".json]")
                local ok_s, file_settings = pcall(get_settings, {tostring(file)})
                if ok_s and type(file_settings) == "table" then
                    run_assertions(file_settings)
                else
                    echo("  ERROR: Could not load settings from " .. charname .. "-" .. tostring(file) .. ".json")
                    error_count = error_count + 1
                end
                respond("")
            end
        end
    end
end

respond("  WARNINGS:" .. warning_count .. " ERRORS:" .. error_count)
respond("  All done!")
respond("")
