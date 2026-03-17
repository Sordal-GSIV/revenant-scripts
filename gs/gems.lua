--- @revenant-script
--- name: gems
--- version: 1.2.0
--- author: Brute
--- game: gs
--- description: Set active (equipped) gemstones by number
--- tags: gems, equip, gemstone, loadout
---
--- Usage:
---   ;gems 1 4 6 15 20    - equip specific gems
---   ;gems none            - unequip all gems
---   ;gems clear           - unequip all gems
---   ;gems help            - show help

local input = (Script.vars[0] or ""):match("^%s*(.-)%s*$"):lower()

if input == "help" then
    echo("Sets your active (equipped) gems. Only the gems you specify will be equipped, nothing else.")
    echo("Example: ;gems 1 4 6 15 20")
    echo("Can also use with aliases or macro keys to switch between different gem profiles.")
    echo("You can also do \";gems none\" or \";gems clear\" to deactivate all gems without equipping any new ones.")
    return
end

local parts = {}
for word in input:gmatch("%S+") do
    table.insert(parts, word)
end

local clearing = input:find("none") or input:find("clear")

if not clearing then
    local all_numeric = #parts > 0
    for _, p in ipairs(parts) do
        if not p:match("^%d+$") then
            all_numeric = false
            break
        end
    end
    if not all_numeric then
        echo("You must provide at least one gem number to activate (equip), i.e. ;gems 1 4 6 15 20")
        return
    end
end

local new_gems = {}
if not clearing then
    for _, p in ipairs(parts) do
        table.insert(new_gems, tonumber(p))
    end
end

local requested_gems = clearing and {} or new_gems

-- Get currently equipped gems
local gem_list_text = quiet_command("gem list all", "Gemstone")
local equipped_gem_ids = {}
for _, line in ipairs(gem_list_text or {}) do
    if line:find("%(equipped%)") then
        local id = line:match("Gemstone (%d+):")
        if id then
            table.insert(equipped_gem_ids, tonumber(id))
        end
    end
end

-- Compute diffs
local function contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then return true end
    end
    return false
end

local common_gems = {}
for _, id in ipairs(equipped_gem_ids) do
    if contains(requested_gems, id) then
        table.insert(common_gems, id)
    end
end

local gems_to_unequip = {}
for _, id in ipairs(equipped_gem_ids) do
    if not contains(common_gems, id) then
        table.insert(gems_to_unequip, id)
    end
end

local gems_to_equip = {}
for _, id in ipairs(requested_gems) do
    if not contains(common_gems, id) then
        table.insert(gems_to_equip, id)
    end
end

-- Nothing to do?
if #gems_to_unequip == 0 and #gems_to_equip == 0 then
    if clearing then
        echo("Nothing to do. No active gems are equipped.")
    else
        local nums = {}
        for _, n in ipairs(requested_gems) do table.insert(nums, tostring(n)) end
        echo("Nothing to do. Already set to " .. table.concat(nums, ", ") .. ".")
    end
    return
end

if clearing then
    echo("Unequipping all active gems... Please wait...")
else
    local nums = {}
    for _, n in ipairs(requested_gems) do table.insert(nums, tostring(n)) end
    echo("Changing active gems to " .. table.concat(nums, ", ") .. "... Please wait...")
end

local errors = {}

-- Unequip
for _, index in ipairs(gems_to_unequip) do
    local res = quiet_command("gem unequip " .. index,
        "Focusing briefly, you release your attunement",
        "You don't currently have",
        "That is not a valid Gemstone number",
        "You cannot",
        "You still haven't recovered"
    )
    local joined = table.concat(res or {}, " ")
    if joined:find("You cannot") or joined:find("That is not a valid") or joined:find("You still haven't recovered") then
        table.insert(errors, "Could not unequip Gem #" .. index .. " - " .. joined:gsub("<[^>]+>", ""):match("^%s*(.-)%s*$"))
    end
end

-- Equip
if not clearing then
    for _, index in ipairs(gems_to_equip) do
        local res = quiet_command("gem equip " .. index,
            "Focusing briefly, you prepare your",
            "You cannot",
            "That is not a valid Gemstone number",
            "will apply the lesser binding to it"
        )
        local joined = table.concat(res or {}, " ")
        if joined:find("You cannot") or joined:find("That is not a valid") then
            table.insert(errors, "Could not equip Gem #" .. index .. " - " .. joined:gsub("<[^>]+>", ""):match("^%s*(.-)%s*$"))
        end
        if joined:find("will apply the lesser binding to it") then
            table.insert(errors, "Did not equip Gem #" .. index .. " as it would become lesser bound, run this script again within 30 seconds if you really meant to equip it!")
        end
    end
end

fput("gem list all")
for _, err in ipairs(errors) do
    echo(err)
end
echo("Done!")
