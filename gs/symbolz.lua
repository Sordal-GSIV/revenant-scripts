--- @revenant-script
--- name: symbolz
--- version: 2.0.0
--- author: elanthia-online
--- contributors: SpiffyJr, Tillmen
--- game: gs
--- description: Voln symbol management -- keeps symbols active with auto-cast
--- tags: voln,symbols,society
---
--- Changelog (from Lich5):
---   v2.0.0 (2025-10-13) - Refactored OOP architecture, YAML->JSON settings
---   v1.1.3 (2025-03-19) - Remove deprecated calls
---   v1.1.0 (2021-03-01) - GTK3 support in Lich5
---   v1.0.0 (2020-03-20) - Original release

--------------------------------------------------------------------------------
-- Symbol definitions
--------------------------------------------------------------------------------

local SYMBOLS = {
    ["9806"] = { name = "Protection",    desc = "Symbol of Protection: +26 DS, +13 TD",   auto = true },
    ["9805"] = { name = "Courage",       desc = "Symbol of Courage: +26 AS",              auto = true },
    ["9816"] = { name = "Supremacy",     desc = "Symbol of Supremacy: +13 AS",            auto = true },
    ["9815"] = { name = "Retribution",   desc = "Symbol of Retribution: reactive flares", auto = true },
    ["9813"] = { name = "Mana",          desc = "Symbol of Mana: gives 50 mana",          auto = false },
    ["9812"] = { name = "Transcendence", desc = "Symbol of Transcendence: non-corporeal", auto = false },
    ["9819"] = { name = "Renewal",       desc = "Symbol of Renewal: gives 1 spirit",      auto = false },
}

local SPELL_EFFECTS = {
    ["9813"] = "9048",
    ["9812"] = "9049",
    ["9819"] = "9050",
}

local FORBIDDEN_ROOMS = {
    "The Belly of the Beast",
    "Ooze, Innards",
    "Temporal Rift",
}

local MANA_THRESHOLD = 40
local SPIRIT_THRESHOLD = 80

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local SETTINGS_FILE = "data/symbolz.json"

local function load_settings()
    if not File.exists(SETTINGS_FILE) then
        local defaults = {}
        for id, _ in pairs(SYMBOLS) do defaults[id] = false end
        return defaults
    end
    local ok, data = pcall(function() return Json.decode(File.read(SETTINGS_FILE)) end)
    return (ok and type(data) == "table") and data or {}
end

local function save_settings(s)
    File.write(SETTINGS_FILE, Json.encode(s))
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
    if not spell or not spell.known or not spell.affordable or spell.active then return end

    -- Special handling for conditional symbols
    if spell_id == "9813" then
        -- Mana: only if below threshold and effect not active
        local effect = Spell[tonumber(SPELL_EFFECTS["9813"])]
        if effect and effect.active then return end
        if Char.percent_mana > MANA_THRESHOLD then return end
    elseif spell_id == "9812" then
        -- Transcendence: only if stunned/webbed/bound
        local effect = Spell[tonumber(SPELL_EFFECTS["9812"])]
        if effect and effect.active then return end
        if not (stunned() or webbed() or bound()) then return end
        if in_forbidden_room() then return end
    elseif spell_id == "9819" then
        -- Renewal: only if spirit below threshold
        local effect = Spell[tonumber(SPELL_EFFECTS["9819"])]
        if effect and effect.active then return end
        if Char.percent_spirit >= SPIRIT_THRESHOLD then return end
    end

    waitrt()
    waitcastrt()
    fput("incant " .. spell_id)

    -- Extra sleep for conditional symbols
    if spell_id == "9813" or spell_id == "9812" or spell_id == "9819" then
        pause(5)
    end
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function run_setup()
    local win = Gui.window("Symbolz - Voln Symbol Upkeep", { width = 450, height = 350 })
    local root = Gui.vbox()

    local checkboxes = {}
    for id, sym in pairs(SYMBOLS) do
        local cb = Gui.checkbox(sym.desc, { checked = settings[id] or false })
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
    respond("Symbolz - Voln Symbol Upkeep")
    respond("  ;symbolz        - Run symbol maintenance loop")
    respond("  ;symbolz setup  - Show setup window")
    respond("  ;symbolz help   - Show this message")
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

-- Check for punishment
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

    for spell_id, _ in pairs(SYMBOLS) do
        cast_if_needed(spell_id)
    end

    pause(1)
end
