--- @revenant-script
--- name: signore
--- version: 0.8.2
--- author: elanthia-online
--- contributors: Ondreian, Dissonance, EO
--- game: gs
--- description: Society power manager with anti-magic room tracking
--- tags: col,sunfist,voln,society,society-powers
--- @lic-audit: validated 2026-03-17
---
--- Changelog (from Lich5):
---   v0.8.2 (2026-01-13) - Disable deprecated Settings.save
---   v0.8.1 (2025-07-16) - Setup window opens on top, fix sigil of mending
---   v0.8   (2025-05-07) - Change CharSettings.save to Settings.save
---   v0.7   (2023-06-05) - Fix for new Infomon library
---   v0.6   (2021-08-21) - Updated to support GTK3
---   v0.5   (2019-02-24) - Add Sigil of Concentration
---   v0.4   (2019-02-23) - Fix using Gtk.queue for Windows

local HELP_TEXT = [[
;signore setup            launches the setup GUI
;signore room:list        lists all rooms currently tagged as anti-magic
;signore room:rm  <num>   remove the anti-magic tag from room <num>
]]

--------------------------------------------------------------------------------
-- Available society powers
--------------------------------------------------------------------------------

local AVAIL_SPELLS = {
    -- CoL
    9903, 9904, 9905, 9906, 9907, 9908, 9909, 9910, 9912, 9913, 9914,
    -- Voln
    9805, 9806, 9816,
    -- GoS
    9704, 9705, 9707, 9708, 9710, 9711, 9713, 9714, 9715, 9716, 9719,
}

local PUNISHMENT_SPELL = 9012

local ANTIMAGIC_PATTERN = "^The power from your sign dissipates into the air%.$"

local SUCCESS_PATTERNS = {
    "^You flex your muscles with renewed vigor!$",
    "^You grip your .* with renewed vigor!$",
    "^Your veins throb and your blood sings%.$",
    "^Magic flows towards you, but does not reach you%.$",
    "^You feel magical energies distort and flow around you%.$",
    "^Your dancing fingers weave a web of protection around you!$",
    "^Repeating the sign has no effect!$",
    "^Your hypnotic gesture makes your mind receptive to the thoughts",
    "^You feel more courageous%.$",
    "^You feel a layer of protection surround you%.$",
    "surrounds you%.$",
    "^You begin to focus sharply upon the task at hand",
    "^A faint blue glow surrounds your hands, subtly guiding your movements%.",
    "You feel your mind and body gird themselves against magical interference",
    "^As you concentrate on your sigil",
    "^You feel infused with a collective knowledge on the undead and their weaknesses%.$",
}

local SUCCESS_RE = Regex.new(table.concat(SUCCESS_PATTERNS, "|"))

local BERSERK_PATTERN = "^You cannot do that while berserking%.$"

--------------------------------------------------------------------------------
-- Anti-magic room tracking
--------------------------------------------------------------------------------

local function load_antimagic_rooms()
    local raw = Settings.antimagic_rooms
    if not raw or raw == "" then return {} end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or {}
end

local function save_antimagic_rooms(rooms)
    Settings.antimagic_rooms = Json.encode(rooms)
end

