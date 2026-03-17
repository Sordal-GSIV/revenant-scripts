--- @revenant-script
--- name: spellactive
--- version: 1.3.3
--- author: elanthia-online
--- contributors: spiffyjr, Tysong
--- game: gs
--- description: Keeps spells active -- recast when they drop
--- tags: spells,magic,active
---
--- Changelog (from Lich5):
---   v1.3.3 (2025-03-19) - Remove deprecated calls
---   v1.3.2 (2024-06-10) - Fixed string compare for .cast result
---   v1.3.1 (2023-01-25) - Add cooldown check for short duration buffs
---   v1.3.0 (2022-07-18) - Added nocast rooms
---   v1.2.1 (2022-05-07) - Fixed barkskin cooldown
---   v1.0.0 - Initial release

--------------------------------------------------------------------------------
-- Settings
--------------------------------------------------------------------------------

local function load_json(key, default)
    local raw = CharSettings[key]
    if not raw or raw == "" then return default end
    local ok, t = pcall(Json.decode, raw)
    return (ok and type(t) == "table") and t or default
end

local function save_json(key, val)
    CharSettings[key] = Json.encode(val)
end

local settings = {
    spells = load_json("spells", {}),
    nocast = load_json("nocast", {}),
    power  = (CharSettings["power"] ~= "false"),
}

local function save_settings()
    save_json("spells", settings.spells)
    save_json("nocast", settings.nocast)
    CharSettings["power"] = tostring(settings.power)
end

local function table_contains(t, val)
    for _, v in ipairs(t) do
        if tostring(v) == tostring(val) then return true end
    end
    return false
end

local function table_remove_value(t, val)
    for i = #t, 1, -1 do
        if tostring(t[i]) == tostring(val) then table.remove(t, i) end
    end
end

--------------------------------------------------------------------------------
-- Resolve a spell by number or name
--------------------------------------------------------------------------------

local function resolve_spell(input)
    if not input or input == "" then return nil end
    local num = tonumber(input)
    if num and Spell[num] then return Spell[num] end
    if Spell[input] then return Spell[input] end
    return nil
end

--------------------------------------------------------------------------------
-- CLI dispatch
--------------------------------------------------------------------------------

local arg1 = Script.vars[1]
local arg2 = Script.vars[2]
local arg3 = Script.vars[3]

if arg1 and arg1:lower() == "add" then
    if not arg2 then echo("You're doing it wrong"); return end
    local spell = resolve_spell(arg2)
    if not spell then echo("Could not find spell: " .. tostring(arg2)); return end
    if table_contains(settings.spells, spell.num) then
        echo("You are already keeping " .. spell.name .. " active"); return
    end
    if not spell.known then echo("You do not know " .. spell.name); return end
    settings.spells[#settings.spells + 1] = spell.num
    save_settings()
    echo("Added " .. spell.name)
    return
elseif arg1 and arg1:lower():match("^del") or (arg1 and arg1:lower():match("^rem")) then
    if not arg2 then echo("You're doing it wrong"); return end
    local spell = resolve_spell(arg2)
    if not spell then echo("Could not find spell: " .. tostring(arg2)); return end
    if not table_contains(settings.spells, spell.num) then
        echo("You are not keeping " .. spell.name .. " active"); return
    end
    table_remove_value(settings.spells, spell.num)
    save_settings()
    echo("Removed " .. spell.name)
    return
elseif arg1 and arg1:lower() == "nocast" then
    if arg2 and arg2:lower() == "add" then
        if not arg3 then echo("You're doing it wrong"); return end
        if table_contains(settings.nocast, arg3) then
            echo("Already not casting in room " .. arg3); return
        end
        settings.nocast[#settings.nocast + 1] = arg3
        save_settings()
        echo("Added " .. arg3 .. " to nocast list")
    elseif arg2 and arg2:lower():match("^del") or (arg2 and arg2:lower():match("^rem")) then
        if not arg3 then echo("You're doing it wrong"); return end
        table_remove_value(settings.nocast, arg3)
        save_settings()
        echo("Removed " .. arg3 .. " from nocast list")
    elseif arg2 and arg2:lower() == "clear" then
        settings.nocast = {}
        save_settings()
        echo("Cleared nocast rooms")
    end
    return
elseif arg1 and arg1:lower() == "list" then
    echo("Spell list:")
    local sorted = {}
    for _, s in ipairs(settings.spells) do sorted[#sorted + 1] = s end
    table.sort(sorted)
    for _, num in ipairs(sorted) do
        local sp = Spell[num]
        echo(string.format("  %4d: %s", num, sp and sp.name or "unknown"))
    end
    echo("Nocast rooms:")
    for _, r in ipairs(settings.nocast) do
        echo(string.format("  %s", tostring(r)))
    end
    return
elseif arg1 and arg1:lower() == "power" then
    settings.power = not settings.power
    save_settings()
    if settings.power then
        echo("Use Sigil of Power when mana is 25 below max")
    else
        echo("Don't use Sigil of Power when mana is 25 below max")
    end
    return
elseif arg1 and (arg1:lower() == "help" or arg1 == "?") then
    echo("SpellActive Help")
    echo("  add [num|name]     add a spell to the list")
    echo("  del [num|name]     delete a spell from the list")
    echo("  nocast add [num]   add a room to the nocast list")
    echo("  nocast del [num]   delete a room from the nocast list")
    echo("  nocast clear       delete all rooms from the nocast list")
    echo("  power              toggle usage of sigil of power")
    echo("  list               list spells you are keeping active")
    return
elseif arg1 then
    return
end

--------------------------------------------------------------------------------
-- Main loop
--------------------------------------------------------------------------------

while true do
    wait_while(function() return dead() end)

    for _, check_spell in ipairs(settings.spells) do
        -- Skip nocast rooms
        local room = Room.current()
        if room then
            local room_id = tostring(room.id)
            if table_contains(settings.nocast, room_id) then
                goto continue_spell
            end
        end

        local spell = Spell[check_spell]
        if spell and not spell.active then
            -- Wait for clear state
            if checkcastrt() > 0 then waitcastrt() end
            if checkrt() > 0 then waitrt() end

            if spell.known and spell.affordable then
                -- Beacon of Courage special: cast Defense of the Faithful
                local cast_spell = spell
                if spell.num == 1699 and Spell[1608] then
                    cast_spell = Spell[1608]
                end

                -- Spirit stagger check
                local was_hidden = hidden()

                fput("incant " .. cast_spell.num)

                if was_hidden and not hidden() then
                    put("hide")
                end
            end
        end

        ::continue_spell::
    end

    -- Sigil of Power
    if settings.power then
        local sop = Spell["Sigil of Power"]
        if sop and sop.known and sop.affordable and (Char.max_mana - Char.mana) > 25 then
            if checkcastrt() > 0 then waitcastrt() end
            if checkrt() > 0 then waitrt() end
            fput("sigil of power")
            pause(1)
        end
    end

    pause(1)
end
