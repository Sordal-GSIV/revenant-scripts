--- @revenant-script
--- name: burst
--- version: 1.0.0
--- author: Alastir
--- contributors: Maodan
--- game: dr
--- description: Remove spells at risk for Spell Burst zones, with configurable preserve list
--- tags: spellburst, spells, utility
---
--- Ported from burst.lic (Lich5) to Revenant Lua
---
--- Usage:
---   ;burst              - Remove at-risk spells (one-shot)
---   ;burst --daemon     - Keep running, recheck periodically
---   ;burst --quiet      - Suppress output
---   ;burst add <num>    - Add spell to preserve list
---   ;burst rem <num>    - Remove spell from preserve list
---   ;burst list         - Show preserved spells
---   ;burst check        - Check current spell risk
---   ;burst set 215 211  - Replace entire preserve list
---   ;burst help         - Show help

local group_spells = {307,310,605,620,1006,1007,1018,1035,1213,1216,1605,1609,1617,1618,1699}
local settings = CharSettings.get("burst_spells") or {}
local quiet = false
local daemon = false
local delay = 5

local function msg(text)
    if not quiet then echo(text) end
end

local function spell_name(num)
    -- Use Spell API if available, otherwise just show number
    if Spell and Spell[num] then
        return Spell[num].name
    end
    return "Spell #" .. tostring(num)
end

local function has_spell(num)
    for _, s in ipairs(settings) do
        if s == num then return true end
    end
    return false
end

local function save_settings()
    CharSettings.set("burst_spells", settings)
end

local function add_spell(num)
    if has_spell(num) then
        msg(spell_name(num) .. " (" .. num .. ") is already in your preserve list")
        return
    end
    table.insert(settings, num)
    save_settings()
    msg("Added " .. spell_name(num) .. " (" .. num .. ") to preserve list")
end

local function rem_spell(num)
    for i, s in ipairs(settings) do
        if s == num then
            table.remove(settings, i)
            save_settings()
            msg("Removed " .. spell_name(num) .. " (" .. num .. ") from preserve list")
            return
        end
    end
    msg(spell_name(num) .. " (" .. num .. ") is not in your preserve list")
end

local function list_spells()
    if #settings == 0 then
        msg("No spells registered to preserve. Use ;burst add <number>")
        return
    end
    msg("Preserved spells (in priority order):")
    for i, num in ipairs(settings) do
        msg("  " .. i .. " | " .. spell_name(num) .. " (" .. num .. ")")
    end
    msg("Only the first 2 preserved spells will be kept if more than 2 are active.")
end

local function is_group_spell(num)
    for _, g in ipairs(group_spells) do
        if g == num then return true end
    end
    return false
end

local function do_burst()
    if #settings == 0 then
        msg("No spells registered to preserve. Use ;burst add <number>")
        return
    end

    local active = Spell.active or {}
    for _, s in ipairs(active) do
        local num = s.num or 0
        if not s:known() and not is_group_spell(num) and (s.circle or 0) <= 16 then
            if not has_spell(num) then
                msg("Removing " .. spell_name(num))
                fput("stop " .. num)
            end
        end
    end
end

local function show_help()
    echo("=== Burst (Spell Burst Protection) ===")
    echo("Author: Alastir / Maodan")
    echo("")
    echo("Usage:")
    echo("  ;burst              - Remove at-risk spells")
    echo("  ;burst --daemon     - Run in background, recheck periodically")
    echo("  ;burst --quiet      - Suppress output")
    echo("  ;burst --delay=N    - Set daemon delay (default 5s)")
    echo("  ;burst add <num>    - Add spell to preserve list")
    echo("  ;burst rem <num>    - Remove spell from preserve list")
    echo("  ;burst list         - List preserved spells")
    echo("  ;burst check        - Check active spells for risk")
    echo("  ;burst set N1 N2    - Replace preserve list")
    echo("  ;burst help         - Show this help")
end

-- Parse arguments
local args = Script.vars or {}
local cmd = args[1] and args[1]:lower() or nil

-- Check for flags
for i, arg in ipairs(args) do
    if arg == "--quiet" then quiet = true end
    if arg == "--daemon" then daemon = true end
    local d = arg:match("%-%-delay=(%d+)")
    if d then delay = tonumber(d) end
end

if cmd == "help" then
    show_help()
elseif cmd == "list" then
    list_spells()
elseif cmd == "check" then
    msg("Checking active spells for Spell Burst risk...")
    list_spells()
elseif cmd == "add" or cmd == "+" then
    local num = tonumber(args[2])
    if num then add_spell(num) else msg("Usage: ;burst add <spell_number>") end
elseif cmd == "rem" or cmd == "-" then
    local num = tonumber(args[2])
    if num then rem_spell(num) else msg("Usage: ;burst rem <spell_number>") end
elseif cmd == "set" then
    settings = {}
    for i = 2, #args do
        local nums = args[i]:gsub(",", " ")
        for n in nums:gmatch("%d+") do
            add_spell(tonumber(n))
        end
    end
    save_settings()
    list_spells()
else
    if daemon then
        msg("Running in daemon mode, rechecking every " .. delay .. " seconds")
        while true do
            do_burst()
            pause(delay)
        end
    else
        do_burst()
    end
end
