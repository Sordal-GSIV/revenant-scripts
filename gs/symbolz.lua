--- @revenant-script
--- name: symbolz
--- version: 2.0.0
--- author: elanthia-online
--- contributors: Ifor Get, SpiffyJr, Tillmen
--- game: gs
--- description: Voln symbol management -- keeps symbols active with auto-cast
--- tags: voln,symbols,society
--- @lic-certified: complete 2026-03-19
---
--- Original Lich5 authors: Ifor Get (original), SpiffyJr, Tillmen, Elanthia-Online (GTK updates)
--- Ported to Revenant Lua from symbolz.lic v2.0.0
---
--- Changelog (from Lich5):
---   v2.0.0 (2025-10-13) - Refactored OOP architecture, YAML->JSON settings
---   v1.1.3 (2025-03-19) - Remove deprecated calls
---   v1.1.2 (2025-01-22) - Minor GTK3 code cleanup
---   v1.1.1 (2023-11-27) - Rubocop cleanup
---   v1.1.0 (2021-03-01) - GTK3 support in Lich5
---   v1.0.0 (2020-03-20) - Original baseline release
---
--- Usage:
---   ;symbolz              - Run symbol maintenance loop
---   ;symbolz setup        - Open settings window
---   ;symbolz options      - Open settings window (alias)
---   ;symbolz help         - Show help

require("lib/spell_casting")

local VERSION = "2.0.0"

--------------------------------------------------------------------------------
-- Symbol definitions (insertion order preserved for GUI display)
--------------------------------------------------------------------------------

-- Ordered list of spell IDs for consistent GUI display (matches original Ruby order)
local SYMBOL_ORDER = { "9806", "9805", "9816", "9815", "9813", "9812", "9819" }

local SYMBOLS = {
    ["9806"] = {
        name    = "Protection",
        desc    = "Symbol of Protection: +26 to DS and +13 TD",
        tooltip = "31 Favor - Stackable",
        auto    = true,
    },
    ["9805"] = {
        name    = "Courage",
        desc    = "Symbol of Courage: +26 to AS",
        tooltip = "31 Favor - Stackable",
        auto    = true,
    },
    ["9816"] = {
        name    = "Supremacy",
        desc    = "Symbol of Supremacy: +13 to AS",
        tooltip = nil,
        auto    = true,
    },
    ["9815"] = {
        name    = "Retribution",
        desc    = "Symbol of Retribution: Reactive Flares When Hit By Undead",
        tooltip = nil,
        auto    = true,
    },
    ["9813"] = {
        name    = "Mana",
        desc    = "Symbol of Mana: Gives 50 Mana",
        tooltip = "Activates at 40% mana - 5 min cooldown",
        auto    = false,
    },
    ["9812"] = {
        name    = "Transcendence",
        desc    = "Symbol of Transcendence: Makes You Non-Corporeal",
        tooltip = "Activates when stunned/webbed/bound - Lasts 30sec, 3min cooldown, 10min if emergency",
        auto    = false,
    },
    ["9819"] = {
        name    = "Renewal",
        desc    = "Symbol of Renewal: Gives 1 Spirit, Can Use Every 2min",
        tooltip = "Activates at 80% spirit, uses until spirit is back at 100%",
        auto    = false,
    },
}

-- Spell effect IDs for conditional symbols (used to check if effect is already active)
local SPELL_EFFECTS = {
    ["9813"] = 9048,  -- Mana effect
    ["9812"] = 9049,  -- Transcendence effect
    ["9819"] = 9050,  -- Renewal effect
}

local FORBIDDEN_ROOMS = {
    "The Belly of the Beast",
    "Ooze, Innards",
    "Temporal Rift",
}

local MANA_THRESHOLD   = 40  -- cast Mana symbol when below this percent
local SPIRIT_THRESHOLD = 80  -- cast Renewal symbol when below this percent

--------------------------------------------------------------------------------
-- Settings (per-character via CharSettings)
--------------------------------------------------------------------------------

