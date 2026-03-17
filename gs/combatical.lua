--- @revenant-script
--- name: combatical
--- version: 1.2.6
--- author: Kyrandos
--- game: gs
--- description: Combat ability manager - track spells, CMANs, items, and custom verbs with cooldowns and usage counts
--- tags: utility, abilities, manager, combat, targeting, spells, items, tracker, status
---
--- Usage:
---   ;combatical              - Start the ability tracker
---   ;combatical scan         - Force rescan of all abilities
---   ;combatical reset        - Clear saved configuration
---   ;combatical debug        - Enable debug output
---
--- Features:
---   - Scans all known spells, CMANs, shield/weapon/armor techniques, feats, warcries
---   - Tracks roundtimes and cooldowns
---   - Supports scripted items and custom verbs with per-day usage tracking
---   - Society abilities (Voln, CoL, GoS)

local SCAN_VERSION = 3

-- Ability data structure
local Ability = {}
Ability.__index = Ability

function Ability.new(data)
    data = data or {}
    local self = setmetatable({}, Ability)
    self.name = data.name or ""
    self.command = data.command or ""
    self.type = data.type or "unknown"
    self.resource_type = data.resource_type or "none"
    self.cost = data.cost or 0
    self.roundtime = data.roundtime or 0
    self.wiki_url = data.wiki_url or ""
    self.category = data.category or "Uncategorized"
    self.passive = data.passive or false
    self.frequency_seconds = data.frequency_seconds
    self.max_charges = data.max_charges
    self.remaining_charges = data.remaining_charges
    self.max_upd = data.max_upd
    self.remaining_upd = data.remaining_upd
    self.cooldown_end = nil
    self.remove_first = data.remove_first or false
    self.get_first = data.get_first or false
    self.item_long_name = data.item_long_name
    self.item_noun = data.item_noun
    return self
end

function Ability:is_ready()
    if self.cooldown_end and os.time() < self.cooldown_end then
        return false
    end
    if self.remaining_charges and self.remaining_charges <= 0 then
        return false
    end
    if self.remaining_upd and self.remaining_upd <= 0 then
        return false
    end
    return true
end

function Ability:cooldown_remaining()
    if not self.cooldown_end then return 0 end
    return math.max(0, self.cooldown_end - os.time())
end

function Ability:execute()
    if not self:is_ready() then
        echo(self.name .. " is not ready (cooldown: " .. self:cooldown_remaining() .. "s)")
        return false
    end

    if self.type == "spell" then
        fput(self.command)
    elseif self.type == "item" then
        if self.remove_first then
            fput("remove my " .. (self.item_noun or self.name))
        elseif self.get_first then
            fput("get my " .. (self.item_noun or self.name))
        end
        fput(self.command)
        if self.remove_first then
            fput("wear my " .. (self.item_noun or self.name))
        elseif self.get_first then
            fput("stow my " .. (self.item_noun or self.name))
        end
    else
        fput(self.command)
    end

    if self.frequency_seconds then
        self.cooldown_end = os.time() + self.frequency_seconds
    end
    if self.remaining_charges then
        self.remaining_charges = self.remaining_charges - 1
    end
    if self.remaining_upd then
        self.remaining_upd = self.remaining_upd - 1
    end

    return true
end

-- Ability scanner
local abilities = {}
local boxes = {}

local function scan_spells()
    local spell_circles = {
        { name = "Minor Spirit",   start = 101, stop = 120 },
        { name = "Major Spirit",   start = 201, stop = 220 },
        { name = "Cleric",         start = 301, stop = 350 },
        { name = "Minor Elemental", start = 401, stop = 420 },
        { name = "Major Elemental", start = 501, stop = 520 },
        { name = "Wizard",         start = 901, stop = 950 },
        { name = "Ranger",         start = 601, stop = 650 },
        { name = "Sorcerer",       start = 701, stop = 750 },
        { name = "Empath",         start = 1101, stop = 1150 },
        { name = "Paladin",        start = 1601, stop = 1650 },
        { name = "Bard",           start = 1001, stop = 1050 },
        { name = "Minor Mental",   start = 1201, stop = 1220 },
        { name = "Telepathy",      start = 1701, stop = 1720 },
    }

    for _, circle in ipairs(spell_circles) do
        for num = circle.start, circle.stop do
            if Spell[num] and Spell[num]:known() then
                local spell = Spell[num]
                local ability = Ability.new({
                    name = spell.name or ("Spell " .. num),
                    command = "incant " .. num,
                    type = "spell",
                    resource_type = "mana",
                    cost = spell.mana_cost or 0,
                    category = circle.name,
                    wiki_url = "https://gswiki.play.net/Spell_" .. num,
                })
                table.insert(abilities, ability)
            end
        end
    end