local function add_antimagic_room(room_id)
    local rooms = load_antimagic_rooms()
    for _, id in ipairs(rooms) do
        if id == room_id then return end
    end
    respond("<pushBold/>adding " .. tostring(room_id) .. " as antimagic<popBold/>")
    rooms[#rooms + 1] = room_id
    save_antimagic_rooms(rooms)
end

local function is_antimagic_room()
    local rooms = load_antimagic_rooms()
    local current = Room.id
    if not current then return false end
    for _, id in ipairs(rooms) do
        if id == current then return true end
    end
    return false
end

--------------------------------------------------------------------------------
-- Settings: which powers are enabled
--------------------------------------------------------------------------------

local function power_active(spell_num)
    local v = CharSettings[tostring(spell_num)]
    return v == "true"
end

local function toggle_power(spell_num)
    local key = tostring(spell_num)
    local current = CharSettings[key] == "true"
    CharSettings[key] = tostring(not current)
end

--------------------------------------------------------------------------------
-- Available known powers
--------------------------------------------------------------------------------

local function get_available_powers()
    local result = {}
    for _, num in ipairs(AVAIL_SPELLS) do
        local spell = Spell[num]
        if spell and spell.known then
            result[#result + 1] = num
        end
    end
    return result
end

--------------------------------------------------------------------------------
-- Soulless check (Signs of Swords/Dissipation require 80%+ spirit)
--------------------------------------------------------------------------------

local function is_soulless(spell_num)
    return (spell_num == 9913 or spell_num == 9914) and GameState.spirit < (GameState.max_spirit * 0.8)
end

--------------------------------------------------------------------------------
-- Cast a single power
--------------------------------------------------------------------------------

local function cast_power(spell_num)
    if is_soulless(spell_num) then return end

    -- Wait for go2 to finish
    wait_while(function() return running("go2") end)

    local spell = Spell[spell_num]
    if not spell then return end
    if not spell:affordable() then return end
    if not power_active(spell_num) then return end
    if spell.active then return end
    if is_antimagic_room() then return end

    local result = dothistimeout(spell.name, 5, {
        ANTIMAGIC_PATTERN,
        "^You flex your muscles",
        "^You grip your",
        "^Your veins throb",
        "^Magic flows towards you",
        "^You feel magical energies",
        "^Your dancing fingers",
        "^Repeating the sign",
        "^Your hypnotic gesture",
        "^You feel more courageous",
        "^You feel a layer of protection",
        "surrounds you%.$",
        "^You begin to focus sharply",
        "^A faint blue glow",
        "You feel your mind and body gird",
        "^As you concentrate on your sigil",
        "^You feel infused with a collective",
        "^You cannot do that while berserking",
    })

    if result then
        if string.find(result, "dissipates into the air") then
            add_antimagic_room(Room.id)
        elseif string.find(result, "berserking") then
            -- Wait for berserking to end
            waitfor("The redness fades from the world")
        end
    end
end

local function cast_all_powers()
    local powers = get_available_powers()
    for _, num in ipairs(powers) do
        local spell = Spell[num]
        if spell and not spell.active then
            cast_power(num)
        end
    end
end

--------------------------------------------------------------------------------
-- Setup GUI
--------------------------------------------------------------------------------

local function run_setup()
    local powers = get_available_powers()
    if #powers == 0 then
        respond("[signore] No known society powers found.")
        return
    end

    local win = Gui.window("Signore Setup", { width = 300, height = 400 })
    local root = Gui.vbox()
    local scroll = Gui.scroll(root)

    local header = Gui.label("Toggle society powers on/off:")
    root:add(header)
    root:add(Gui.separator())

    for _, num in ipairs(powers) do
        local spell = Spell[num]
        local name = spell and spell.name or tostring(num)
        local cb = Gui.checkbox(name, power_active(num))
        cb:on_change(function()
            toggle_power(num)
        end)
        root:add(cb)
    end

    win:set_root(scroll)
    win:show()

    before_dying(function()
        if win then win:close() end
    end)

    Gui.wait(win, "close")
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

-- Wait for repository to finish before proceeding
wait_while(function() return running("repository") end)

-- Warn if infomon is not running
if not running("infomon") then
    echo("Warning: infomon not running")
end

local args0 = Script.vars[0] or ""

-- Add known antimagic room
add_antimagic_room(2642)

if string.find(args0, "room:list") then
    local rooms = load_antimagic_rooms()
    respond("antimagic rooms: " .. table.concat(rooms, ", "))
    return
end

if string.find(args0, "room:reset") then
    save_antimagic_rooms({})
    respond("reset all antimagic rooms")
    return
end

if string.find(args0, "room:rm") then
    local to_delete = tonumber(Script.vars[2])
    if not to_delete then
        respond("you must pass a room number to delete")
        return
    end
    local rooms = load_antimagic_rooms()
    local new_rooms = {}
    for _, id in ipairs(rooms) do
        if id ~= to_delete then
            new_rooms[#new_rooms + 1] = id
        end
    end
    save_antimagic_rooms(new_rooms)
    respond("antimagic rooms: " .. table.concat(new_rooms, ", "))
    return
end

if string.find(args0, "setup") or string.find(args0, "options") then
    run_setup()
    return
end

if string.find(args0, "help") then
    respond(HELP_TEXT)
    return
end

-- Check for available powers
local available = get_available_powers()
if #available == 0 then
    respond("[signore.error] you do not know any societal powers...")
    return
end

-- Check for punishment
if Spell[PUNISHMENT_SPELL] and Spell[PUNISHMENT_SPELL].active then
    respond("--- you are currently under PUNISHMENT ---")
    return
end

-- Main loop
while true do
    if dead() then return end
    cast_all_powers()
    pause(0.1)
end
