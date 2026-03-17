--- @revenant-script
--- name: sk_script
--- version: 1.2.3
--- author: elanthia-online
--- game: gs
--- description: Add/remove Self Knowledge spells to the known list
--- tags: sk,self knowledge,spells
---
--- Usage:
---   ;sk_script add <spell_number>    add spell number to saved list
---   ;sk_script rm <spell_number>     remove spell number from saved list
---   ;sk_script list                  show all currently saved SK spell numbers
---   ;sk_script help                  show this help
---
--- NOTE: This is the CLI script. The SK library is at lib/gs/sk.lua.

local SK = require("lib/gs/sk")

local function show_help()
    respond("  Script to add SK spells to be known and used with Spell API calls.")
    respond("")
    respond("  ;sk_script add <SPELL_NUMBER>  - Add spell number to saved list")
    respond("  ;sk_script rm <SPELL_NUMBER>   - Remove spell number from saved list")
    respond("  ;sk_script list                - Show all currently saved SK spell numbers")
    respond("  ;sk_script help                - Show this menu")
    respond("")
end

local function show_list()
    local spells = SK.known()
    if #spells == 0 then
        respond("Current SK Spells: (none)")
    else
        local parts = {}
        for _, n in ipairs(spells) do parts[#parts + 1] = tostring(n) end
        respond("Current SK Spells: " .. table.concat(parts, ", "))
    end
end

local action = Script.vars[1]

if not action or action == "" or action == "help" then
    show_help()
    return
end

action = action:lower()

if action == "list" then
    show_list()
elseif action == "add" then
    local nums = {}
    for i = 2, 20 do
        local v = Script.vars[i]
        if v and v:match("^%d+$") then
            nums[#nums + 1] = tonumber(v)
        end
    end
    if #nums == 0 then
        echo("Please provide spell numbers to add.")
        return
    end
    SK.add(table.unpack(nums))
    echo("Added " .. #nums .. " spell(s) to SK list.")
    show_list()
elseif action == "rm" or action == "remove" then
    local nums = {}
    for i = 2, 20 do
        local v = Script.vars[i]
        if v and v:match("^%d+$") then
            nums[#nums + 1] = tonumber(v)
        end
    end
    if #nums == 0 then
        echo("Please provide spell numbers to remove.")
        return
    end
    SK.remove(table.unpack(nums))
    echo("Removed " .. #nums .. " spell(s) from SK list.")
    show_list()
else
    echo("Unknown action: " .. action)
    show_help()
end
