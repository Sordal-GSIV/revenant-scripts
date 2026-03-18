--- @revenant-script
--- name: combatical
--- version: 1.3.1
--- author: Kyrandos
--- game: gs
--- description: Combat ability manager - track spells, CMANs, items, and custom verbs with cooldowns and usage counts
--- tags: utility, abilities, manager, combat, targeting, spells, items, tracker, status, gui
--- @lic-certified: complete 2026-03-18
---
--- Ported from Combatical.lic (Lich5 GTK3) to Revenant Lua (Gui.* API)
--- Original author: Kyrandos — Version 1.2.6
--- Contact: EducatedBarbarian@proton.me
---
--- Changelog (Lich5):
---   1.0.0 2/15/2026 - initial release
---   1.0.1 2/15/2026 - Minor tweaks to language and ability pool layout + slider bars
---   1.0.5 2/15/2026 - major revisions to ability status tracking, added ability to reorder abilities
---   1.1.0 2/16/2026 - Added notification for locked items, gameobj id method, debugging, improved stability
---   1.1.1 2/16/2026 - fix reset, fix box_labels sizing, CSS accumulation fix, GoS sigils, scan versioning
---   1.1.2 2/16/2026 - Added clarifying tooltips, added [] remove item function
---   1.1.3 2/16/2026 - Added (verb) get-from-container, attack flash, COWARDS tracking
---   1.1.5 2/16/2026 - Reworked NPC targeting, added status icons
---   1.1.6 2/25/2026 - Scripted item edit function, wiki case sensitivity fix
---   1.1.7 2/25/2026 - Save improvements
---   1.1.8 2/25/2026 - Wiki case fix, ctrl+click autofire
---   1.1.9 2/25/2026 - UTF 8 default for Mac OS
---   1.2.0 2/25/2026 - Finished Society: Voln corrected, COL+GOS enabled, ALL ability colorings
---   1.2.1 2/26/2026 - Track scripted items by long name for persistence
---   1.2.2 2/26/2026 - Fix item_long_name/item_noun save/load cycle
---   1.2.5 2/26/2026 - Crash handling and refresh logic improvements
---   1.2.6 3/03/2026 - Debug info firing in non-debug mode fixed
---   1.3.0 3/18/2026 - Revenant port: GTK3 -> Gui.* API, full game logic preserved
---   1.3.1 3/18/2026 - Fix Berserker warcry scan, COWARDS tracking, get-first container lookup,
---                     attack flash marker, lock button, refresh button, ability notes UI,
---                     wiki_confirm toggle, repeat CLI command
---
--- Usage:
---   ;combatical              - Open the ability manager GUI
---   ;combatical scan         - Force rescan of all abilities
---   ;combatical list         - List all known abilities to game window
---   ;combatical use <name>   - Execute an ability by name
---   ;combatical wiki <name>  - Print wiki URL for an ability
---   ;combatical repeat <name>- Toggle auto-repeat for an ability
---   ;combatical setup        - Open settings GUI
---   ;combatical reset        - Clear saved configuration
---   ;combatical debug        - Enable debug output
---
--- Features:
---   - Full scanner: spells (all circles + Arcane), CMANs, Shield/Weapon/Armor techniques,
---     Feats, Warcries, Society abilities (Voln, CoL, GoS), Common Verbs, Native Buffs
---   - Scripted items: frequency, charge, UPD tracking with midnight EST reset
---   - [verb] remove-first and (verb) get-from-container notations
---   - NPC/target tracking with status icons
---   - Named ability groups (boxes) with ordering
---   - Resource bars: health/mana/stamina/spirit
---   - Settings persistence via CharSettings (JSON)
---   - GUI with Gui.* API: ability buttons in groups, target display, resource bars
---   - CLI commands for headless use

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local SCAN_VERSION = 3
local SETTINGS_KEY = "combatical"
local AUTOSAVE_INTERVAL = 120 -- seconds
local UPDATE_INTERVAL = 0.25 -- seconds (250ms timer tick)

-- ============================================================================
-- DEBUG
-- ============================================================================

local debug_mode = false

local function dbg(msg)
    if debug_mode then
        echo("[DEBUG] " .. msg)
    end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

local function title_case(str)
    return str:gsub("(%a)([%w_']*)", function(a, b)
        return a:upper() .. b
    end)
end

local function build_wiki_url(name)
    return "https://gswiki.play.net/" .. name:gsub(" ", "_")
end

--- Format seconds to human readable: "12:04:32", "4:32", "3s"
local function format_duration(seconds)
    seconds = math.ceil(seconds)
    if seconds >= 3600 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        return string.format("%d:%02d:%02d", h, m, s)
    elseif seconds >= 60 then
        local m = math.floor(seconds / 60)
        local s = seconds % 60
        return string.format("%d:%02d", m, s)
    else
        return seconds .. "s"
    end
end

--- Parse frequency/charges/UPD string
--- "12h4m32s" -> {type="frequency", value=seconds}
--- "50 charges" -> {type="charges", value=50}
--- "3UPD" -> {type="upd", value=3}
local function parse_frequency(str)
    if not str or str == "" then return nil end
    str = str:lower():match("^%s*(.-)%s*$")
    if str == "" then return nil end

    -- UPD
    local upd = str:match("^(%d+)%s*upd$")
    if upd then return { type = "upd", value = tonumber(upd) } end

    -- Charges
    local charges = str:match("^(%d+)%s*charges?$")
    if charges then return { type = "charges", value = tonumber(charges) } end

    -- Time format
    local total = 0
    local matched = false
    local h = str:match("(%d+)%s*h")
    if h then total = total + tonumber(h) * 3600; matched = true end
    local m = str:match("(%d+)%s*m")
    if m then total = total + tonumber(m) * 60; matched = true end
    local s = str:match("(%d+)%s*s")
    if s then total = total + tonumber(s); matched = true end

    if matched and total > 0 then
        return { type = "frequency", value = total }
    end
    return nil
end

--- Deep copy a table
local function deep_copy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deep_copy(v)
    end
    return copy
end

--- Check if table contains a value
local function tbl_contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

--- Find index in table
local function tbl_index(tbl, val)
    for i, v in ipairs(tbl) do
        if v == val then return i end
    end
    return nil
end

--- Get current EST date string for UPD reset
local function est_date_today()
    -- Approximate EST as UTC-5
    local utc = os.time()
    local est = utc - 5 * 3600
    return os.date("%Y-%m-%d", est)
end

-- ============================================================================
-- ABILITY CLASS
-- ============================================================================

local Ability = {}
Ability.__index = Ability

function Ability.new(data)
    data = data or {}
    local self = setmetatable({}, Ability)
    self.name              = data.name or ""
    self.command           = data.command or ""
    self.type              = data.type or "unknown"
    self.resource_type     = data.resource_type or "none"
    self.cost              = data.cost or 0
    self.roundtime         = data.roundtime or 0
    self.wiki_url          = data.wiki_url or ""
    self.category          = data.category or "Uncategorized"
    self.passive           = data.passive or false
    self.frequency_seconds = data.frequency_seconds
    self.max_charges       = data.max_charges
    self.remaining_charges = data.remaining_charges
    self.max_upd           = data.max_upd
    self.remaining_upd     = data.remaining_upd
    self.upd_last_reset    = data.upd_last_reset
    self.item_cooldown_end = nil
    self.remove_first      = data.remove_first or false
    self.get_first         = data.get_first or false
    self.item_long_name    = data.item_long_name
    self.item_noun         = data.item_noun
    return self
end

function Ability:to_table()
    local t = {
        name          = self.name,
        command       = self.command,
        type          = self.type,
        resource_type = self.resource_type,
        cost          = self.cost,
        roundtime     = self.roundtime,
        wiki_url      = self.wiki_url,
        category      = self.category,
        passive       = self.passive,
    }
    if self.frequency_seconds then t.frequency_seconds = self.frequency_seconds end
    if self.max_charges then t.max_charges = self.max_charges end
    if self.max_upd then t.max_upd = self.max_upd end
    if self.remove_first then t.remove_first = true end
    if self.get_first then t.get_first = true end
    if self.item_long_name and self.item_long_name ~= "" then t.item_long_name = self.item_long_name end
    if self.item_noun and self.item_noun ~= "" then t.item_noun = self.item_noun end
    return t
end

function Ability.from_table(t)
    if not t then return nil end
    return Ability.new(t)
end

function Ability:check_upd_reset()
    if not self.max_upd then return end
    local today = est_date_today()
    if not self.upd_last_reset or self.upd_last_reset ~= today then
        dbg("[UPD] " .. self.name .. ": daily reset (" .. (self.upd_last_reset or "first use") .. " -> " .. today .. "), refilled to " .. self.max_upd)
        self.remaining_upd = self.max_upd
        self.upd_last_reset = today
    end
end

function Ability:available()
    if self.passive then return false end
    if self.type == "item" then
        if self.item_cooldown_end and self.item_cooldown_end > os.time() then return false end
        if self.max_charges and self.remaining_charges and self.remaining_charges <= 0 then return false end
        if self.max_upd then
            self:check_upd_reset()
            if self.remaining_upd and self.remaining_upd <= 0 then return false end
        end
        return true
    end
    if self.type == "spell" or self.type == "society" or self.type == "verb" then
        return true
    end
    -- For CMANs, shields, weapons, armor, feats, warcries: check Effects.Cooldowns
    local ok, result = pcall(function()
        local cooldowns = Effects and Effects.Cooldowns and Effects.Cooldowns.to_h and Effects.Cooldowns:to_h()
        if cooldowns then
            local norm = self.name:lower()
            for key, expiry in pairs(cooldowns) do
                if tostring(key):lower() == norm then
                    if type(expiry) == "number" and expiry > os.time() then
                        return false
                    end
                end
            end
        end
        return true
    end)
    if ok then return result end
    return true
end

function Ability:record_item_use()
    if self.frequency_seconds and self.frequency_seconds > 0 then
        self.item_cooldown_end = os.time() + self.frequency_seconds
        dbg("[ITEM] " .. self.name .. ": cooldown set to " .. self.frequency_seconds .. "s")
    end
    if self.max_charges and self.remaining_charges and self.remaining_charges > 0 then
        self.remaining_charges = self.remaining_charges - 1
        dbg("[ITEM] " .. self.name .. ": charges " .. self.remaining_charges .. "/" .. self.max_charges)
    end
    if self.max_upd then
        self:check_upd_reset()
        if self.remaining_upd and self.remaining_upd > 0 then
            self.remaining_upd = self.remaining_upd - 1
            dbg("[ITEM] " .. self.name .. ": UPD " .. self.remaining_upd .. "/" .. self.max_upd)
        end
    end
end

function Ability:item_cooldown_remaining()
    if not self.item_cooldown_end then return 0 end
    return math.max(0, self.item_cooldown_end - os.time())
end

function Ability:roundtime_display()
    if self.roundtime == 0 then return "" end
    if self.roundtime < 60 then return self.roundtime .. "s" end
    if self.roundtime < 3600 then
        return math.floor(self.roundtime / 60) .. "m " .. (self.roundtime % 60) .. "s"
    end
    return math.floor(self.roundtime / 3600) .. "h " .. math.floor((self.roundtime % 3600) / 60) .. "m"
end

--- Get color for ability based on resource type
function Ability:color()
    if self.resource_type == "mana" then return { 0, 102, 204 }
    elseif self.resource_type == "stamina" then return { 255, 214, 0 }
    elseif self.resource_type == "health" then return { 204, 0, 0 }
    elseif self.resource_type == "spirit" then return { 255, 255, 255 }
    else return { 135, 135, 135 }
    end
