--- @revenant-script
--- name: dr_craft
--- version: 1.0.0
--- author: unknown
--- game: dr
--- description: General DR crafting framework - forging, outfitting, engineering, alchemy support
--- tags: crafting, forging, outfitting, engineering, alchemy
---
--- Ported from dr-craft.lic (Lich5) to Revenant Lua
---
--- Core crafting module providing shared crafting utilities for DR.
--- Manages crafting tools, books, patterns, and step sequences.
---
--- Usage:
---   Loaded by other crafting scripts. Can also be used standalone:
---   ;dr_craft <discipline> <recipe>

local settings = get_settings()
local bag = settings.crafting_container or "backpack"
local bag_items = settings.crafting_items_in_container or {}

local function get_crafting_item(item, container, items, belt)
    container = container or bag
    if belt and belt.name then
        local r = DRC.bput("get my " .. item .. " from my " .. belt.name,
            {"You get", "What were you", "You are already"})
        if r:find("You get") or r:find("already") then return true end
    end
    local r = DRC.bput("get my " .. item .. " from my " .. container,
        {"You get", "What were you", "You are already"})
    return r:find("You get") or r:find("already")
end

local function stow_crafting_item(item, container, belt)
    container = container or bag
    if belt and belt.name then
        local r = DRC.bput("put my " .. item .. " on my " .. belt.name,
            {"You put", "What were you", "That can't"})
        if r:find("You put") then return true end
    end
    DRC.bput("put my " .. item .. " in my " .. container,
        {"You put", "What were you"})
end

local function turn_to_page(section)
    if not section then
        echo("Failed to find recipe in book!")
        return false
    end
    DRC.bput("turn my book to " .. section, {"You turn", "already"})
    return true
end

local function study_book()
    DRC.bput("study my book", {"Roundtime"})
    waitrt()
end

-- Export functions for other scripts
DRCC = DRCC or {}
DRCC.get_crafting_item = get_crafting_item
DRCC.stow_crafting_item = stow_crafting_item

echo("=== DR Craft Framework ===")
echo("Crafting container: " .. bag)
echo("Crafting utilities loaded for use by other scripts.")
echo("")
echo("Supported disciplines: Forging, Outfitting, Engineering, Alchemy")
echo("Use specific crafting scripts (;forge, ;shape, ;sew, etc.) for actual crafting.")
