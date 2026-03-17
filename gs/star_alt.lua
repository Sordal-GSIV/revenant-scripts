--- @revenant-script
--- name: star_alt
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Track character alts with formatted table display and find integration
--- tags: utility, alts, tracking
---
--- Usage:
---   ;star_alt list [name]   - List all or specific character
---   ;star_alt add <main> [alts...] - Add main/alts
---   ;star_alt remove <main> <alt>  - Remove an alt
---   ;star_alt find <name|all>      - Find online characters
---   ;star_alt <name>        - Look up a character

CharSettings["main_alts"] = CharSettings["main_alts"] or {}
CharSettings["notes"] = CharSettings["notes"] or {}

local function fmt(name) return name:sub(1,1):upper() .. name:sub(2):lower() end

local function resolve_main(name)
    name = fmt(name)
    if CharSettings["main_alts"][name] then return name end
    for main, alts in pairs(CharSettings["main_alts"]) do
        for _, alt in ipairs(alts) do
            if alt:lower() == name:lower() then return main end
        end
    end
    return nil
end

local args = script.vars
if args[1] == "list" then
    if args[2] then
        local main = resolve_main(args[2])
        if main then
            echo("Main: " .. main .. " | Alts: " .. table.concat(CharSettings["main_alts"][main] or {}, ", "))
        else echo(fmt(args[2]) .. " not found.") end
    else
        for main, alts in pairs(CharSettings["main_alts"]) do
            echo("Main: " .. main .. " | Alts: " .. table.concat(alts, ", "))
            if CharSettings["notes"][main] then echo("  Note: " .. CharSettings["notes"][main]) end
        end
    end
elseif args[1] == "add" and args[2] then
    local main = fmt(args[2])
    CharSettings["main_alts"][main] = CharSettings["main_alts"][main] or {}
    for i = 3, #args do
        table.insert(CharSettings["main_alts"][main], fmt(args[i]))
        echo("Added " .. fmt(args[i]) .. " as alt of " .. main)
    end
    if #args < 3 then echo("Added " .. main .. " as main.") end
elseif args[1] == "remove" and args[2] and args[3] then
    local main = fmt(args[2])
    local alts = CharSettings["main_alts"][main] or {}
    for i, v in ipairs(alts) do
        if v == fmt(args[3]) then table.remove(alts, i); echo("Removed."); break end
    end
elseif args[1] == "removemain" and args[2] then
    CharSettings["main_alts"][fmt(args[2])] = nil
    CharSettings["notes"][fmt(args[2])] = nil
    echo("Removed " .. fmt(args[2]))
elseif args[1] == "note" and args[2] and args[3] then
    CharSettings["notes"][fmt(args[2])] = table.concat(args, " ", 3)
    echo("Note added.")
elseif args[1] == "find" and args[2] then
    if args[2] == "all" then
        for main, alts in pairs(CharSettings["main_alts"]) do
            local names = {main}; for _, a in ipairs(alts) do table.insert(names, a) end
            fput("find " .. table.concat(names, " ")); pause(0.5)
        end
    else
        local main = resolve_main(args[2])
        if main then
            local names = {main}; for _, a in ipairs(CharSettings["main_alts"][main] or {}) do table.insert(names, a) end
            fput("find " .. table.concat(names, " "))
        else echo("Not found.") end
    end
elseif args[1] == "reset" then
    CharSettings["main_alts"] = {}; CharSettings["notes"] = {}; echo("Reset.")
elseif args[1] and args[1] ~= "help" then
    local main = resolve_main(args[1])
    if main then echo("Main: " .. main .. " | Alts: " .. table.concat(CharSettings["main_alts"][main] or {}, ", "))
    else echo(fmt(args[1]) .. " not found.") end
else
    echo("Usage: ;star_alt list|add|remove|removemain|note|find|reset|<name>")
end