end

-- ============================================================================
-- SCANNER MODULE
-- ============================================================================

local EXCLUDED_ABILITIES = { perceive = true, glance = true }

--- Scan all known spells across all circles
local function scan_spells()
    local abilities = {}
    local ok, err = pcall(function()
        if not Spell then return end

        -- If Spell has a .list method, iterate it
        if Spell.list then
            local spell_list = Spell.list()
            if type(spell_list) == "table" then
                for _, spell in ipairs(spell_list) do
                    if spell.known then
                        local circle_name = spell.circle or "Unknown"
                        -- Skip society spells (handled by scan_society)
                        if circle_name ~= "Order of Voln" and circle_name ~= "Council of Light" and circle_name ~= "Guardians of Sunfist" then
                            local cmd = "incant " .. (spell.num or spell.name:lower())
                            local cat = "Spells - " .. circle_name
                            table.insert(abilities, Ability.new({
                                name = spell.name or ("Spell " .. (spell.num or "?")),
                                command = cmd,
                                type = "spell",
                                resource_type = "mana",
                                cost = spell.mana_cost or 0,
                                roundtime = 3,
                                wiki_url = build_wiki_url(spell.name or ""),
                                category = cat,
                                passive = false,
                            }))
                        end
                    end
                end
                dbg("Found " .. #abilities .. " known spells via Spell.list()")
                return
            end
        end

        -- Fallback: iterate known spell circle ranges
        local circles = {
            { name = "Minor Spirit",    start = 101,  stop = 150  },
            { name = "Major Spirit",    start = 201,  stop = 250  },
            { name = "Cleric",          start = 301,  stop = 350  },
            { name = "Minor Elemental", start = 401,  stop = 450  },
            { name = "Major Elemental", start = 501,  stop = 550  },
            { name = "Ranger",          start = 601,  stop = 650  },
            { name = "Sorcerer",        start = 701,  stop = 750  },
            { name = "Wizard",          start = 901,  stop = 950  },
            { name = "Bard",            start = 1001, stop = 1050 },
            { name = "Empath",          start = 1101, stop = 1150 },
            { name = "Minor Mental",    start = 1201, stop = 1250 },
            { name = "Paladin",         start = 1601, stop = 1650 },
            { name = "Telepathy",       start = 1701, stop = 1750 },
            { name = "Arcane",          start = 1700, stop = 1750 },
        }

        for _, circle in ipairs(circles) do
            for num = circle.start, circle.stop do
                local spell = Spell[num]
                if spell and spell.known then
                    table.insert(abilities, Ability.new({
                        name = spell.name or ("Spell " .. num),
                        command = "incant " .. num,
                        type = "spell",
                        resource_type = "mana",
                        cost = spell.mana_cost or 0,
                        roundtime = 3,
                        wiki_url = build_wiki_url(spell.name or ("Spell_" .. num)),
                        category = "Spells - " .. circle.name,
                        passive = false,
                    }))
                end
            end
        end
        dbg("Found " .. #abilities .. " known spells via circle scan")
    end)
    if not ok then dbg("Error scanning spells: " .. tostring(err)) end
    return abilities
end

--- Scan Combat Maneuvers
local function scan_cmans()
    local abilities = {}
    local ok, err = pcall(function()
        if not CMan then return end

        -- If CMan has a lookups method, iterate it
        if CMan.cman_lookups then
            local lookups = CMan.cman_lookups()
            if type(lookups) == "table" then
                for _, cman in ipairs(lookups) do
                    local rank = CMan[cman.short_name]
                    if rank and rank > 0 then
                        local cman_data = CMan.data and CMan.data(cman.long_name)
                        local is_passive = cman_data and cman_data.type == "passive"
                        if not is_passive then
                            local usage = (cman_data and cman_data.usage) or cman.short_name
                            local stamina_cost = 0
                            if cman_data and cman_data.cost then
                                stamina_cost = cman_data.cost.stamina or 0
                            end
                            table.insert(abilities, Ability.new({
                                name = title_case(cman.long_name:gsub("_", " ")),
                                command = "cman " .. usage,
                                type = "cman",
                                resource_type = "stamina",
                                cost = stamina_cost,
                                roundtime = 3,
                                wiki_url = build_wiki_url(cman.long_name),
                                category = "Combat Maneuvers",
                                passive = is_passive,
                            }))
                        end
                    end
                end
            end
        else
            -- Fallback: well-known CMANs list
            local known_cmans = {
                "surge_of_strength", "disarm_weapon", "weapon_bonding", "tackle",
                "trip", "sweep", "feint", "bull_rush", "sunder_shield",
                "twin_hammerfist", "berserk", "quickstrike", "stun_maneuvers",
                "shield_bash", "shield_charge", "block_the_elements",
                "cheap_shot", "cutthroat", "hamstring",
                "predators_eye", "shadow_mastery", "silent_strike",
                "side_by_side", "spell_thieve", "vanish",
                "divert", "duck_and_weave", "evade",
                "flurry", "guardant_thew", "haymaker",
                "headbutt", "rage", "volley",
                "cripple", "grapple_mastery", "garrote",
                "spin_attack", "staggering_blow", "sunder_weapon",
                "trample", "war_cry",
            }
            for _, cman_name in ipairs(known_cmans) do
                local rank = CMan[cman_name]
                if rank and rank > 0 then
                    table.insert(abilities, Ability.new({
                        name = title_case(cman_name:gsub("_", " ")),
                        command = "cman " .. cman_name:gsub("_", " "),
                        type = "cman",
                        resource_type = "stamina",
                        cost = 0,
                        roundtime = 3,
                        wiki_url = build_wiki_url(cman_name),
                        category = "Combat Maneuvers",
                        passive = false,
                    }))
                end
            end
        end
        dbg("Found " .. #abilities .. " CMANs")
    end)
    if not ok then dbg("Error scanning CMANs: " .. tostring(err)) end
    return abilities
end

--- Generic technique scanner for Shield/Weapon/Armor
local function scan_techniques(module_obj, module_name, lookups_method, data_method, command_prefix, category_name, type_name)
    local abilities = {}
    if not module_obj then return abilities end

    local ok, err = pcall(function()
        if module_obj[lookups_method] then
            local lookups = module_obj[lookups_method]()
            if type(lookups) == "table" then
                for _, tech in ipairs(lookups) do
                    local rank = module_obj[tech.short_name]
                    if rank and rank > 0 then
                        local tech_data = module_obj[data_method] and module_obj[data_method](tech.long_name)
                        local is_passive = tech_data and tech_data.type == "passive"
                        if not is_passive then
                            local usage = (tech_data and tech_data.usage) or tech.short_name
                            local stamina_cost = 0
                            if tech_data and tech_data.cost then
                                stamina_cost = tech_data.cost.stamina or 0
                            end
                            table.insert(abilities, Ability.new({
                                name = title_case(tech.long_name:gsub("_", " ")),
                                command = command_prefix .. " " .. usage,
                                type = type_name,
                                resource_type = "stamina",
                                cost = stamina_cost,
                                roundtime = 3,
                                wiki_url = build_wiki_url(tech.long_name),
                                category = category_name,
                                passive = is_passive,
                            }))
                        end
                    end
                end
            end
        end
        dbg("Found " .. #abilities .. " " .. category_name)
    end)
    if not ok then dbg("Error scanning " .. module_name .. ": " .. tostring(err)) end
    return abilities
end

local function scan_shields()
    local mod = Shield or (Lich and Lich.Gemstone and Lich.Gemstone.Shield)
    return scan_techniques(mod, "Shield", "shield_lookups", "data", "shield", "Shield Specializations", "shield")
end

local function scan_weapons()
    local mod = Weapon or (Lich and Lich.Gemstone and Lich.Gemstone.Weapon)
    return scan_techniques(mod, "Weapon", "weapon_lookups", "data", "weapon", "Weapon Techniques", "weapon")
end

local function scan_armor()
    local mod = Armor or (Lich and Lich.Gemstone and Lich.Gemstone.Armor)
    return scan_techniques(mod, "Armor", "armor_lookups", "data", "armor", "Armor Specializations", "armor")
end

--- Scan Feats
local function scan_feats()
    local abilities = {}
    local ok, err = pcall(function()
        local mod = Feat or (Lich and Lich.Gemstone and Lich.Gemstone.Feat)
        if not mod then return end

        if mod.feat_lookups then
            local lookups = mod.feat_lookups()
            if type(lookups) == "table" then
                for _, feat in ipairs(lookups) do
                    local rank = mod[feat.short_name]
                    if rank and rank > 0 then
                        local feat_data = mod.data and mod.data(feat.long_name)
                        local is_passive = feat_data and feat_data.type == "passive"
                        -- Filter Kai's Strike (Voln passive)
                        if not is_passive and not feat.long_name:lower():find("kais_strike") then
                            local usage = (feat_data and feat_data.usage) or feat.short_name
                            local feat_resource = "none"
                            local feat_cost = 0
                            if feat_data and feat_data.cost then
                                local st = feat_data.cost.stamina or 0
                                local mn = feat_data.cost.mana or 0
                                if st > 0 then
                                    feat_resource = "stamina"
                                    feat_cost = st
                                elseif mn > 0 then
                                    feat_resource = "mana"
                                    feat_cost = mn
                                end
                            end
                            table.insert(abilities, Ability.new({
                                name = title_case(feat.long_name:gsub("_", " ")),
                                command = "feat " .. usage,
                                type = "feat",
                                resource_type = feat_resource,
                                cost = feat_cost,
                                roundtime = 3,
                                wiki_url = build_wiki_url(feat.long_name),
                                category = "Feats",
                                passive = is_passive,
                            }))
                        end
                    end
                end
            end
        end
        dbg("Found " .. #abilities .. " Feats")
    end)
    if not ok then dbg("Error scanning Feats: " .. tostring(err)) end
    return abilities
end

--- Scan Warcries (Warriors only)
local function scan_warcries()
    local abilities = {}
    local ok, err = pcall(function()
        local prof = Stats and Stats.profession or ""
        local prof_l = prof:lower()
        if not (prof_l:find("warrior") or prof_l:find("berserker")) then
            dbg("Skipping warcries - profession '" .. prof .. "' cannot use warcries")
            return
        end

        local mod = Warcry or (Lich and Lich.Gemstone and Lich.Gemstone.Warcry)
        if not mod then return end

        if mod.warcry_lookups then
            local lookups = mod.warcry_lookups()
            if type(lookups) == "table" then
                for _, warcry in ipairs(lookups) do
                    local rank = mod[warcry.short_name]
                    if rank and rank ~= false and rank > 0 then
                        local warcry_data = mod.data and mod.data(warcry.long_name)
                        if warcry_data then
                            local is_passive = warcry_data.type == "passive"
                            if not is_passive then
                                local usage = warcry_data.usage or warcry.short_name
                                local stamina_cost = 0
                                if warcry_data.cost then
                                    stamina_cost = warcry_data.cost.stamina or 0
                                end
                                table.insert(abilities, Ability.new({
                                    name = title_case(warcry.long_name:gsub("_", " ")),
                                    command = "warcry " .. usage,
                                    type = "warcry",
                                    resource_type = "stamina",
                                    cost = stamina_cost,
                                    roundtime = 3,
                                    wiki_url = build_wiki_url(warcry.long_name),
                                    category = "Warcries",
                                    passive = is_passive,
                                }))
                            end
                        end
                    end
                end
            end
        end
        dbg("Found " .. #abilities .. " Warcries")
    end)
    if not ok then dbg("Error scanning Warcries: " .. tostring(err)) end
    return abilities
end

--- Scan Society abilities (Voln, CoL, GoS)
local function scan_society()
    local abilities = {}
    local ok, err = pcall(function()
        if not Society then return end

        local status = Society.status or ""
        local rank = Society.rank or 0

        -- Voln
        if status == "Order of Voln" then
            local voln_symbols = {
                { name = "Symbol of Recognition",   command = "symbol of recognition",   rank_req = 1  },
                { name = "Symbol of Blessing",       command = "symbol of blessing",       rank_req = 2  },
                { name = "Symbol of Diminishment",   command = "symbol of diminishment",   rank_req = 4  },
                { name = "Symbol of Courage",        command = "symbol of courage",        rank_req = 5  },
                { name = "Symbol of Protection",     command = "symbol of protection",     rank_req = 6  },
                { name = "Symbol of Submission",     command = "symbol of submission",     rank_req = 7  },
                { name = "Symbol of Holiness",       command = "symbol of holiness",       rank_req = 9  },
                { name = "Symbol of Recall",         command = "symbol of recall",         rank_req = 10 },
                { name = "Symbol of Sleep",          command = "symbol of sleep",          rank_req = 11 },
                { name = "Symbol of Transcendence",  command = "symbol of transcendence",  rank_req = 12 },
                { name = "Symbol of Mana",           command = "symbol of mana",           rank_req = 13 },
                { name = "Symbol of Sight",          command = "symbol of sight",          rank_req = 14 },
                { name = "Symbol of Retribution",    command = "symbol of retribution",    rank_req = 15 },
                { name = "Symbol of Supremacy",      command = "symbol of supremacy",      rank_req = 16 },
                { name = "Symbol of Restoration",    command = "symbol of restoration",    rank_req = 17 },
                { name = "Symbol of Need",           command = "symbol of need",           rank_req = 18 },
                { name = "Symbol of Renewal",        command = "symbol of renewal",        rank_req = 19 },
                { name = "Symbol of Disruption",     command = "symbol of disruption",     rank_req = 20 },
                { name = "Kai's Smite",              command = "smite",                    rank_req = 21 },
                { name = "Symbol of Turning",        command = "symbol of turning",        rank_req = 22 },
                { name = "Symbol of Preservation",   command = "symbol of preservation",   rank_req = 23 },
                { name = "Symbol of Dreams",         command = "symbol of dreams",         rank_req = 24 },
                { name = "Symbol of Return",         command = "symbol of return",         rank_req = 25 },
                { name = "Symbol of Seeking",        command = "symbol of seeking",        rank_req = 26 },
            }
            for _, sym in ipairs(voln_symbols) do
                if rank >= sym.rank_req then
                    table.insert(abilities, Ability.new({
                        name = sym.name,
                        command = sym.command,
                        type = "society",
                        resource_type = "spirit",
                        cost = 1,
                        roundtime = 3,
                        wiki_url = build_wiki_url(sym.name),
                        category = "Society - Voln",
                        passive = false,
                    }))
                end
            end
        end

        -- Guardians of Sunfist
        if status == "Guardians of Sunfist" then
            local gos_sigils = {
                { name = "Sigil of Recognition",      command = "sigil of recognition",      rank_req = 1,  resource = "none",    cost = 0  },
                { name = "Sigil of Location",          command = "sigil of location",          rank_req = 2,  resource = "none",    cost = 0  },
                { name = "Sigil of Contact",           command = "sigil of contact",           rank_req = 3,  resource = "mana",    cost = 1  },
                { name = "Sigil of Resolve",           command = "sigil of resolve",           rank_req = 4,  resource = "stamina", cost = 5  },
                { name = "Sigil of Minor Bane",        command = "sigil of minor bane",        rank_req = 5,  resource = "stamina", cost = 3  },
                { name = "Sigil of Bandages",          command = "sigil of bandages",          rank_req = 6,  resource = "stamina", cost = 10 },
                { name = "Sigil of Defense",           command = "sigil of defense",           rank_req = 7,  resource = "stamina", cost = 5  },
                { name = "Sigil of Offense",           command = "sigil of offense",           rank_req = 8,  resource = "stamina", cost = 5  },
                { name = "Sigil of Distraction",       command = "sigil of distraction",       rank_req = 9,  resource = "stamina", cost = 10 },
                { name = "Sigil of Minor Protection",  command = "sigil of minor protection",  rank_req = 10, resource = "stamina", cost = 10 },
                { name = "Sigil of Focus",             command = "sigil of focus",             rank_req = 11, resource = "stamina", cost = 5  },
                { name = "Sigil of Intimidation",      command = "sigil of intimidation",      rank_req = 12, resource = "stamina", cost = 10 },
                { name = "Sigil of Mending",           command = "sigil of mending",           rank_req = 13, resource = "stamina", cost = 15 },
                { name = "Sigil of Concentration",     command = "sigil of concentration",     rank_req = 14, resource = "stamina", cost = 30 },
                { name = "Sigil of Major Bane",        command = "sigil of major bane",        rank_req = 15, resource = "stamina", cost = 10 },
                { name = "Sigil of Determination",     command = "sigil of determination",     rank_req = 16, resource = "stamina", cost = 30 },
                { name = "Sigil of Health",            command = "sigil of health",            rank_req = 17, resource = "stamina", cost = 20 },
                { name = "Sigil of Power",             command = "sigil of power",             rank_req = 18, resource = "stamina", cost = 50 },
                { name = "Sigil of Major Protection",  command = "sigil of major protection",  rank_req = 19, resource = "stamina", cost = 15 },
                { name = "Sigil of Escape",            command = "sigil of escape",            rank_req = 20, resource = "stamina", cost = 75 },
            }
            for _, sig in ipairs(gos_sigils) do
                if rank >= sig.rank_req then
                    table.insert(abilities, Ability.new({
                        name = sig.name,
                        command = sig.command,
                        type = "society",
                        resource_type = sig.resource,
                        cost = sig.cost,
                        roundtime = 3,
                        wiki_url = build_wiki_url(sig.name),
                        category = "Society - Guardians of Sunfist",
                        passive = false,
                    }))
                end
            end
        end

        -- Council of Light
        if status == "Council of Light" then
            local col_signs = {
                { name = "Sign of Recognition",   command = "sign of recognition",   rank_req = 1,  resource = "none",   cost = 0 },
                { name = "Sign of Signal",         command = "signal",                rank_req = 2,  resource = "none",   cost = 0 },
                { name = "Sign of Warding",        command = "sign of warding",       rank_req = 3,  resource = "mana",   cost = 1 },
                { name = "Sign of Striking",       command = "sign of striking",      rank_req = 4,  resource = "mana",   cost = 1 },
                { name = "Sign of Clotting",       command = "sign of clotting",      rank_req = 5,  resource = "mana",   cost = 1 },
                { name = "Sign of Thought",        command = "sign of thought",       rank_req = 6,  resource = "mana",   cost = 1 },
                { name = "Sign of Defending",      command = "sign of defending",     rank_req = 7,  resource = "mana",   cost = 2 },
                { name = "Sign of Smiting",        command = "sign of smiting",       rank_req = 8,  resource = "mana",   cost = 2 },
                { name = "Sign of Staunching",     command = "sign of staunching",    rank_req = 9,  resource = "mana",   cost = 1 },
                { name = "Sign of Deflection",     command = "sign of deflection",    rank_req = 10, resource = "mana",   cost = 3 },
                { name = "Sign of Hypnosis",       command = "sign of hypnosis",      rank_req = 11, resource = "spirit", cost = 1 },
                { name = "Sign of Swords",         command = "sign of swords",        rank_req = 12, resource = "spirit", cost = 1 },
                { name = "Sign of Shields",        command = "sign of shields",       rank_req = 13, resource = "spirit", cost = 1 },
                { name = "Sign of Dissipation",    command = "sign of dissipation",   rank_req = 14, resource = "spirit", cost = 1 },
                { name = "Sign of Healing",        command = "sign of healing",       rank_req = 15, resource = "spirit", cost = 2 },
                { name = "Sign of Madness",        command = "sign of madness",       rank_req = 16, resource = "spirit", cost = 3 },
                { name = "Sign of Possession",     command = "sign of possession",    rank_req = 17, resource = "spirit", cost = 4 },
                { name = "Sign of Wracking",       command = "sign of wracking",      rank_req = 18, resource = "spirit", cost = 5 },
                { name = "Sign of Darkness",       command = "sign of darkness",      rank_req = 19, resource = "spirit", cost = 6 },
                { name = "Sign of Hopelessness",   command = "sign of hopelessness",  rank_req = 20, resource = "none",   cost = 0 },
            }
            for _, sign in ipairs(col_signs) do
                if rank >= sign.rank_req then
                    table.insert(abilities, Ability.new({
                        name = sign.name,
                        command = sign.command,
                        type = "society",
                        resource_type = sign.resource,
                        cost = sign.cost,
                        roundtime = 3,
                        wiki_url = build_wiki_url(sign.name),
                        category = "Society - Council of Light",
                        passive = false,
                    }))
                end
            end
        end

        dbg("Found " .. #abilities .. " Society abilities")
    end)
    if not ok then dbg("Error scanning Society: " .. tostring(err)) end
    return abilities
end

--- Scan common verbs
local function scan_common_verbs()
    local verbs = {
        { name = "Hide",   command = "hide",   resource = "stamina", cost = 10, rt = 3 },
        { name = "Search", command = "search", resource = "stamina", cost = 5,  rt = 3 },
    }
    local abilities = {}
    for _, v in ipairs(verbs) do
        table.insert(abilities, Ability.new({
            name = v.name,
            command = v.command,
            type = "verb",
            resource_type = v.resource,
            cost = v.cost,
            roundtime = v.rt,
            wiki_url = build_wiki_url(v.name),
            category = "Verbs",
            passive = false,
        }))
    end
    dbg("Found " .. #abilities .. " common verbs")
    return abilities
end

--- Scan native resource buffs
local function scan_native_buffs()
    local buffs = {
        { name = "Stamina Burst",       command = "stamina burst",       resource = "stamina", cost = 0, rt = 0 },
        { name = "Stamina Second Wind",  command = "stamina second wind",  resource = "stamina", cost = 0, rt = 0 },
        { name = "Mana Spellup",        command = "mana spellup",        resource = "mana",    cost = 0, rt = 0 },
        { name = "Mana Pulse",          command = "mana pulse",          resource = "mana",    cost = 0, rt = 0 },
    }
    local abilities = {}
    for _, b in ipairs(buffs) do
        table.insert(abilities, Ability.new({
            name = b.name,
            command = b.command,
            type = "feat",
            resource_type = b.resource,
            cost = b.cost,
            roundtime = b.rt,
            wiki_url = "",
            category = "Native Buffs",
            passive = false,
        }))
    end
    dbg("Found " .. #abilities .. " native buffs")
    return abilities
end

--- Build item abilities from scripted items cache
local function build_item_abilities(scripted_items, item_charges_tracking, item_cooldown_tracking, item_upd_tracking)
    local abilities = {}
    scripted_items = scripted_items or {}
    item_charges_tracking = item_charges_tracking or {}
    item_cooldown_tracking = item_cooldown_tracking or {}
    item_upd_tracking = item_upd_tracking or {}

    for _, item in ipairs(scripted_items) do
        if item.status == "verified" then
            local verb_meta = item.verb_meta or {}
            local verbs = item.verbs or {}
            for _, verb in ipairs(verbs) do
                local meta = verb_meta[verb] or {}
                local freq_str = meta.freq_str or ""
                local parsed = (freq_str ~= "") and parse_frequency(freq_str) or nil

                -- Detect [verb] bracket and (verb) paren notation
                local raw_verb = verb
                local remove_first = false
                local get_first = false
                local bare_verb = raw_verb

                local bracket_match = raw_verb:match("^%[(.+)%]$")
                local paren_match = raw_verb:match("^%((.+)%)$")
                if bracket_match then
                    bare_verb = bracket_match
                    remove_first = true
                elseif paren_match then
                    bare_verb = paren_match
                    get_first = true
                end

                local ability_data = {
                    name = item.name .. " - " .. raw_verb,
                    command = bare_verb,
                    type = "item",
                    resource_type = "none",
                    cost = 0,
                    roundtime = 3,
                    wiki_url = "",
                    category = "Item Scripts",
                    passive = false,
                    remove_first = remove_first,
                    get_first = get_first,
                    item_long_name = item.long_name or "",
                    item_noun = item.noun or "",
                }

                if parsed then
                    if parsed.type == "frequency" then
                        ability_data.frequency_seconds = parsed.value
                    elseif parsed.type == "charges" then
                        ability_data.max_charges = parsed.value
                        ability_data.remaining_charges = parsed.value
                    elseif parsed.type == "upd" then
                        ability_data.max_upd = parsed.value
                        ability_data.remaining_upd = parsed.value
                    end
                end

                local a = Ability.new(ability_data)

                -- Restore runtime tracking state
                if a.max_charges then
                    local saved = item_charges_tracking[a.name]
                    if saved then a.remaining_charges = saved end
                end
                if a.max_upd then
                    local saved = item_upd_tracking[a.name]
                    if saved then
                        a.remaining_upd = saved.remaining
                        a.upd_last_reset = saved.last_reset
                    end
                    a:check_upd_reset()
                end
                if a.frequency_seconds then
                    local saved_cd = item_cooldown_tracking[a.name]
                    if saved_cd and saved_cd > os.time() then
                        a.item_cooldown_end = saved_cd
                    end
                end

                table.insert(abilities, a)
            end
        end
    end
    dbg("Built " .. #abilities .. " item abilities")
    return abilities
end

--- Full scan of all ability sources
local function scan_all_abilities(scripted_items, custom_verbs, item_charges_tracking, item_cooldown_tracking, item_upd_tracking)
    dbg("Scanning abilities for " .. (GameState.name or "unknown") .. "...")

    local abilities = {}

    -- Append results from each scanner
    local function append(list)
        for _, a in ipairs(list) do
            table.insert(abilities, a)
        end
    end

    append(scan_spells())
    append(scan_cmans())
    append(scan_shields())
    append(scan_weapons())
    append(scan_armor())
    append(scan_feats())
    append(scan_warcries())
    append(scan_society())
    append(scan_common_verbs())
    append(scan_native_buffs())

    -- Scripted items
    append(build_item_abilities(scripted_items or {}, item_charges_tracking, item_cooldown_tracking, item_upd_tracking))

    -- Custom verbs
    custom_verbs = custom_verbs or {}
    for _, verb_name in ipairs(custom_verbs) do
        table.insert(abilities, Ability.new({
            name = verb_name:sub(1, 1):upper() .. verb_name:sub(2),
            command = verb_name:lower(),
            type = "verb",
            resource_type = "none",
            cost = 0,
            roundtime = 3,
            wiki_url = "",
            category = "Verbs",
            passive = false,
        }))
    end

    -- Filter excluded
    local filtered = {}
    for _, a in ipairs(abilities) do
        if not EXCLUDED_ABILITIES[a.name:lower()] then
            table.insert(filtered, a)
        end
    end

    dbg("Found " .. #filtered .. " total abilities")
    return filtered
end

-- ============================================================================
-- SETTINGS MANAGEMENT
-- ============================================================================

local function create_default_boxes(n)
    n = n or 6
    local boxes = {}
    for i = 1, n do
        table.insert(boxes, { name = "Box " .. i, abilities = {} })
    end
    return boxes
end

local function load_settings()
    local raw = CharSettings[SETTINGS_KEY]
    local data
    if raw and raw ~= "" then
        local ok, decoded = pcall(Json.decode, raw)
        if ok and type(decoded) == "table" then
            data = decoded
        end
    end
    if not data then
        data = {}
    end

    -- Defaults
    data.abilities          = data.abilities or {}
    data.boxes              = data.boxes or create_default_boxes()
    data.num_boxes          = data.num_boxes or 6
    data.box_labels         = data.box_labels or {}
    data.scripted_items     = data.scripted_items or {}
    data.custom_verbs       = data.custom_verbs or {}
    data.ability_notes      = data.ability_notes or {}
    data.observed_rt        = data.observed_rt or {}
    data.locked             = data.locked or false
    data.wiki_confirm       = (data.wiki_confirm == nil) and true or data.wiki_confirm
    data.scan_version       = data.scan_version or 0
    data.item_charges_tracking  = data.item_charges_tracking or {}
    data.item_cooldown_tracking = data.item_cooldown_tracking or {}
    data.item_upd_tracking      = data.item_upd_tracking or {}

    -- Ensure box_labels has correct size
    while #data.box_labels < data.num_boxes do
        table.insert(data.box_labels, "(empty)")
    end

    return data
end

local function save_settings(data)
    CharSettings[SETTINGS_KEY] = Json.encode(data)
    CharSettings.save()
end

-- ============================================================================
-- RESOLVE ITEM TARGET
-- ============================================================================

--- Resolve the live game target for a scripted item
--- Priority: GameObj search by long_name (uses #id), then "my noun" fallback
local function resolve_item_target(item_long_name, item_noun, item_name)
    if item_long_name and item_long_name ~= "" then
        local all_objs = {}
        local rh = GameObj.right_hand()
        if rh then table.insert(all_objs, rh) end
        local lh = GameObj.left_hand()
        if lh then table.insert(all_objs, lh) end
        local ok1, inv = pcall(GameObj.inv)
        if ok1 and type(inv) == "table" then
            for _, obj in ipairs(inv) do table.insert(all_objs, obj) end
        end
        -- Search containers too if available
        local ok2, containers = pcall(function() return GameObj.containers and GameObj.containers() end)
        if ok2 and type(containers) == "table" then
            for _, items in pairs(containers) do
                if type(items) == "table" then
                    for _, obj in ipairs(items) do table.insert(all_objs, obj) end
                end
            end
        end
        for _, obj in ipairs(all_objs) do
            if obj.name == item_long_name then
                return "#" .. obj.id
            end
        end
    end
    local fallback = (item_noun and item_noun ~= "") and item_noun or (item_name or "")
    return "my " .. fallback
end

-- ============================================================================
-- ABILITY EXECUTION
-- ============================================================================

--- Find which container an item is in; returns container noun string or nil
local function find_item_container(item_long_name, item_noun)
    local ok, containers = pcall(function()
        return GameObj.containers and GameObj.containers()
    end)
    if not ok or type(containers) ~= "table" then return nil end
    for container_name, items in pairs(containers) do
        if type(items) == "table" then
            for _, obj in ipairs(items) do
                if (item_long_name and item_long_name ~= "" and obj.name == item_long_name)
                    or (item_noun and item_noun ~= "" and obj.noun == item_noun) then
                    -- container_name may be a full name like "a leather satchel"; use last word as noun
                    local container_noun = tostring(container_name):match("(%S+)$") or tostring(container_name)
                    return container_noun
                end
            end
        end
    end
    return nil
end

local last_click_time = 0
local last_cast_ability = nil
local cast_seen_rt = false
local last_cast_time = nil
local rt_end_snapshot = 0
local cast_rt_end_snapshot = 0
local prepped_spell = nil
local repeat_abilities = {} -- {[ability_name] = true}
local current_target = nil
local current_target_type = nil -- "enemy" or "player"

-- COWARDS tracking state
local departure_cache   = {}  -- {noun:lower() = timestamp} creatures that recently left
local engaged_enemy_nouns = {} -- {noun:lower() = true} enemies we've used abilities against
local prev_npc_nouns    = {}  -- {noun:lower() = true} NPC nouns seen in last update cycle
local cowards_list      = {}  -- {noun:lower() = true} fled enemies that were engaged

--- Record that an ability was just used for RT tracking
local function record_ability_cast(ability_name)
    last_cast_ability = ability_name
    cast_seen_rt = false
    last_cast_time = os.time()
    rt_end_snapshot = checkrt and checkrt() or 0
    cast_rt_end_snapshot = checkcastrt and checkcastrt() or 0
    dbg("[RT] Tracking cast: '" .. ability_name .. "'")
end

--- Execute an ability (send command to game)
local function execute_ability(ability, abilities, current_enemies)
    local now = os.time()
    if (now - last_click_time) < 1 then return false end -- click throttle (1s for non-GUI)
    last_click_time = now

    -- Don't execute in roundtime
    local game_rt = checkrt and checkrt() or 0
    local game_cast_rt = checkcastrt and checkcastrt() or 0
    if math.max(game_rt, game_cast_rt) > 0.5 then
        dbg("Still in roundtime, command not sent")
        return false
    end

    if not ability:available() then
        local info = {}
        if ability.type == "item" and ability.item_cooldown_end then
            table.insert(info, "item_cd=" .. string.format("%.1f", ability:item_cooldown_remaining()) .. "s")
        end
        if ability.max_charges then
            table.insert(info, "charges=" .. (ability.remaining_charges or 0) .. "/" .. ability.max_charges)
        end
        if ability.max_upd then
            table.insert(info, "upd=" .. (ability.remaining_upd or 0) .. "/" .. ability.max_upd)
        end
        if ability.passive then table.insert(info, "passive") end
        dbg("[EXEC] " .. ability.name .. " BLOCKED (" .. table.concat(info, ", ") .. ")")
        return false
    end

    -- Track current enemy target for COWARDS detection
    if current_target and current_target_type == "enemy" then
        engaged_enemy_nouns[current_target:lower()] = true
    end

    local command = ability.command

    -- Append target for spells
    if current_target and ability.type == "spell" then
        command = command .. " " .. current_target
    end

    -- Item: resolve target fresh
    if ability.type == "item" and ability.item_long_name then
        local item_target = resolve_item_target(ability.item_long_name, ability.item_noun, ability.name)
        command = ability.command .. " " .. item_target

        -- Remove-first items: remove -> waitrt -> verb -> waitrt -> wear
        if ability.remove_first then
            dbg("[EXEC] " .. ability.name .. " REMOVE-FIRST -> '" .. command .. "'")
            ability:record_item_use()
            record_ability_cast(ability.name)
            fput("remove " .. item_target)
            waitrt()
            pause(0.3)
            fput(command)
            waitrt()
            pause(0.3)
            fput("wear " .. item_target)
            return true
        end

        -- Get-first items: get from container -> verb -> return to container
        if ability.get_first then
            dbg("[EXEC] " .. ability.name .. " GET-FIRST -> '" .. command .. "'")
            ability:record_item_use()
            record_ability_cast(ability.name)
            local container_noun = find_item_container(ability.item_long_name, ability.item_noun)
            if container_noun then
                fput("get " .. item_target .. " from my " .. container_noun)
                waitrt()
                pause(0.3)
                fput(command)
                waitrt()
                pause(0.3)
                fput("put " .. item_target .. " in my " .. container_noun)
            else
                fput("get " .. item_target)
                waitrt()
                pause(0.3)
                fput(command)
                waitrt()
                pause(0.3)
                fput("stow " .. item_target)
            end
            return true
        end
    end

    -- Consume item charges/cooldown
    if ability.type == "item" then
        ability:record_item_use()
    end
    record_ability_cast(ability.name)

    dbg("[EXEC] " .. ability.name .. " (" .. ability.type .. ") -> '" .. command .. "' target=" .. tostring(current_target))
    put(command)
    return true
end

--- Match a command string against known abilities
local function match_ability_command(cmd_str, abilities)
    if not cmd_str or cmd_str == "" then return nil end
    local stripped = cmd_str:lower():match("^%s*(.-)%s*$")
    if stripped == "" then return nil end

    for _, a in ipairs(abilities) do
        local acmd = a.command:lower()
        -- Exact match or with target appended
        if stripped == acmd or stripped:sub(1, #acmd + 1) == acmd .. " " then
            return a
        end

        local parts = {}
        for word in acmd:gmatch("%S+") do table.insert(parts, word) end
        local typed_words = {}
        for word in stripped:gmatch("%S+") do table.insert(typed_words, word) end
        local typed_first = typed_words[1] or ""

        if #parts == 2 then
            local prefix, verb = parts[1], parts[2]
            -- Shorthand match (verb only)
            if stripped == verb or stripped:sub(1, #verb + 1) == verb .. " " then
                return a
            end
            -- Abbreviated verb (min 3 chars)
            if #typed_first >= 3 and verb:sub(1, #typed_first) == typed_first then
                return a
            end
            -- Abbreviated with prefix
            if typed_first == prefix and #typed_words >= 2 then
                local typed_verb = typed_words[2]
                if #typed_verb >= 3 and verb:sub(1, #typed_verb) == typed_verb then
                    return a
                end
            end
        else
            -- Single-word commands
            if #typed_first >= 3 and acmd:sub(1, #typed_first) == typed_first then
                return a
            end
        end
    end

    -- Prep/cast for spells
    local prep_num = stripped:match("^prep[a-z]*%s+(%d+)")
    if prep_num then
        for _, a in ipairs(abilities) do
            if a.type == "spell" and a.command:lower() == "incant " .. prep_num then
                prepped_spell = a.name
                return a
            end
        end
    end
    if stripped:match("^cast%s") or stripped == "cast" then
        if prepped_spell then
            for _, a in ipairs(abilities) do
                if a.name == prepped_spell then return a end
            end
        end
    end

    return nil
end

-- ============================================================================
-- SIMPLIFIED CATEGORY NAMES
-- ============================================================================

local function simplify_category(category)
    if not category then return "Unknown" end
    local spell_circle = category:match("^Spells %- (.+)$")
    if spell_circle then return spell_circle end
    if category == "Combat Maneuvers" then return "CMANs" end
    if category == "Shield Specializations" then return "Shields" end
    if category == "Weapon Techniques" then return "Weapons" end
    if category == "Armor Specializations" then return "Armor" end
    if category == "Item Scripts" then return "Gear" end
    local society = category:match("^Society %- (.+)$")
    if society then return society end
    return category
end

-- ============================================================================
-- STATUS ICONS
-- ============================================================================

local STATUS_ICONS = {
    { "stunned",       "*" },
    { "lying down",    "v" },
    { "laying down",   "v" },
    { "dead",          "X" },
    { "kneeling",      "k" },
    { "sitting",       "s" },
    { "webbed",        "w" },
    { "held in place", "w" },
    { "frozen",        "!" },
    { "paralyzed",     "!" },
    { "bleeding",      "~" },
    { "sleeping",      "z" },
}

local function status_icons_for(gameobj)
    local status_str = (gameobj.status or ""):lower()
    if status_str == "" then return "" end
    local icons = {}
    for _, entry in ipairs(STATUS_ICONS) do
        if status_str:find(entry[1], 1, true) then
            table.insert(icons, entry[2])
        end
    end
    if #icons == 0 then return "" end
    return " [" .. table.concat(icons) .. "]"
end

-- ============================================================================
-- GUI (Gui.* API)
-- ============================================================================

local function build_gui(abilities, settings)
    local boxes = settings.boxes
    local box_labels = settings.box_labels
    local num_boxes = settings.num_boxes
    local observed_rt = settings.observed_rt
    local ability_notes = settings.ability_notes
    local locked = settings.locked

    -- Main window
    local win = Gui.window("Combatical - " .. (GameState.name or "Character"), { width = 900, height = 700, resizable = true })
    local root = Gui.vbox()

    -- ---- Toolbar: Title + Lock + Refresh + Resource Bars ----
    local toolbar = Gui.hbox()

    local title = Gui.label("COMBATICAL")
    toolbar:add(title)

    -- Lock toggle
    local lock_btn = Gui.button(settings.locked and "[LOCKED]" or "[UNLOCKED]")
    lock_btn:on_click(function()
        settings.locked = not settings.locked
        lock_btn:set_text(settings.locked and "[LOCKED]" or "[UNLOCKED]")
        dbg("[LOCK] locked=" .. tostring(settings.locked))
    end)
    toolbar:add(lock_btn)

    -- Rescan button
    local refresh_btn = Gui.button("Rescan")
    refresh_btn:on_click(function()
        if settings.locked then echo("Locked - cannot rescan"); return end
        echo("Rescanning abilities...")
        local new_abs = scan_all_abilities(
            settings.scripted_items, settings.custom_verbs,
            settings.item_charges_tracking, settings.item_cooldown_tracking, settings.item_upd_tracking
        )
        settings.abilities = {}
        for _, a in ipairs(new_abs) do
            table.insert(settings.abilities, a:to_table())
        end
        settings.scan_version = SCAN_VERSION
        save_settings(settings)
        echo("Rescan complete: " .. #new_abs .. " abilities. Close/reopen window to apply.")
    end)
    toolbar:add(refresh_btn)

    -- Resource bars
    local hp_bar = Gui.progress(0)
    local hp_label = Gui.label("HP 0/0")
    local mp_bar = Gui.progress(0)
    local mp_label = Gui.label("MP 0/0")
    local st_bar = Gui.progress(0)
    local st_label = Gui.label("ST 0/0")
    local sp_bar = Gui.progress(0)
    local sp_label = Gui.label("SP 0/0")

    local bars_left = Gui.vbox()
    bars_left:add(hp_label)
    bars_left:add(hp_bar)
    bars_left:add(st_label)
    bars_left:add(st_bar)

    local bars_right = Gui.vbox()
    bars_right:add(mp_label)
    bars_right:add(mp_bar)
    bars_right:add(sp_label)
    bars_right:add(sp_bar)

    toolbar:add(bars_left)
    toolbar:add(bars_right)

    root:add(toolbar)
    root:add(Gui.separator())

    -- ---- Target display ----
    local target_row = Gui.hbox()

    -- Enemy targets
    local enemy_label = Gui.label("Enemies: (none)")
    target_row:add(enemy_label)

    -- Player targets
    local player_label = Gui.label("Players: (none)")
    target_row:add(player_label)

    -- Current target
    local target_display = Gui.label("Target: (none)")
    target_row:add(target_display)

    local clear_btn = Gui.button("Clear Target")
    clear_btn:on_click(function()
        current_target = nil
        current_target_type = nil
        target_display:set_text("Target: (none)")
    end)
    target_row:add(clear_btn)

    root:add(target_row)
    root:add(Gui.separator())

    -- ---- Ability Boxes (main area) ----
    local boxes_container = Gui.vbox()

    -- Build ability buttons for a box
    local ability_buttons = {} -- {ability_name = {label=, button=}}

    local function build_box_card(box_index)
        local box = boxes[box_index]
        if not box then return Gui.label("(error)") end
        local label_text = box_labels[box_index] or box.name or ("Box " .. box_index)
        local card = Gui.card({ title = label_text })

        local box_content = Gui.vbox()
        local box_abilities = box.abilities or {}

        if #box_abilities == 0 then
            box_content:add(Gui.label("(empty - assign abilities via setup)"))
        else
            for _, ability_name in ipairs(box_abilities) do
                -- Find the ability
                local ability = nil
                for _, a in ipairs(abilities) do
                    if a.name == ability_name then ability = a; break end
                end
                if ability and not ability.passive then
                    local rgb = ability:color()
                    local obs_rt = observed_rt[ability.name]
                    local base_rt = obs_rt or ability.roundtime
                    local rt_str = base_rt > 0 and (" (" .. base_rt .. "s)") or ""

                    -- Build display text
                    local display_text = ability.name .. rt_str
                    if ability:available() then
                        display_text = display_text .. " [ready]"
                    end

                    -- Charges/UPD display
                    if ability.type == "item" and ability.max_charges then
                        display_text = display_text .. " [" .. (ability.remaining_charges or 0) .. " charges]"
                    end
                    if ability.type == "item" and ability.max_upd then
                        ability:check_upd_reset()
                        display_text = display_text .. " [" .. (ability.remaining_upd or 0) .. "/" .. ability.max_upd .. " UPD]"
                    end

                    -- Note
                    local note = ability_notes[ability.name]
                    if note and note ~= "" then
                        display_text = display_text .. "  -- " .. note
                    end

                    local btn = Gui.button(display_text)
                    btn:on_click(function()
                        execute_ability(ability, abilities, GameObj.npcs())
                    end)
                    box_content:add(btn)

                    ability_buttons[ability.name] = { button = btn, ability = ability }
                end
            end
        end

        card:add(box_content)
        return card
    end

    -- Create boxes in rows of 3
    local row = nil
    for i = 1, num_boxes do
        if (i - 1) % 3 == 0 then
            if row then boxes_container:add(row) end
            row = Gui.hbox()
        end
        row:add(build_box_card(i))
    end
    if row then boxes_container:add(row) end

    local boxes_scroll = Gui.scroll(boxes_container)
    root:add(boxes_scroll)

    root:add(Gui.separator())

    -- ---- Unassigned Pool ----
    local pool_card = Gui.card({ title = "Unassigned Pool" })
    local pool_content = Gui.vbox()

    -- Get assigned ability names
    local assigned = {}
    for _, box in ipairs(boxes) do
        for _, name in ipairs(box.abilities or {}) do
            assigned[name] = true
        end
    end

    -- Group unassigned by category
    local categories = {}
    for _, ability in ipairs(abilities) do
        if not assigned[ability.name] and not ability.passive then
            local cat = simplify_category(ability.category)
            if not categories[cat] then categories[cat] = {} end
            table.insert(categories[cat], ability)
        end
    end

    local sorted_cats = {}
    for cat in pairs(categories) do table.insert(sorted_cats, cat) end
    table.sort(sorted_cats)

    if #sorted_cats == 0 then
        pool_content:add(Gui.label("All abilities assigned to boxes"))
    else
        for _, cat_name in ipairs(sorted_cats) do
            pool_content:add(Gui.section_header(cat_name .. " (" .. #categories[cat_name] .. ")"))
            for _, ability in ipairs(categories[cat_name]) do
                local obs_rt = observed_rt[ability.name]
                local base_rt = obs_rt or ability.roundtime
                local rt_str = base_rt > 0 and (" (" .. base_rt .. "s)") or ""
                local label_text = ability.name .. rt_str
                if ability.cost > 0 then
                    label_text = label_text .. " [" .. ability.cost .. " " .. ability.resource_type .. "]"
                end
                local btn = Gui.button(label_text)
                btn:on_click(function()
                    execute_ability(ability, abilities, GameObj.npcs())
                end)
                pool_content:add(btn)
                ability_buttons[ability.name] = { button = btn, ability = ability }
            end
        end
    end

    pool_card:add(Gui.scroll(pool_content))
    root:add(pool_card)

    win:set_root(root)
    win:show()

    return {
        win = win,
        hp_bar = hp_bar, hp_label = hp_label,
        mp_bar = mp_bar, mp_label = mp_label,
        st_bar = st_bar, st_label = st_label,
        sp_bar = sp_bar, sp_label = sp_label,
        enemy_label = enemy_label,
        player_label = player_label,
        target_display = target_display,
        ability_buttons = ability_buttons,
    }
end

--- Update resource bars
local function update_resource_bars(gui)
    if not gui then return end
    local hp = GameState.health or 0
    local max_hp = GameState.max_health or 1
    local mp = GameState.mana or 0
    local max_mp = GameState.max_mana or 1
    local st = GameState.stamina or 0
    local max_st = GameState.max_stamina or 1
    local sp = GameState.spirit or 0
    local max_sp = GameState.max_spirit or 1

    gui.hp_bar:set_value(max_hp > 0 and (hp / max_hp) or 0)
    gui.hp_label:set_text("HP " .. hp .. "/" .. max_hp)
    gui.mp_bar:set_value(max_mp > 0 and (mp / max_mp) or 0)
    gui.mp_label:set_text("MP " .. mp .. "/" .. max_mp)
    gui.st_bar:set_value(max_st > 0 and (st / max_st) or 0)
    gui.st_label:set_text("ST " .. st .. "/" .. max_st)
    gui.sp_bar:set_value(max_sp > 0 and (sp / max_sp) or 0)
    gui.sp_label:set_text("SP " .. sp .. "/" .. max_sp)
end

--- Update target display (enemies, players, COWARDS, current target)
local function update_target_display(gui)
    if not gui then return end

    local npcs = GameObj.npcs()
    local now = os.time()

    -- Build current NPC noun set
    local current_npc_nouns = {}
    for _, npc in ipairs(npcs) do
        current_npc_nouns[npc.noun:lower()] = true
    end

    -- Compute COWARDS: previously-engaged NPCs that left via departure_cache
    for noun in pairs(prev_npc_nouns) do
        if not current_npc_nouns[noun] and engaged_enemy_nouns[noun] then
            local dep_ts = departure_cache[noun]
            if dep_ts and (now - dep_ts) < 120 then
                cowards_list[noun] = true
            end
        end
    end
    -- Remove cowards that returned to the room
    for noun in pairs(cowards_list) do
        if current_npc_nouns[noun] then cowards_list[noun] = nil end
    end
    -- Expire old departure cache entries (> 120s)
    for noun, ts in pairs(departure_cache) do
        if (now - ts) > 120 then departure_cache[noun] = nil end
    end
    -- Update prev snapshot for next call
    prev_npc_nouns = current_npc_nouns

    -- Determine attacker noun for flash marker (>> prefix)
    local flash_noun = nil
    if last_attacker_id and last_attacker_time and (now - last_attacker_time) < 3 then
        for _, npc in ipairs(npcs) do
            if tostring(npc.id) == tostring(last_attacker_id) then
                flash_noun = npc.noun:lower()
                break
            end
        end
    end

    -- Build enemy label text
    local enemy_parts = {}
    for _, npc in ipairs(npcs) do
        local icons = status_icons_for(npc)
        local prefix = (flash_noun and npc.noun:lower() == flash_noun) and ">> " or ""
        table.insert(enemy_parts, prefix .. npc.noun .. icons)
    end
    -- Append COWARDS
    local coward_nouns = {}
    for noun in pairs(cowards_list) do table.insert(coward_nouns, noun) end
    if #coward_nouns > 0 then
        table.sort(coward_nouns)
        table.insert(enemy_parts, "| COWARDS: " .. table.concat(coward_nouns, ", "))
    end

    if #enemy_parts > 0 then
        gui.enemy_label:set_text("Enemies: " .. table.concat(enemy_parts, "  "))
    else
        gui.enemy_label:set_text("Enemies: (none)")
    end

    -- Players
    local pcs = GameObj.pcs()
    local player_parts = {}
    for _, pc in ipairs(pcs) do
        table.insert(player_parts, pc.noun)
    end
    if #player_parts > 0 then
        gui.player_label:set_text("Players: " .. table.concat(player_parts, ", "))
    else
        gui.player_label:set_text("Players: (none)")
    end

    -- Current target
    if current_target then
        gui.target_display:set_text("Target: " .. current_target .. " (" .. (current_target_type or "?") .. ")")
        -- Auto-clear if gone
        local found = false
        if current_target_type == "enemy" then
            for _, npc in ipairs(npcs) do
                if npc.noun == current_target then found = true; break end
            end
        elseif current_target_type == "player" then
            for _, pc in ipairs(pcs) do
                if pc.noun == current_target then found = true; break end
            end
        end
        if not found then
            current_target = nil
            current_target_type = nil
            gui.target_display:set_text("Target: (auto-cleared)")
        end
    end
end

--- Update ability button labels (RT countdown, cooldowns, availability)
local function update_ability_displays(gui, observed_rt)
    if not gui or not gui.ability_buttons then return end

    local game_rt = checkrt and checkrt() or 0
    local game_cast_rt = checkcastrt and checkcastrt() or 0
    local remaining = math.max(game_rt, game_cast_rt)

    -- RT tracking state machine
    if last_cast_ability then
        if not cast_seen_rt then
            local current_rt = checkrt and checkrt() or 0
            if current_rt > rt_end_snapshot + 0.5 then
                cast_seen_rt = true
                local obs = observed_rt[last_cast_ability]
                if not obs or math.ceil(remaining) < obs then
                    observed_rt[last_cast_ability] = math.ceil(remaining)
                end
            elseif last_cast_time and (os.time() - last_cast_time) > 8 then
                last_cast_ability = nil
                cast_seen_rt = false
                last_cast_time = nil
            end
        elseif remaining <= 0 then
            last_cast_ability = nil
            cast_seen_rt = false
            last_cast_time = nil
        end
    end

    for ability_name, entry in pairs(gui.ability_buttons) do
        local ability = entry.ability
        local btn = entry.button
        if ability and btn then
            local obs_rt = observed_rt[ability.name]
            local base_rt = obs_rt or ability.roundtime
            local rt_str = base_rt > 0 and (" (" .. base_rt .. "s)") or ""

            local display = ability.name .. rt_str

            -- Charges/UPD
            if ability.type == "item" and ability.max_charges then
                local rc = ability.remaining_charges or 0
                display = display .. " [" .. rc .. " chg]"
            end
            if ability.type == "item" and ability.max_upd then
                ability:check_upd_reset()
                local ru = ability.remaining_upd or 0
                display = display .. " [" .. ru .. "/" .. ability.max_upd .. " UPD]"
            end

            -- Item cooldown
            local item_cd = (ability.type == "item") and ability:item_cooldown_remaining() or 0

            -- Repeat indicator
            if repeat_abilities[ability.name] then
                display = display .. " [repeat]"
            end

            -- RT countdown
            if remaining > 0 and ability.name == last_cast_ability and cast_seen_rt then
                display = display .. " -- RT: " .. math.ceil(remaining) .. "s"
            elseif item_cd > 0 then
                display = display .. " -- CD: " .. format_duration(item_cd)
            elseif ability:available() then
                display = display .. " [ready]"
            else
                display = display .. " [cooldown]"
            end

            btn:set_text(display)
        end
    end
end

-- ============================================================================
-- SETTINGS GUI (setup command)
-- ============================================================================

local function open_settings_gui(settings, abilities)
    local win = Gui.window("Combatical Settings", { width = 500, height = 500, resizable = true })
    local root = Gui.vbox()

    local tabs = Gui.tab_bar({ "Boxes", "Items", "Verbs", "Notes", "About" })

    -- ---- Boxes Tab ----
    local boxes_tab = Gui.vbox()
    boxes_tab:add(Gui.section_header("Ability Box Management"))

    -- For each box, show a label editor and ability assignment
    for i = 1, settings.num_boxes do
        local box = settings.boxes[i]
        if not box then break end
        local label_text = settings.box_labels[i] or box.name or ("Box " .. i)

        local box_row = Gui.hbox()
        local box_label = Gui.label("Box " .. i .. ": " .. label_text)
        box_row:add(box_label)

        local edit_input = Gui.input({ text = label_text, placeholder = "Box label..." })
        edit_input:on_submit(function()
            local new_text = edit_input:get_text()
            if new_text == "" then new_text = "(empty)" end
            settings.box_labels[i] = new_text
            box_label:set_text("Box " .. i .. ": " .. new_text)
        end)
        box_row:add(edit_input)

        boxes_tab:add(box_row)

        -- Ability assignment: show current, allow adding by name
        local assign_input = Gui.input({ placeholder = "Type ability name to add..." })
        assign_input:on_submit(function()
            local name = assign_input:get_text()
            if name ~= "" then
                -- Find ability
                for _, a in ipairs(abilities) do
                    if a.name:lower() == name:lower() then
                        if not tbl_contains(box.abilities, a.name) then
                            -- Remove from other boxes
                            for _, other_box in ipairs(settings.boxes) do
                                local idx = tbl_index(other_box.abilities, a.name)
                                if idx then table.remove(other_box.abilities, idx) end
                            end
                            table.insert(box.abilities, a.name)
                            echo("Added " .. a.name .. " to Box " .. i)
                        end
                        break
                    end
                end
                assign_input:set_text("")
            end
        end)
        boxes_tab:add(assign_input)

        -- Show currently assigned
        if box.abilities and #box.abilities > 0 then
            boxes_tab:add(Gui.label("  Assigned: " .. table.concat(box.abilities, ", ")))
        end

        boxes_tab:add(Gui.separator())
    end

    -- Add/remove boxes
    local box_count_row = Gui.hbox()
    box_count_row:add(Gui.label("Number of boxes: " .. settings.num_boxes))
    local add_box_btn = Gui.button("+")
    add_box_btn:on_click(function()
        settings.num_boxes = settings.num_boxes + 1
        table.insert(settings.boxes, { name = "Box " .. settings.num_boxes, abilities = {} })
        table.insert(settings.box_labels, "(empty)")
        echo("Added Box " .. settings.num_boxes .. " (close and reopen settings to see it)")
    end)
    box_count_row:add(add_box_btn)
    local rem_box_btn = Gui.button("-")
    rem_box_btn:on_click(function()
        if settings.num_boxes > 1 then
            -- Clear abilities from removed box
            local removed_box = settings.boxes[settings.num_boxes]
            if removed_box then removed_box.abilities = {} end
            table.remove(settings.boxes, settings.num_boxes)
            table.remove(settings.box_labels, settings.num_boxes)
            settings.num_boxes = settings.num_boxes - 1
            echo("Removed last box (now " .. settings.num_boxes .. " boxes)")
        end
    end)
    box_count_row:add(rem_box_btn)
    boxes_tab:add(box_count_row)

    tabs:set_tab_content(1, Gui.scroll(boxes_tab))

    -- ---- Items Tab ----
    local items_tab = Gui.vbox()
    items_tab:add(Gui.section_header("Scripted Items"))
    items_tab:add(Gui.label("Add items by long name (e.g. 'a mithril spear')"))

    local item_name_input = Gui.input({ placeholder = "Item long name..." })
    local item_noun_input = Gui.input({ placeholder = "Item noun (e.g. spear)..." })
    local item_verb_input = Gui.input({ placeholder = "Verbs (comma separated, e.g. TURN,RUB,[PULL],(RAISE))..." })
    local item_freq_input = Gui.input({ placeholder = "Frequency per verb (e.g. 3h, 50 charges, 3UPD) or blank..." })

    items_tab:add(item_name_input)
    items_tab:add(item_noun_input)
    items_tab:add(item_verb_input)
    items_tab:add(item_freq_input)

    local add_item_btn = Gui.button("Add Item")
    add_item_btn:on_click(function()
        local long_name = item_name_input:get_text()
        if long_name == "" then echo("Enter item long name"); return end
        local noun = item_noun_input:get_text()
        if noun == "" then
            -- Derive noun from last word
            noun = long_name:match("(%S+)$") or long_name
        end
        local verbs_str = item_verb_input:get_text()
        local freq_str = item_freq_input:get_text()

        -- Parse verbs
        local verbs = {}
        for v in verbs_str:gmatch("[^,]+") do
            local trimmed = v:match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                table.insert(verbs, trimmed:upper())
            end
        end
        if #verbs == 0 then echo("Enter at least one verb"); return end

        -- Build verb_meta
        local verb_meta = {}
        if freq_str ~= "" then
            -- Apply same frequency to all verbs
            for _, v in ipairs(verbs) do
                verb_meta[v] = { freq_str = freq_str }
            end
        end

        -- Remove existing with same long_name
        local new_items = {}
        for _, item in ipairs(settings.scripted_items) do
            if (item.long_name or ""):lower() ~= long_name:lower() then
                table.insert(new_items, item)
            end
        end
        settings.scripted_items = new_items

        -- Display name: strip article
        local display_name = long_name:gsub("^[Aa]n? ", ""):gsub("^[Ss]ome ", ""):gsub("^[Tt]he ", "")

        table.insert(settings.scripted_items, {
            name = display_name,
            long_name = long_name,
            noun = noun,
            verbs = verbs,
            status = "verified",
            verb_meta = verb_meta,
        })
        echo("Added item: " .. display_name .. " (" .. table.concat(verbs, ", ") .. ")")
        item_name_input:set_text("")
        item_noun_input:set_text("")
        item_verb_input:set_text("")
        item_freq_input:set_text("")
    end)
    items_tab:add(add_item_btn)

    -- Right hand button
    local rh_btn = Gui.button("Fill from Right Hand")
    rh_btn:on_click(function()
        local rh = GameObj.right_hand()
        if rh then
            item_name_input:set_text(rh.name or "")
            item_noun_input:set_text(rh.noun or "")
            echo("Filled: " .. (rh.name or "?") .. " (noun: " .. (rh.noun or "?") .. ")")
        else
            echo("Nothing in right hand")
        end
    end)
    items_tab:add(rh_btn)

    items_tab:add(Gui.separator())
    items_tab:add(Gui.section_header("Current Items"))
    for _, item in ipairs(settings.scripted_items) do
        local verbs_text = table.concat(item.verbs or {}, ", ")
        items_tab:add(Gui.label((item.name or "?") .. " (" .. verbs_text .. ")"))
    end

    tabs:set_tab_content(2, Gui.scroll(items_tab))

    -- ---- Verbs Tab ----
    local verbs_tab = Gui.vbox()
    verbs_tab:add(Gui.section_header("Custom Verbs"))
    verbs_tab:add(Gui.label("Add basic game verbs to track as abilities"))

    local verb_input = Gui.input({ placeholder = "Enter verb name..." })
    local add_verb_btn = Gui.button("Add Verb")
    add_verb_btn:on_click(function()
        local name = verb_input:get_text():lower():match("^%s*(.-)%s*$")
        if name ~= "" then
            if not tbl_contains(settings.custom_verbs, name) then
                table.insert(settings.custom_verbs, name)
                echo("Added verb: " .. name)
            end
            verb_input:set_text("")
        end
    end)
    verbs_tab:add(verb_input)
    verbs_tab:add(add_verb_btn)
    verbs_tab:add(Gui.separator())
    for _, v in ipairs(settings.custom_verbs) do
        verbs_tab:add(Gui.label("  " .. v))
    end

    tabs:set_tab_content(3, Gui.scroll(verbs_tab))

    -- ---- Notes Tab ----
    local notes_tab = Gui.vbox()
    notes_tab:add(Gui.section_header("Ability Notes"))
    notes_tab:add(Gui.label("Add personal notes to any ability (shows in button text)"))
    notes_tab:add(Gui.separator())

    local note_ability_input = Gui.input({ placeholder = "Ability name (must match exactly)..." })
    local note_text_input = Gui.input({ placeholder = "Note text (leave blank to clear)..." })

    local add_note_btn = Gui.button("Save Note")
    add_note_btn:on_click(function()
        local aname = note_ability_input:get_text():match("^%s*(.-)%s*$")
        if aname == "" then echo("Enter an ability name"); return end
        -- Case-insensitive match to find real name
        local real_name = nil
        for _, a in ipairs(abilities) do
            if a.name:lower() == aname:lower() then real_name = a.name; break end
        end
        if not real_name then echo("No ability matching '" .. aname .. "' found"); return end
        local note = note_text_input:get_text():match("^%s*(.-)%s*$")
        if note == "" then
            settings.ability_notes[real_name] = nil
            echo("Cleared note for: " .. real_name)
        else
            settings.ability_notes[real_name] = note
            echo("Saved note for: " .. real_name .. " -> " .. note)
        end
        note_ability_input:set_text("")
        note_text_input:set_text("")
    end)

    notes_tab:add(note_ability_input)
    notes_tab:add(note_text_input)
    notes_tab:add(add_note_btn)
    notes_tab:add(Gui.separator())
    notes_tab:add(Gui.section_header("Current Notes"))

    -- Show existing notes
    local has_notes = false
    for aname, note in pairs(settings.ability_notes) do
        if note and note ~= "" then
            notes_tab:add(Gui.label("  " .. aname .. ": " .. note))
            has_notes = true
        end
    end
    if not has_notes then
        notes_tab:add(Gui.label("  (no notes saved)"))
    end

    tabs:set_tab_content(4, Gui.scroll(notes_tab))

    -- ---- About Tab ----
    local about_tab = Gui.vbox()
    about_tab:add(Gui.section_header("Combatical v1.3.1"))
    about_tab:add(Gui.label("Author: Kyrandos"))
    about_tab:add(Gui.label("Contact: EducatedBarbarian@proton.me"))
    about_tab:add(Gui.label(""))
    about_tab:add(Gui.label("Notes:"))
    about_tab:add(Gui.label("  - Click an ability button to execute it"))
    about_tab:add(Gui.label("  - Use ;combatical setup to configure boxes and items"))
    about_tab:add(Gui.label("  - [verb] notation: remove item, verb, wear again"))
    about_tab:add(Gui.label("  - (verb) notation: get from container, verb, return"))
    about_tab:add(Gui.label("  - Frequency formats: 3h4m30s, 50 charges, 3UPD"))
    about_tab:add(Gui.label("  - Wiki: use ;combatical wiki <ability name> to open wiki page"))
    about_tab:add(Gui.label("  - Repeat: use ;combatical repeat <ability name> to toggle auto-repeat"))
    about_tab:add(Gui.label("  - >> prefix in enemy list = recent attacker"))
    about_tab:add(Gui.label("  - COWARDS label = engaged enemy that fled"))
    about_tab:add(Gui.label(""))
    about_tab:add(Gui.label("Other scripts by Kyrandos:"))
    about_tab:add(Gui.label("  Loresang, VolnRestore2, Merchantical"))

    -- Wiki confirm toggle
    local wiki_toggle = Gui.toggle("Confirm before opening wiki links", settings.wiki_confirm ~= false)
    wiki_toggle:on_change(function()
        settings.wiki_confirm = wiki_toggle:get_checked()
    end)
    about_tab:add(wiki_toggle)

    -- Debug toggle
    local debug_toggle = Gui.toggle("Debug Mode", debug_mode)
    debug_toggle:on_change(function()
        debug_mode = debug_toggle:get_checked()
        echo("Debug mode " .. (debug_mode and "ON" or "OFF"))
    end)
    about_tab:add(debug_toggle)

    -- Reset button
    local reset_btn = Gui.button("Reset to Defaults")
    reset_btn:on_click(function()
        settings.boxes = create_default_boxes()
        settings.num_boxes = 6
        settings.box_labels = {}
        for i = 1, 6 do table.insert(settings.box_labels, "(empty)") end
        settings.locked = false
        settings.wiki_confirm = true
        settings.custom_verbs = {}
        settings.scripted_items = {}
        settings.ability_notes = {}
        settings.observed_rt = {}
        echo("Settings reset to defaults. Close and reopen to apply.")
    end)
    about_tab:add(reset_btn)

    tabs:set_tab_content(5, Gui.scroll(about_tab))

    root:add(tabs)

    -- Save button at bottom
    local save_btn = Gui.button("Save Settings")
    save_btn:on_click(function()
        save_settings(settings)
        echo("Settings saved.")
    end)
    root:add(save_btn)

    win:set_root(root)
    win:show()

    return win
end

-- ============================================================================
-- CLI COMMANDS
-- ============================================================================

local function cli_list(abilities)
    echo("=== Combatical - Combat Ability Manager ===")
    echo("Author: Kyrandos (v1.3.1)")
    echo("")
    echo("Abilities loaded: " .. #abilities)
    echo("")

    -- Group by category
    local categories = {}
    for _, ability in ipairs(abilities) do
        if not ability.passive then
            local cat = ability.category
            if not categories[cat] then categories[cat] = {} end
            table.insert(categories[cat], ability)
        end
    end

    local cat_names = {}
    for name in pairs(categories) do
        table.insert(cat_names, name)
    end
    table.sort(cat_names)

    for _, cat_name in ipairs(cat_names) do
        echo("--- " .. cat_name .. " ---")
        for _, ability in ipairs(categories[cat_name]) do
            local status = ""
            if ability.cost > 0 then
                status = " (" .. ability.resource_type .. ": " .. ability.cost .. ")"
            end
            if ability:available() then
                status = status .. " [ready]"
            end
            echo("  " .. ability.name .. status)
        end
        echo("")
    end
end

local function cli_use(name, abilities)
    if not name or name == "" then
        echo("Usage: ;combatical use <ability name>")
        return
    end
    local matched = match_ability_command(name, abilities)
    if matched then
        execute_ability(matched, abilities, GameObj.npcs())
    else
        echo("No ability matching '" .. name .. "' found.")
    end
end

-- ============================================================================
-- MAIN ENTRY POINT
-- ============================================================================

local args = Script.vars
local arg1 = (args[1] or ""):lower()

-- Debug mode from args
if arg1 == "debug" then
    debug_mode = true
    arg1 = (args[2] or ""):lower()
end

-- Wait for character login
if not GameState.name or GameState.name == "" then
    echo("Waiting for character login...")
    wait_while(function() return not GameState.name or GameState.name == "" end)
end

echo("Starting for character: " .. (GameState.name or "unknown"))

-- Load settings
local settings = load_settings()

-- Handle CLI commands
if arg1 == "reset" then
    CharSettings[SETTINGS_KEY] = nil
    CharSettings.save()
    echo("Settings reset. Restart combatical to use defaults.")
    return
end

-- Determine if we need to scan
local needs_scan = (#settings.abilities == 0) or (settings.scan_version < SCAN_VERSION) or (arg1 == "scan")

local abilities = {}
if needs_scan then
    dbg("Scanning all abilities...")
    abilities = scan_all_abilities(
        settings.scripted_items,
        settings.custom_verbs,
        settings.item_charges_tracking,
        settings.item_cooldown_tracking,
        settings.item_upd_tracking
    )
    -- Save scanned abilities
    settings.abilities = {}
    for _, a in ipairs(abilities) do
        table.insert(settings.abilities, a:to_table())
    end
    settings.scan_version = SCAN_VERSION
    save_settings(settings)
    echo("Scan complete - found " .. #abilities .. " abilities")
else
    -- Load from cache
    for _, t in ipairs(settings.abilities) do
        local a = Ability.from_table(t)
        if a and not EXCLUDED_ABILITIES[a.name:lower()] then
            table.insert(abilities, a)
        end
    end
    -- Rebuild item abilities fresh (for runtime tracking)
    local non_items = {}
    for _, a in ipairs(abilities) do
        if a.type ~= "item" then table.insert(non_items, a) end
    end
    abilities = non_items
    local item_abs = build_item_abilities(
        settings.scripted_items,
        settings.item_charges_tracking,
        settings.item_cooldown_tracking,
        settings.item_upd_tracking
    )
    for _, a in ipairs(item_abs) do
        table.insert(abilities, a)
    end
    dbg("Loaded " .. #abilities .. " abilities from cache")
end

-- Handle scan-only mode
if arg1 == "scan" then
    echo("Scan complete. " .. #abilities .. " abilities found.")
    return
end

-- Handle list mode
if arg1 == "list" then
    cli_list(abilities)
    return
end

-- Handle use mode
if arg1 == "use" then
    local rest = args[0] or ""
    local use_name = rest:match("use%s+(.+)")
    cli_use(use_name or (args[2] or ""), abilities)
    return
end

-- Handle wiki mode
if arg1 == "wiki" then
    local rest = args[0] or ""
    local wiki_name = rest:match("wiki%s+(.+)") or (args[2] or "")
    if wiki_name == "" then
        echo("Usage: ;combatical wiki <ability name>")
    else
        for _, a in ipairs(abilities) do
            if a.name:lower() == wiki_name:lower() then
                local url = a.wiki_url ~= "" and a.wiki_url or build_wiki_url(a.name)
                echo("Wiki: " .. url)
                return
            end
        end
        echo("No ability matching '" .. wiki_name .. "'")
    end
    return
end

-- Handle repeat toggle mode (CLI version; in GUI use the main window)
if arg1 == "repeat" then
    local rest = args[0] or ""
    local rep_name = rest:match("repeat%s+(.+)") or (args[2] or "")
    if rep_name == "" then
        echo("Usage: ;combatical repeat <ability name>")
        local active = {}
        for n in pairs(repeat_abilities) do table.insert(active, n) end
        if #active > 0 then
            echo("Currently repeating: " .. table.concat(active, ", "))
        end
    else
        local found = false
        for _, a in ipairs(abilities) do
            if a.name:lower() == rep_name:lower() then
                found = true
                if repeat_abilities[a.name] then
                    repeat_abilities[a.name] = nil
                    echo("Repeat OFF: " .. a.name)
                else
                    repeat_abilities[a.name] = true
                    echo("Repeat ON: " .. a.name)
                end
                break
            end
        end
        if not found then echo("No ability matching '" .. rep_name .. "'") end
    end
    return
end

-- Handle setup mode (settings GUI, then return)
if arg1 == "setup" then
    local setup_win = open_settings_gui(settings, abilities)
    Gui.wait(setup_win, "close")
    -- Re-save after setup closes
    save_settings(settings)
    -- Rescan with updated settings
    abilities = scan_all_abilities(
        settings.scripted_items,
        settings.custom_verbs,
        settings.item_charges_tracking,
        settings.item_cooldown_tracking,
        settings.item_upd_tracking
    )
    settings.abilities = {}
    for _, a in ipairs(abilities) do
        table.insert(settings.abilities, a:to_table())
    end
    settings.scan_version = SCAN_VERSION
    save_settings(settings)
    echo("Settings saved. " .. #abilities .. " abilities after rescan.")
    return
end

-- ============================================================================
-- MAIN GUI MODE (default)
-- ============================================================================

local gui = build_gui(abilities, settings)

-- Cleanup hook
before_dying(function()
    dbg("Shutting down")
    DownstreamHook.remove("combatical_attack_monitor")
    UpstreamHook.remove("combatical_cmd_monitor")
    -- Save item tracking state
    settings.item_charges_tracking = {}
    settings.item_cooldown_tracking = {}
    settings.item_upd_tracking = {}
    for _, a in ipairs(abilities) do
        if a.type == "item" then
            if a.max_charges and a.remaining_charges then
                settings.item_charges_tracking[a.name] = a.remaining_charges
            end
            if a.item_cooldown_end and a.item_cooldown_end > os.time() then
                settings.item_cooldown_tracking[a.name] = a.item_cooldown_end
            end
            if a.max_upd then
                settings.item_upd_tracking[a.name] = {
                    remaining = a.remaining_upd,
                    last_reset = a.upd_last_reset,
                }
            end
        end
    end
    settings.observed_rt = settings.observed_rt or {}
    settings.abilities = {}
    for _, a in ipairs(abilities) do
        table.insert(settings.abilities, a:to_table())
    end
    save_settings(settings)
    echo("Settings saved on exit")
end)

-- Install downstream hook for attacker detection
local attack_pattern = "swings|claws|bites|charges|hurls|lunges|thrusts|slashes|swipes|punches|kicks|fires|gestures|channels|casts|directs|throws|pounds|smashes|attacks|strikes"
local last_attacker_id = nil
local last_attacker_time = nil

DownstreamHook.add("combatical_attack_monitor", function(xml_line)
    -- Try to capture attacker ID from XML
    local id = xml_line:match('<a exist="(%-?%d+)" noun="[^"]*">[^<]*</a>')
    if id then
        -- Check if line contains attack verb
        for verb in attack_pattern:gmatch("[^|]+") do
            if xml_line:find(verb, 1, true) then
                last_attacker_id = id
                last_attacker_time = os.time()
                break
            end
        end
    end
    return xml_line
end)

-- Install upstream hook for command detection
UpstreamHook.add("combatical_cmd_monitor", function(cmd)
    local stripped = cmd:lower():match("^%s*(.-)%s*$") or ""
    stripped = stripped:gsub("^<c>", ""):match("^%s*(.-)%s*$") or ""
    if stripped ~= "" then
        local matched = match_ability_command(stripped, abilities)
        if matched then
            if last_cast_ability ~= matched.name then
                dbg("[HOOK] Matched: " .. matched.name)
                if matched.type == "item" then matched:record_item_use() end
                record_ability_cast(matched.name)
            end
        else
            -- Unrecognized command: clear stale RT tracking
            if last_cast_ability and cast_seen_rt then
                dbg("[HOOK] Unmatched '" .. stripped .. "', clearing stale RT for '" .. last_cast_ability .. "'")
                last_cast_ability = nil
                cast_seen_rt = false
                last_cast_time = nil
            end
        end
    end
    return cmd
end)

echo("Window open - close to exit. Use ;combatical setup for configuration.")

-- ============================================================================
-- MAIN LOOP: game line processing + periodic updates
-- ============================================================================

local last_autosave = os.time()
local last_update = os.time()
local window_open = true

-- Set close handler
gui.win:on_close(function()
    window_open = false
end)

while window_open do
    local line = get()
    if not line then
        -- get() returned nil, check if window still open
        if not window_open then break end
        pause(0.1)
    else
        -- Detect roundtime from game output
        local rt_val = line:match("^Roundtime: (%d+) sec%.$") or line:match("^Cast Roundtime (%d+) Seconds?%.")
        if rt_val then
            rt_val = tonumber(rt_val)
            if last_cast_ability and not cast_seen_rt then
                cast_seen_rt = true
                local obs = settings.observed_rt[last_cast_ability]
                if not obs or rt_val < obs then
                    settings.observed_rt[last_cast_ability] = rt_val
                end
                dbg("[GET] RT confirmed for " .. last_cast_ability .. ": " .. rt_val .. "s")
            end
        end

        -- Detect creature departures for COWARDS tracking
        local creature, direction = line:match("^[Aa]n? (.+) just went (.+)%.$")
        if not creature then
            creature, direction = line:match("^[Tt]he (.+) just went (.+)%.$")
        end
        if creature and direction then
            -- Store departure; noun is last word of creature name
            local noun = creature:match("(%S+)$") or creature
            departure_cache[noun:lower()] = os.time()
            -- Also store full name in case noun matching fails
            departure_cache[creature:lower()] = os.time()
            dbg("[DEPART] " .. creature .. " -> " .. direction)
        end

        -- Detect attacks for flash info
        if line:match("^[Aa]n? .+ " .. "swings") or
           line:match("^[Aa]n? .+ " .. "claws") or
           line:match("^[Aa]n? .+ " .. "bites") or
           line:match("^[Aa]n? .+ " .. "charges") or
           line:match("^[Aa]n? .+ " .. "lunges") or
           line:match("^[Aa]n? .+ " .. "thrusts") or
           line:match("^[Aa]n? .+ " .. "gestures") then
            -- Attack detected (flash tracking would update GUI labels here)
            dbg("[ATTACK] " .. line:sub(1, 60))
        end

        -- Detect cooldown expiry
        local ready_name = line:match("^(%w[%w%s]+) is ready for use%.$")
        if ready_name then
            dbg("[COOLDOWN] Ready: " .. ready_name)
        end
    end

    -- Periodic updates (every 250ms equivalent)
    local now = os.time()

    -- Update GUI displays
    local ok, err = pcall(function()
        update_resource_bars(gui)
        update_target_display(gui)
        update_ability_displays(gui, settings.observed_rt)
    end)
    if not ok then
        dbg("Update error: " .. tostring(err))
    end

    -- Auto-repeat: fire abilities when RT clears
    if next(repeat_abilities) then
        local game_rt = checkrt and checkrt() or 0
        local game_cast_rt = checkcastrt and checkcastrt() or 0
        if math.max(game_rt, game_cast_rt) <= 0 then
            for ability_name in pairs(repeat_abilities) do
                for _, a in ipairs(abilities) do
                    if a.name == ability_name and a:available() then
                        execute_ability(a, abilities, GameObj.npcs())
                        break -- One per tick
                    end
                end
                break -- Only fire one per tick
            end
        end
    end

    -- Periodic autosave
    if (now - last_autosave) >= AUTOSAVE_INTERVAL then
        local ok2, err2 = pcall(function()
            settings.item_charges_tracking = {}
            settings.item_cooldown_tracking = {}
            settings.item_upd_tracking = {}
            for _, a in ipairs(abilities) do
                if a.type == "item" then
                    if a.max_charges and a.remaining_charges then
                        settings.item_charges_tracking[a.name] = a.remaining_charges
                    end
                    if a.item_cooldown_end and a.item_cooldown_end > os.time() then
                        settings.item_cooldown_tracking[a.name] = a.item_cooldown_end
                    end
                    if a.max_upd then
                        settings.item_upd_tracking[a.name] = {
                            remaining = a.remaining_upd,
                            last_reset = a.upd_last_reset,
                        }
                    end
                end
            end
            save_settings(settings)
            dbg("Autosaved settings")
        end)
        if not ok2 then dbg("Autosave error: " .. tostring(err2)) end
        last_autosave = now
    end
end

echo("Script exiting cleanly")