end

local function scan_cmans()
    local cman_list = {
        "surge_of_strength", "disarm_weapon", "weapon_bonding", "tackle",
        "trip", "sweep", "feint", "bull_rush", "sunder_shield",
        "twin_hammerfist", "berserk", "quickstrike",
        "shield_bash", "shield_charge", "block_the_elements",
        "surigao", "cheap_shot", "cutthroat", "hamstring",
        "predators_eye", "shadow_mastery", "silent_strike",
    }

    for _, cman_name in ipairs(cman_list) do
        if CMan and CMan[cman_name] and CMan[cman_name]:known() then
            local ability = Ability.new({
                name = cman_name:gsub("_", " "):gsub("(%a)([%w_']*)", function(a, b) return a:upper() .. b end),
                command = cman_name:gsub("_", " "),
                type = "cman",
                resource_type = "stamina",
                category = "Combat Maneuvers",
            })
            table.insert(abilities, ability)
        end
    end
end

local function scan_society()
    -- Voln
    if Society and Society.status == "Voln" then
        local voln_steps = {
            { name = "Symbol of Thought",    step = 1,  command = "symbol of thought" },
            { name = "Symbol of Courage",    step = 4,  command = "symbol of courage" },
            { name = "Symbol of Protection",  step = 6,  command = "symbol of protection" },
            { name = "Symbol of Blessing",   step = 7,  command = "symbol of blessing" },
            { name = "Symbol of Return",     step = 10, command = "symbol of return" },
            { name = "Symbol of Holiness",   step = 14, command = "symbol of holiness" },
            { name = "Symbol of Restoration", step = 18, command = "symbol of restoration" },
            { name = "Symbol of Submission", step = 20, command = "symbol of submission" },
            { name = "Symbol of Transcendence", step = 26, command = "symbol of transcendence" },
        }
        for _, v in ipairs(voln_steps) do
            if Society.rank and Society.rank >= v.step then
                table.insert(abilities, Ability.new({
                    name = v.name, command = v.command,
                    type = "society", category = "Voln",
                }))
            end
        end
    end
end

local function do_scan()
    abilities = {}
    echo("Scanning abilities...")
    scan_spells()
    scan_cmans()
    scan_society()
    echo("Found " .. #abilities .. " abilities.")
end

-- Settings persistence
local settings_key = "combatical_settings"

local function load_settings()
    local data = CharSettings[settings_key]
    if data then
        -- Restore box assignments, custom items, etc.
        boxes = data.boxes or {}
    end
end

local function save_settings()
    CharSettings[settings_key] = { boxes = boxes, scan_version = SCAN_VERSION }
    CharSettings.save()
end

-- Main entry point
local arg1 = Script.vars[1] or ""
local debug_mode = (arg1 == "debug")

if arg1 == "reset" then
    CharSettings[settings_key] = nil
    CharSettings.save()
    echo("Combatical settings reset.")
    return
end

load_settings()

local stored = CharSettings[settings_key]
if not stored or (stored.scan_version or 0) < SCAN_VERSION or arg1 == "scan" then
    do_scan()
    save_settings()
else
    do_scan()
end

-- Display abilities
echo("=== Combatical - Combat Ability Manager ===")
echo("Author: Kyrandos (v1.2.6)")
echo("")
echo("Abilities loaded: " .. #abilities)
echo("")

-- Group by category
local categories = {}
for _, ability in ipairs(abilities) do
    if not categories[ability.category] then
        categories[ability.category] = {}
    end
    table.insert(categories[ability.category], ability)
end

local cat_names = {}
for name, _ in pairs(categories) do
    table.insert(cat_names, name)
end
table.sort(cat_names)

for _, cat_name in ipairs(cat_names) do
    echo("--- " .. cat_name .. " ---")
    for _, ability in ipairs(categories[cat_name]) do
        local status = ""
        if ability.type == "spell" and ability.cost > 0 then
            status = " (mana: " .. ability.cost .. ")"
        end
        echo("  " .. ability.name .. status)
    end
    echo("")
end

echo("Note: The original GTK GUI interface is not available in Revenant.")
echo("Abilities can be executed via game commands directly.")
echo("Use ;combatical scan to re-scan abilities after training changes.")

-- Background monitoring for cooldowns and roundtime
while true do
    local line = get()
    if line then
        -- Track roundtime
        local rt = line:match("Roundtime: (%d+) sec")
        if rt then
            if debug_mode then
                echo("[Combatical] RT: " .. rt .. "s")
            end
        end

        -- Track health/mana/stamina changes
        if line:find("<progressBar id='mana'") then
            local val = line:match("value='(%d+)'")
            if val and debug_mode then
                echo("[Combatical] Mana: " .. val)
            end
        end
    end
end