local function load_settings()
    local raw = CharSettings.symbolz
    if raw then
        local ok, data = pcall(Json.decode, raw)
        if ok and type(data) == "table" then return data end
    end
    local defaults = {}
    for id in pairs(SYMBOLS) do defaults[id] = false end
    return defaults
end

local function save_settings(s)
    CharSettings.symbolz = Json.encode(s)
end

local settings = load_settings()

--------------------------------------------------------------------------------
-- Casting logic
--------------------------------------------------------------------------------

local function in_forbidden_room()
    for _, room_name in ipairs(FORBIDDEN_ROOMS) do
        if checkroom(room_name) then return true end
    end
    return false
end

local function cast_if_needed(spell_id)
    if not settings[spell_id] then return end

    local spell = Spell[tonumber(spell_id)]
    if not spell or not spell.known or spell.active or not spell:affordable() then return end

    -- Special conditions for non-auto symbols
    if spell_id == "9813" then
        -- Mana: only when below threshold and effect not already active
        local effect = Spell[SPELL_EFFECTS["9813"]]
        if effect and effect.active then return end
        if Char.percent_mana > MANA_THRESHOLD then return end
    elseif spell_id == "9812" then
        -- Transcendence: only when stunned/webbed/bound and not in forbidden room
        local effect = Spell[SPELL_EFFECTS["9812"]]
        if effect and effect.active then return end
        if not (stunned() or webbed() or bound()) then return end
        if in_forbidden_room() then return end
    elseif spell_id == "9819" then
        -- Renewal: only when spirit below threshold and effect not already active
        local effect = Spell[SPELL_EFFECTS["9819"]]
        if effect and effect.active then return end
        if Char.percent_spirit >= SPIRIT_THRESHOLD then return end
    end

    spell:incant()

    -- Extra pause after conditional symbols (they have cooldown/timing requirements)
    if spell_id == "9813" or spell_id == "9812" or spell_id == "9819" then
        pause(5)
    end
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function run_setup()
    local win = Gui.window("Symbolz " .. VERSION .. " - Voln Symbol Upkeep",
        { width = 500, height = 400 })
    local root = Gui.vbox()

    local checkboxes = {}
    for _, id in ipairs(SYMBOL_ORDER) do
        local sym = SYMBOLS[id]
        local label = sym.desc
        if sym.tooltip then label = label .. " — " .. sym.tooltip end
        local cb = Gui.checkbox(label, { checked = settings[id] or false })
        checkboxes[id] = cb
        root:add(cb)
    end

    local save_btn = Gui.button("Save and Close")
    save_btn:on_click(function()
        for id, cb in pairs(checkboxes) do
            settings[id] = cb:is_checked()
        end
        save_settings(settings)
        echo("Symbolz settings saved!")
        win:close()
    end)
    root:add(save_btn)

    win:set_root(root)
    win:show()
    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- Help
--------------------------------------------------------------------------------

local function show_help()
    respond("")
    respond("Symbolz " .. VERSION .. " - Voln Symbol Upkeep")
    respond("  ;symbolz              - Run symbol maintenance loop")
    respond("  ;symbolz setup        - Open settings window")
    respond("  ;symbolz options      - Open settings window (alias)")
    respond("  ;symbolz help         - Show this message")
    respond("")
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]

if arg1 and arg1:lower() == "help" then
    show_help()
    return
elseif arg1 and (arg1:lower() == "setup" or arg1:lower() == "options") then
    run_setup()
    return
end

--------------------------------------------------------------------------------
-- Main maintenance loop
--------------------------------------------------------------------------------

if Spell[9012] and Spell[9012].active then
    echo("The Grand Poohbah is still mad at you.")
    return
end

echo("Symbolz active. Maintaining enabled symbols...")

while true do
    if dead() then return end

    if Spell[9012] and Spell[9012].active then
        echo("The Grand Poohbah is still mad at you.")
        return
    end

    for _, spell_id in ipairs(SYMBOL_ORDER) do
        cast_if_needed(spell_id)
    end

    pause(1)
end
