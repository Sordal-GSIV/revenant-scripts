--- @revenant-script
--- name: tcalt
--- version: 1.0.0
--- author: unknown
--- game: gs
--- description: Manage a list of main characters and their alts with notes
--- tags: utility, alts, characters
---
--- Usage:
---   ;tcalt list                      - Lists all main characters and their alts
---   ;tcalt add <main> <alt> [<alt>]  - Adds alt(s) to the specified main
---   ;tcalt remove <main> <alt>       - Removes the specified alt
---   ;tcalt removemain <main>         - Removes main and all alts
---   ;tcalt note <name> <note>        - Adds notes to the specified name
---   ;tcalt find <name>               - Find command for main and all alts
---   ;tcalt <name>                    - Display entry for the name
---   ;tcalt reset                     - Reset all data

CharSettings["main_alts"] = CharSettings["main_alts"] or {}
CharSettings["notes"] = CharSettings["notes"] or {}

local function format_name(name)
    return name:sub(1,1):upper() .. name:sub(2):lower()
end

local function list_alts()
    local data = CharSettings["main_alts"]
    if not next(data) then
        echo("No alts have been added yet.")
        return
    end
    for main, alts in pairs(data) do
        echo("Main: " .. main .. " - Alts: " .. table.concat(alts, ", "))
        if CharSettings["notes"][main] then
            echo("Notes: " .. CharSettings["notes"][main])
        end
    end
end

local function add_alt(main_name, alt_name)
    main_name = format_name(main_name)
    CharSettings["main_alts"][main_name] = CharSettings["main_alts"][main_name] or {}
    if alt_name then
        alt_name = format_name(alt_name)
        for _, v in ipairs(CharSettings["main_alts"][main_name]) do
            if v == alt_name then
                echo(alt_name .. " is already an alt of " .. main_name .. ".")
                return
            end
        end
        table.insert(CharSettings["main_alts"][main_name], alt_name)
        echo("Added " .. alt_name .. " as an alt of " .. main_name .. ".")
    else
        echo("Added " .. main_name .. " as a main character.")
    end
end

local function remove_alt(main_name, alt_name)
    main_name = format_name(main_name)
    alt_name = format_name(alt_name)
    local alts = CharSettings["main_alts"][main_name]
    if alts then
        for i, v in ipairs(alts) do
            if v == alt_name then
                table.remove(alts, i)
                echo("Removed " .. alt_name .. " from the alts of " .. main_name .. ".")
                return
            end
        end
    end
    echo(alt_name .. " is not an alt of " .. main_name .. ".")
end

local function remove_main(main_name)
    main_name = format_name(main_name)
    if CharSettings["main_alts"][main_name] then
        CharSettings["main_alts"][main_name] = nil
        CharSettings["notes"][main_name] = nil
        echo("Removed " .. main_name .. " and all their alts.")
    else
        echo(main_name .. " does not exist.")
    end
end

local function display_entry(name)
    name = format_name(name)
    if CharSettings["main_alts"][name] then
        echo("Main: " .. name .. " - Alts: " .. table.concat(CharSettings["main_alts"][name], ", "))
        if CharSettings["notes"][name] then echo("Notes: " .. CharSettings["notes"][name]) end
        return
    end
    for main, alts in pairs(CharSettings["main_alts"]) do
        for _, alt in ipairs(alts) do
            if alt == name then
                echo("Main: " .. main .. " - Alts: " .. table.concat(alts, ", "))
                return
            end
        end
    end
    echo(name .. " does not exist.")
end

local args = script.vars
if args[1] == "list" then list_alts()
elseif args[1] == "add" and args[2] then
    if #args > 3 then for i = 3, #args do add_alt(args[2], args[i]) end
    else add_alt(args[2]) end
elseif args[1] == "remove" and args[2] and args[3] then remove_alt(args[2], args[3])
elseif args[1] == "removemain" and args[2] then remove_main(args[2])
elseif (args[1] == "note" or args[1] == "notes") and args[2] and args[3] then
    local note = table.concat(args, " ", 3)
    CharSettings["notes"][format_name(args[2])] = note
    echo("Added note to " .. format_name(args[2]) .. ": " .. note)
elseif args[1] == "reset" then
    CharSettings["main_alts"] = {}
    CharSettings["notes"] = {}
    echo("Reset all main and alt information.")
elseif args[1] == "find" and args[2] then
    if args[2] == "all" then
        for main, alts in pairs(CharSettings["main_alts"]) do
            local names = {main}
            for _, v in ipairs(alts) do table.insert(names, v) end
            fput("find " .. table.concat(names, " "))
            pause(0.5)
        end
    else display_entry(args[2]) end
elseif args[1] then display_entry(args[1])
else echo("Usage: ;tcalt list | add | remove | removemain | note | find | reset | <name>") end
