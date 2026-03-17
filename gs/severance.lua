--- @revenant-script
--- name: severance
--- version: 1.0.11
--- author: Kaetel
--- game: gs
--- description: Remove spells at risk for Spell Sever zones, preserve configured priority list
--- tags: spellsever, spells, utility
---
--- Usage:
---   ;severance           - Remove at-risk spells
---   ;severance check     - Check which spells are at risk
---   ;severance list      - List preserved spells
---   ;severance add <num> - Add spell to preserve list
---   ;severance rem <num> - Remove spell from preserve list
---   ;severance set <nums> - Replace entire list
---   ;severance setlimit <n> - Set sever limit (default 2)
---   ;severance --daemon  - Run continuously

UserVars.severspells = UserVars.severspells or {}
UserVars.severlimit = UserVars.severlimit or 2

local GROUP_SPELLS = {307,310,605,620,1006,1007,1018,1035,1213,1216,1125,1605,1609,1617,1618,1699}
local limit = UserVars.severlimit

local function is_group_spell(num)
    for _, g in ipairs(GROUP_SPELLS) do if g == num then return true end end
    return false
end

local function get_severable()
    local result = {}
    for _, s in ipairs(Spell.active or {}) do
        if not s.known and not is_group_spell(s.num) and s.circle <= 16 and (s.num - s.circle * 100) <= 50 then
            table.insert(result, s)
        end
    end
    table.sort(result, function(a, b)
        local ai, bi = 1000 + a.num, 1000 + b.num
        for i, sn in ipairs(UserVars.severspells) do
            if sn == a.num then ai = i end
            if sn == b.num then bi = i end
        end
        return ai < bi
    end)
    return result
end

local args = script.vars
if not args[1] then
    -- Sever mode
    local severable = get_severable()
    if #severable <= limit then
        respond("You're safely under the Spell Sever limit.")
    else
        respond("Over limit by " .. (#severable - limit) .. " spells...")
        for i = limit + 1, #severable do
            fput("stop " .. severable[i].num)
        end
    end
elseif args[1] == "check" then
    local severable = get_severable()
    if #severable <= limit then
        respond("You're safely under the limit.")
    else
        respond("Over limit by " .. (#severable - limit) .. " spells")
        for i = 1, math.min(limit, #severable) do
            respond("  Keep: " .. severable[i].name .. " (" .. severable[i].num .. ")")
        end
        for i = limit + 1, #severable do
            respond("  AT RISK: " .. severable[i].name .. " (" .. severable[i].num .. ")")
        end
    end
elseif args[1] == "list" then
    if #UserVars.severspells == 0 then
        respond("No spells configured. Use ;severance add <spellnum>")
    else
        for i, num in ipairs(UserVars.severspells) do
            respond(i .. " | " .. (Spell[num] and Spell[num].name or "?") .. " (" .. num .. ")")
        end
    end
elseif args[1] == "add" or args[1] == "+" then
    local n = tonumber(args[2])
    if n then
        table.insert(UserVars.severspells, n)
        respond("Added " .. n .. " to protected spells")
    end
elseif args[1] == "rem" or args[1] == "-" then
    local n = tonumber(args[2])
    for i, v in ipairs(UserVars.severspells) do
        if v == n then table.remove(UserVars.severspells, i); break end
    end
    respond("Removed " .. (n or "?") .. " from protected spells")
elseif args[1] == "setlimit" and args[2] then
    UserVars.severlimit = tonumber(args[2]) or 2
    respond("Sever limit set to " .. UserVars.severlimit)
elseif args[1] == "help" then
    respond(";severance [check|list|add|rem|set|setlimit|--daemon|help]")
end
